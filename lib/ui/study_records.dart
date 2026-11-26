import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../data/study_history.dart';
import '../data/study_models.dart';
import '../data/study_timer.dart';
import '../data/study_timer_notifications.dart';
import 'design.dart';
import 'study_chart.dart';
import 'study_record_form.dart';
import 'study_delete_dialog.dart';
import 'study_range_picker.dart';
import 'study_timer_screen.dart';
import 'view_switch.dart';
import 'subject_color_picker.dart';

typedef _SubjectTime = ({String name, int minutes, List<StudyRecord> sources});

class StudyRecordsScreen extends StatefulWidget {
  final Session session;
  final bool active;
  final DateTime Function() today;
  final VoidCallback? onOpenTimer;
  final ValueChanged<StudyTimer?>? onTimerBound;
  final VoidCallback? onRecordsChanged;
  final StudySubjectColor? colorForSubject;
  final Color? Function(StudyRecord)? colorForRecord;
  const StudyRecordsScreen(
    this.session, {
    super.key,
    required this.active,
    this.today = dayInSeoul,
    this.onOpenTimer,
    this.onTimerBound,
    this.onRecordsChanged,
    this.colorForSubject,
    this.colorForRecord,
  });
  @override
  State<StudyRecordsScreen> createState() => StudyRecordsScreenState();
}

class StudyRecordsScreenState extends State<StudyRecordsScreen>
    with WidgetsBindingObserver {
  PassApi? account;
  int epoch = 0, view = 0, preset = 7, page = -1, pane = 0;
  late DateTime end = widget.today();
  late DateTime start = plusDays(end, -6);
  List<StudyRecord> records = [];
  final dayExpansion = <DateTime, bool>{};
  (int, DateTime, DateTime)? expansionRange;
  StudyStats? stats;
  List<_SubjectTime>? _subjectTimes;
  final _recordTaskChoices = <int, StudyTaskChoice>{};
  String? subjectTimesError;
  bool loadingRecords = false, loadingStats = false, paging = false;
  bool hasNext = false, denied = false, covered = false;
  String? recordError, statsError, pageError;
  DateTime? uncertainDate;
  DateTime? uncertainOriginalDate;
  int? uncertainMinutes;
  int? uncertainRecordId;
  bool uncertainDelete = false;
  final checkedDates = <String>{};
  final recordsScroll = ScrollController();
  StudyTimer? timer;
  Timer? ticker;
  final notifications = StudyTimerNotifications();
  bool notificationOverlay = false;
  bool get canWrite =>
      !widget.session.accountActionsBlocked &&
      uncertainDate == null &&
      timer?.restoring != true &&
      timer?.loadFailed != true &&
      timer?.locked != true;

  @override
  void initState() {
    super.initState();
    account = widget.session.account;
    widget.session.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    notifications.addListener(notificationChanged);
    unawaited(
      notifications.attach(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.session.accountActionsBlocked) return;
          widget.onOpenTimer?.call();
          unawaited(openNotificationTimer());
        });
      }),
    );
    bindTimer();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => timer?.tick());
    if (widget.active) load();
  }

  void bindTimer() {
    final old = timer;
    if (old != null) {
      notifications.clear();
      old.removeListener(timerChanged);
      unawaited(old.pause());
      old.dispose();
    }
    final user = widget.session.user, api = account;
    if (user == null || api == null) {
      timer = null;
      publishTimer(null);
      return;
    }
    final next = StudyTimer(
      widget.session.drafts,
      widget.session.origin,
      user.id,
      isPlanChanging: () =>
          api.changingPlan || widget.session.accountActionsBlocked,
    );
    timer = api.planTimer = next;
    next.addListener(timerChanged);
    unawaited(next.restore());
    publishTimer(next);
  }

  void publishTimer(StudyTimer? clock) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(timer, clock)) widget.onTimerBound?.call(clock);
    });
  }

  void timerChanged() {
    if (!mounted) return;
    if (!denied && timer != null && !widget.session.accountActionsBlocked) {
      unawaited(notifications.sync(timer!));
    }
    var inspect = false;
    setState(() {
      final clock = timer;
      if (clock?.phase == StudyTimerPhase.uncertain &&
          clock?.date != null &&
          uncertainDate == null) {
        uncertainDate = clock!.date;
        uncertainMinutes = clock.minutes;
        uncertainOriginalDate = null;
        uncertainRecordId = null;
        uncertainDelete = false;
        checkedDates.clear();
        preset = 0;
        view = 0;
        start = clock.date!;
        end = clock.date!;
        inspect = true;
      }
    });
    if (inspect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  void notificationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> resumeNotification() async {
    final clock = timer, api = account;
    if (clock == null || denied || widget.session.accountActionsBlocked) return;
    final elapsed = await notifications.elapsed();
    if (!mounted ||
        denied ||
        !identical(timer, clock) ||
        !identical(api, account)) {
      return;
    }
    if (elapsed != null) await clock.alignElapsed(elapsed);
    clock.tick();
    await notifications.sync(clock, refresh: true);
  }

  Future<bool> prepareForWithdrawal() async {
    final clock = timer, api = account;
    if (clock == null || api == null) return false;
    bool ready() =>
        mounted &&
        identical(timer, clock) &&
        identical(widget.session.account, api) &&
        !api.changingPlan &&
        !covered &&
        !notificationOverlay &&
        !denied &&
        uncertainDate == null &&
        clock.available &&
        clock.error == null &&
        !clock.locked;
    if (!ready()) return false;
    try {
      if (!await clock.pause().timeout(const Duration(seconds: 5)) ||
          !ready()) {
        return false;
      }
      return await notifications.stopForWithdrawal().timeout(
            const Duration(seconds: 5),
          ) &&
          ready();
    } on TimeoutException {
      return false;
    }
  }

  void clear() {
    records = [];
    _recordTaskChoices.clear();
    stats = null;
    _subjectTimes = null;
    subjectTimesError = null;
    page = -1;
    hasNext = false;
    recordError = null;
    statsError = null;
    pageError = null;
    loadingRecords = false;
    loadingStats = false;
    paging = false;
  }

  void accountChanged() {
    if (!mounted || identical(account, widget.session.account)) return;
    if (identical(account?.planTimer, timer)) account?.planTimer = null;
    setState(() {
      epoch++;
      dayExpansion.clear();
      account = widget.session.account;
      denied = false;
      uncertainDate = null;
      uncertainMinutes = null;
      uncertainRecordId = null;
      uncertainDelete = false;
      uncertainOriginalDate = null;
      checkedDates.clear();
      clear();
      bindTimer();
    });
    if (widget.active && !covered) load();
  }

  @override
  void didUpdateWidget(StudyRecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(accountChanged);
      widget.session.addListener(accountChanged);
    }
    if (!identical(account, widget.session.account)) accountChanged();
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        showTimer();
      } else {
        epoch++;
        clear();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(resumeNotification());
    if (state == AppLifecycleState.resumed &&
        mounted &&
        widget.active &&
        !covered &&
        ModalRoute.of(context)?.isCurrent == true) {
      load();
    }
  }

  @override
  void dispose() {
    recordsScroll.dispose();
    if (identical(account?.planTimer, timer)) account?.planTimer = null;
    notifications.removeListener(notificationChanged);
    notifications.dispose();
    ticker?.cancel();
    timer?.removeListener(timerChanged);
    if (timer case final clock?) {
      unawaited(clock.pause());
      clock.dispose();
    }
    epoch++;
    widget.session.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool current(PassApi api, int turn) =>
      mounted &&
      widget.active &&
      pane != 0 &&
      !covered &&
      !denied &&
      turn == epoch &&
      identical(account, api) &&
      identical(widget.session.account, api);

  void forbid() {
    if (!mounted) return;
    notifications.clear();
    if (timer case final clock?) unawaited(clock.pause());
    setState(() {
      epoch++;
      denied = true;
      clear();
    });
  }

  bool permissionError(Object e) =>
      e is ApiError && (e.status == 401 || e.status == 403);

  StudyTaskChoice? _matchingTask(StudyRecord record, StudyTaskChoice? task) {
    if (task == null ||
        record.planId != null && task.planId != record.planId ||
        record.subjectId != null &&
            task.subjectId != null &&
            task.subjectId != record.subjectId) {
      return null;
    }
    return task;
  }

  Color? _recordColor(StudyRecord record) {
    final direct = widget.colorForRecord?.call(record);
    if (direct != null) return direct;
    final task = _matchingTask(record, _recordTaskChoices[record.taskId]);
    final name = record.subjectName?.trim();
    if (task == null ||
        name != null && name.isNotEmpty && name != task.subjectName?.trim()) {
      return null;
    }
    return widget.colorForSubject?.call(task);
  }

  Set<int> _unresolvedColorTasks(Iterable<StudyRecord> history) => {
    if (widget.colorForRecord != null && widget.colorForSubject != null)
      for (final record in history)
        if (record.taskId case final id?
            when !_recordTaskChoices.containsKey(id) &&
                widget.colorForRecord!(record) == null)
          id,
  };

  Future<void> _loadRecordColors(
    PassApi api,
    int turn,
    List<StudyRecord> items,
  ) async {
    final taskIds = _unresolvedColorTasks(items);
    if (taskIds.isEmpty) return;
    try {
      final tasks = await readStudyTaskChoices(
        api,
        includeReplaced: true,
        taskIds: taskIds,
        isCurrent: () => current(api, turn),
      );
      if (tasks == null || !current(api, turn)) return;
      setState(
        () => _recordTaskChoices.addEntries(
          tasks.map((task) => MapEntry(task.id, task)),
        ),
      );
    } catch (_) {
      // History remains usable when optional color metadata is unavailable.
    }
  }

  Future<void> load() async {
    final api = account;
    if (!mounted ||
        !widget.active ||
        pane == 0 ||
        covered ||
        denied ||
        api == null) {
      return;
    }
    if (preset != 0 && uncertainDate == null) {
      end = widget.today();
      start = plusDays(end, 1 - preset);
    }
    final turn = ++epoch, from = start, to = end;
    final range = (preset, from, to);
    if (expansionRange != range) {
      dayExpansion.clear();
      expansionRange = range;
    }
    setState(() {
      clear();
      loadingRecords = true;
      loadingStats = true;
    });
    await Future.wait([
      if (view == 0) readRecords(api, turn, from, to),
      readStats(api, turn, from, to),
      if (view != 0) readSubjectTimes(api, turn, from, to),
    ]);
  }

  Future<void> readSubjectTimes(
    PassApi api,
    int turn,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final history = await readStudyHistory(
        api,
        from,
        to,
        pageSize: 100,
        isCurrent: () => current(api, turn),
      );
      if (history == null || !current(api, turn)) return;
      String? subjectName(String? value) {
        final name = value?.trim();
        return name == null || name.isEmpty ? null : name;
      }

      final knownNames = <int, String>{};
      for (final record in history) {
        final id = record.subjectId, name = subjectName(record.subjectName);
        if (id != null && name != null) {
          knownNames.putIfAbsent(id, () => name);
        }
      }
      final missing = {
        for (final record in history)
          if (subjectName(record.subjectName) == null &&
              !knownNames.containsKey(record.subjectId) &&
              record.taskId != null)
            record.taskId!,
      };
      final taskIds = {...missing, ..._unresolvedColorTasks(history)};
      final linkedTasks = <int, StudyTaskChoice>{};
      if (taskIds.isNotEmpty) {
        try {
          final found = await readStudyTaskChoices(
            api,
            includeReplaced: true,
            taskIds: taskIds,
            isCurrent: () => current(api, turn),
          );
          if (found == null) return;
          for (final task in found) {
            linkedTasks[task.id] = task;
          }
        } catch (error) {
          if (missing.isNotEmpty && permissionError(error)) rethrow;
          // Keep the confirmed minutes even when optional task details are unavailable.
        }
      }
      if (!current(api, turn)) return;
      final totals = <(int?, String), _SubjectTime>{};
      for (final record in history) {
        final linked = missing.contains(record.taskId)
            ? _matchingTask(record, linkedTasks[record.taskId])
            : null;
        final id = record.subjectId ?? linked?.subjectId;
        final name =
            subjectName(record.subjectName) ??
            knownNames[id] ??
            subjectName(linked?.subjectName);
        final label =
            name ??
            (record.taskId == null && id == null ? '과목 미연결' : '과목 이름 없음');
        final key = (id, id == null ? label : '');
        final prior = totals[key];
        final sources = prior?.sources ?? <StudyRecord>[];
        sources.add(record);
        totals[key] = (
          name: name ?? prior?.name ?? label,
          minutes: (prior?.minutes ?? 0) + record.minutes,
          sources: sources,
        );
      }
      final ordered = totals.values.toList()
        ..sort((a, b) {
          final duration = b.minutes.compareTo(a.minutes);
          return duration != 0 ? duration : a.name.compareTo(b.name);
        });
      setState(() {
        _recordTaskChoices.addAll(linkedTasks);
        _subjectTimes = ordered;
      });
    } catch (e) {
      if (!current(api, turn)) return;
      if (permissionError(e)) {
        forbid();
        return;
      }
      setState(() => subjectTimesError = friendly(e));
    }
  }

  Future<void> readRecords(
    PassApi api,
    int turn,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final result = await api.studySessions(from, to);
      if (!current(api, turn)) return;
      if (result.page != 0 ||
          result.items.any(
            (r) => r.date.isBefore(from) || r.date.isAfter(to),
          )) {
        throw const FormatException('Unexpected study page');
      }
      setState(() {
        records = result.items;
        markInspectedDate(from, to, result.hasNext);
        page = result.page;
        hasNext = result.hasNext;
        loadingRecords = false;
      });
      unawaited(_loadRecordColors(api, turn, result.items));
    } catch (e) {
      if (!current(api, turn)) return;
      if (permissionError(e)) {
        forbid();
        return;
      }
      setState(() {
        loadingRecords = false;
        recordError = friendly(e);
      });
    }
  }

  Future<void> readStats(
    PassApi api,
    int turn,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final result = await api.studyStats(from, to);
      if (!current(api, turn)) return;
      if (result.start != from || result.end != to) {
        throw const FormatException('Unexpected study range');
      }
      setState(() {
        stats = result;
        loadingStats = false;
      });
    } catch (e) {
      if (!current(api, turn)) return;
      if (permissionError(e)) {
        forbid();
        return;
      }
      setState(() {
        loadingStats = false;
        statsError = friendly(e);
      });
    }
  }

  Future<void> more() async {
    final api = account;
    if (api == null || denied || paging || !hasNext || page >= 10000) return;
    final turn = epoch, next = page + 1;
    final from = start, to = end;
    setState(() {
      paging = true;
      pageError = null;
    });
    try {
      final result = await api.studySessions(from, to, page: next);
      if (!current(api, turn)) return;
      if (result.page != next ||
          result.items.any(
            (r) => r.date.isBefore(from) || r.date.isAfter(to),
          )) {
        throw const FormatException('Unexpected study page');
      }
      final ids = records.map((r) => r.id).toSet();
      setState(() {
        records = [...records, ...result.items.where((r) => ids.add(r.id))];
        page = next;
        hasNext = result.hasNext;
        markInspectedDate(from, to, result.hasNext);
        paging = false;
      });
      unawaited(_loadRecordColors(api, turn, result.items));
    } catch (e) {
      if (!current(api, turn)) return;
      if (permissionError(e)) {
        forbid();
        return;
      }
      setState(() {
        paging = false;
        pageError = friendly(e);
      });
    }
  }

  void period(int days) {
    setState(() {
      preset = days;
      end = widget.today();
      start = plusDays(end, 1 - days);
    });
    load();
  }

  Future<void> custom() async {
    final api = account;
    if (api == null || denied || uncertainDate != null) return;
    final range = await pickStudyRange(
      context,
      initial: DateTimeRange(start: start, end: end),
      today: widget.today(),
    );
    if (!mounted ||
        range == null ||
        !identical(account, api) ||
        denied ||
        uncertainDate != null) {
      return;
    }
    setState(() {
      preset = 0;
      start = range.start;
      end = range.end;
    });
    load();
  }

  Future<void> add({StudyRecord? original}) async {
    final api = account;
    if (api == null || denied || covered || !canWrite) return;
    setState(() {
      covered = true;
      epoch++;
      loadingRecords = false;
      loadingStats = false;
      paging = false;
    });
    final result = await Navigator.push<StudyRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => StudyRecordForm(
          widget.session,
          record: original,
          colorForSubject: widget.colorForSubject,
          onForbidden: forbid,
          onUncertain: (date, minutes) {
            if (mounted && identical(api, widget.session.account)) {
              setState(() {
                uncertainDate = date;
                uncertainMinutes = minutes;
                uncertainOriginalDate = original?.date;
                uncertainRecordId = original?.id;
                uncertainDelete = false;
                checkedDates.clear();
              });
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() => covered = false);
    if (!identical(api, widget.session.account) || denied) {
      load();
      return;
    }
    final date = result?.date ?? uncertainDate;
    if (date != null) {
      setState(() {
        view = 0;
        dayExpansion[date] = true;
        if (uncertainDate != null ||
            date.isBefore(start) ||
            date.isAfter(end)) {
          preset = 0;
          start = date;
          end = date;
        }
      });
    }
    if (result != null || uncertainDate != null) {
      widget.onRecordsChanged?.call();
    }
    if (result != null) {
      toast(
        context,
        original == null
            ? '공부시간 ${durationLabel(result.minutes)}을 저장했어요.'
            : '공부시간을 ${durationLabel(result.minutes)}으로 수정했어요.',
      );
    }
    await load();
  }

  Future<void> remove(StudyRecord record) async {
    final api = account;
    if (api == null || denied || covered || !canWrite) return;
    setState(() {
      covered = true;
      epoch++;
      loadingRecords = false;
      loadingStats = false;
      paging = false;
    });
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudyDeleteDialog(
        widget.session,
        api,
        record,
        onForbidden: forbid,
        onUncertain: () {
          if (mounted && identical(api, widget.session.account)) {
            setState(() {
              uncertainDate = record.date;
              uncertainMinutes = record.minutes;
              uncertainOriginalDate = null;
              uncertainRecordId = record.id;
              uncertainDelete = true;
              checkedDates.clear();
            });
          }
        },
      ),
    );
    if (!mounted) return;
    setState(() => covered = false);
    if (!identical(api, widget.session.account) || denied) {
      load();
      return;
    }
    if (uncertainDate != null) {
      setState(() {
        preset = 0;
        view = 0;
        start = uncertainDate!;
        end = uncertainDate!;
      });
    }
    if (deleted == true || uncertainDate != null) {
      widget.onRecordsChanged?.call();
    }
    if (deleted == true) toast(context, '학습기록을 삭제했어요.');
    await load();
  }

  Future<bool> selectPlannedTask(
    SavedPlan plan,
    StudyTask task, {
    required bool Function() isCurrent,
  }) async {
    final api = account;
    final clock = timer;
    if (api == null ||
        clock == null ||
        covered ||
        denied ||
        !canWrite ||
        !clock.available) {
      throw const ApiError('기록 화면에서 현재 타이머나 저장 상태를 먼저 확인해 주세요.');
    }
    final planId = plan.id;
    if (planId == null || isoDay(task.date) != isoDay(widget.today())) {
      throw const ApiError('오늘 학습계획을 새로고침한 뒤 다시 선택해 주세요.');
    }
    StudyTaskChoice? match;
    for (var page = 0; ; page++) {
      final result = await api.studyPlanTasks(date: task.date, page: page);
      if (!mounted ||
          !isCurrent() ||
          !identical(api, account) ||
          !identical(timer, clock)) {
        return false;
      }
      if (result.page != page || (result.hasNext && result.items.isEmpty)) {
        throw const ApiError('과목 목록을 확인하지 못했어요. 다시 시도해 주세요.');
      }
      for (final choice in result.items) {
        if (choice.status != 'ACTIVE' ||
            choice.planId != planId ||
            choice.planVersion != plan.version ||
            task.id != null && choice.id != task.id ||
            choice.scheduledDate == null ||
            isoDay(choice.scheduledDate!) != isoDay(task.date) ||
            choice.certificationName?.trim() != task.exam.trim() ||
            choice.subjectName?.trim() != task.subject.trim()) {
          continue;
        }
        if (match != null && match.id != choice.id) {
          throw const ApiError('같은 이름의 계획 항목이 여러 개 있어요. 기록에서 과목을 선택해 주세요.');
        }
        match = choice;
      }
      if (!result.hasNext) break;
    }
    if (match == null || isoDay(task.date) != isoDay(widget.today())) {
      throw const ApiError('현재 계획과 과목을 확인하지 못했어요. 홈을 새로고침한 뒤 다시 시도해 주세요.');
    }
    if (covered || denied || !canWrite || !clock.available) {
      throw const ApiError('기록 화면에서 현재 타이머나 저장 상태를 먼저 확인해 주세요.');
    }
    if (clock.task?.id == match.id &&
        clock.task?.planVersion == match.planVersion &&
        !clock.dayEnded) {
      return true;
    }
    if (clock.phase == StudyTimerPhase.running ||
        clock.elapsed > Duration.zero ||
        clock.dayEnded) {
      throw const ApiError('기존 측정 시간이 남아 있어요. 기록 탭에서 저장하거나 정리한 뒤 과목을 바꿔 주세요.');
    }
    if (!await clock.choose(match)) {
      throw const ApiError('선택한 과목을 저장하지 못했어요. 기록 탭에서 타이머를 확인해 주세요.');
    }
    return mounted && isCurrent() && identical(timer, clock);
  }

  void showTimer() {
    if (!mounted || covered) return;
    if (uncertainDate != null && timer?.phase != StudyTimerPhase.uncertain) {
      openRecords(0);
      return;
    }
    setState(() {
      pane = 0;
      epoch++;
      clear();
    });
  }

  Future<void> openNotificationTimer() async {
    final clock = timer, api = account;
    if (!mounted ||
        clock == null ||
        api == null ||
        denied ||
        notificationOverlay) {
      return;
    }
    if (!Navigator.of(context).canPop()) {
      showTimer();
      return;
    }
    notificationOverlay = true;
    try {
      final result = await Navigator.push<StudyRecord>(
        context,
        MaterialPageRoute(
          builder: (_) => StudyTimerScreen(
            widget.session,
            clock,
            colorForSubject: widget.colorForSubject,
            onForbidden: forbid,
            canSave: () =>
                !widget.session.accountActionsBlocked &&
                !covered &&
                uncertainDate == null &&
                !denied &&
                identical(api, widget.session.account),
            notificationNotice: notifications.notice,
            onNotificationSettings: notifications.openSettings,
            onUncertain: (date, minutes) {
              if (mounted && identical(api, widget.session.account)) {
                timerChanged();
              }
            },
            onSaved: (record) {
              if (mounted &&
                  identical(api, widget.session.account) &&
                  identical(clock, timer)) {
                timerSaved(record);
              }
            },
          ),
        ),
      );
      if (mounted && result != null && identical(api, widget.session.account)) {
        timerSaved(result);
      }
    } finally {
      notificationOverlay = false;
    }
  }

  void openRecords(int selectedView) {
    if (!mounted || covered) return;
    setState(() {
      if (selectedView == 0 && pane != 1) dayExpansion.clear();
      pane = selectedView + 1;
      view = selectedView;
      epoch++;
      clear();
    });
    load();
  }

  void timerSaved(StudyRecord record) {
    if (!mounted) return;
    toast(context, '공부시간 ${durationLabel(record.minutes)}을 저장했어요.');
    setState(() {
      if (record.date.isBefore(start) || record.date.isAfter(end)) {
        preset = 0;
        start = record.date;
        end = record.date;
      }
    });
    if (pane != 0) load();
  }

  Widget withViewSwitch(Widget body) => Column(
    children: [
      WidthLimit(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: ViewSwitch(
            key: const ValueKey('study-pane-switch'),
            selected: pane,
            options: [
              ViewSwitchOption(
                '타이머',
                const ValueKey('study-timer-open'),
                timer != null &&
                        (uncertainDate == null ||
                            timer?.phase == StudyTimerPhase.uncertain)
                    ? showTimer
                    : null,
              ),
              ViewSwitchOption(
                '학습기록',
                const ValueKey('open-study-history'),
                () => openRecords(0),
              ),
              ViewSwitchOption(
                '통계',
                const ValueKey('open-study-statistics'),
                uncertainDate == null ? () => openRecords(1) : null,
              ),
            ],
          ),
        ),
      ),
      Expanded(child: body),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (denied || account == null) {
      return ScrollBody(
        children: [
          EmptyPanel(
            Icons.lock_outline,
            '기록을 확인할 수 없어요',
            '로그인 상태와 권한을 다시 확인해 주세요.',
            action: '다시 로그인',
            onTap: widget.session.logout,
          ),
        ],
      );
    }
    final clock = timer;
    if (pane == 0 && clock != null) {
      return withViewSwitch(
        TickerMode(
          enabled: widget.active,
          child: StudyTimerScreen(
            widget.session,
            clock,
            key: ObjectKey(clock),
            colorForSubject: widget.colorForSubject,
            embedded: true,
            active: widget.active,
            notificationNotice: notifications.notice,
            onNotificationSettings: notifications.enabled
                ? notifications.openSettings
                : null,
            onForbidden: forbid,
            canSave: () => !widget.session.accountActionsBlocked,
            onUncertain: (date, minutes) {
              timerChanged();
            },
            onHistory: () => openRecords(0),
            onSaved: timerSaved,
          ),
        ),
      );
    }
    final byDay = <DateTime, List<StudyRecord>>{};
    if (view == 0 && !loadingRecords && recordError == null) {
      for (final record in records) {
        (byDay[record.date] ??= []).add(record);
      }
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    bool isExpanded(DateTime day) => dayExpansion[day] ?? (day == days.first);
    final totals = {
      for (final day in stats?.days ?? <StudyDay>[]) day.date: day.minutes,
    };
    final rows = <(DateTime, StudyRecord?)>[
      for (final day in days) ...[
        (day, null),
        if (isExpanded(day))
          for (final record in byDay[day]!) (day, record),
      ],
    ];
    return withViewSwitch(
      PopScope(
        canPop: !widget.active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.active) showTimer();
        },
        child: WidthLimit(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView.builder(
              key: ValueKey('study-view-$view'),
              controller: view == 0 ? recordsScroll : null,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: rows.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) return header();
                if (index <= rows.length) {
                  final (day, record) = rows[index - 1];
                  if (record != null) return recordRow(record);
                  final minutes =
                      totals[day] ??
                      byDay[day]!.fold<int>(0, (n, r) => n + r.minutes);
                  return dayRow(
                    day,
                    minutes,
                    expanded: isExpanded(day),
                    partial: totals[day] == null && hasNext && day == days.last,
                  );
                }
                return view == 0 ? historyFooter() : statistics();
              },
            ),
          ),
        ),
      ),
    );
  }

  void markInspectedDate(DateTime from, DateTime to, bool morePages) {
    if (uncertainDate == null || from != to) return;
    final found =
        uncertainRecordId != null &&
        records.any((r) => r.id == uncertainRecordId);
    if (found || !morePages) checkedDates.add(isoDay(from));
  }

  void inspectUncertainDate(DateTime date) {
    if (!mounted ||
        uncertainDate == null ||
        account == null ||
        denied ||
        covered) {
      return;
    }
    setState(() {
      preset = 0;
      start = date;
      end = date;
      dayExpansion[date] = true;
      view = 0;
    });
    load();
  }

  bool get inspectedUncertain =>
      uncertainDate != null &&
      checkedDates.contains(isoDay(uncertainDate!)) &&
      (uncertainOriginalDate == null ||
          checkedDates.contains(isoDay(uncertainOriginalDate!)));

  Widget header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (uncertainDate != null) ...[
        AlertText(
          uncertainDelete
              ? '${isoDay(uncertainDate!)} · $uncertainMinutes분 기록의 삭제 결과를 확인해 주세요. 목록에서 해당 기록을 찾거나 끝까지 확인한 뒤 계속해 주세요.'
              : uncertainOriginalDate == null
              ? '${isoDay(uncertainDate!)} · $uncertainMinutes분의 저장 결과를 확인해 주세요. 같은 기록이 있는지 목록을 먼저 확인한 후 추가해 주세요.'
              : '수정 결과를 확인해 주세요. 수정 전 ${isoDay(uncertainOriginalDate!)}과 요청한 ${isoDay(uncertainDate!)} · $uncertainMinutes분의 기록을 확인한 후 계속해 주세요.',
        ),
        if (uncertainOriginalDate != null &&
            uncertainOriginalDate != uncertainDate)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () {
                  final date = uncertainOriginalDate;
                  if (date != null) inspectUncertainDate(date);
                },
                child: const Text('수정 전 날짜 보기'),
              ),
              OutlinedButton(
                onPressed: () {
                  final date = uncertainDate;
                  if (date != null) inspectUncertainDate(date);
                },
                child: const Text('수정 요청 날짜 보기'),
              ),
            ],
          ),
        if (!inspectedUncertain)
          const HelpText('확인할 기록이 보이지 않으면 ‘이전 기록 더 보기’로 이어서 확인해 주세요.'),
        OutlinedButton(
          onPressed:
              !loadingRecords &&
                  recordError == null &&
                  inspectedUncertain &&
                  timer?.storing != true
              ? () async {
                  final api = account;
                  final clock = timer;
                  final session = widget.session;
                  if (clock?.phase == StudyTimerPhase.uncertain) {
                    final found = await showDialog<bool>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: const Text('타이머 기록 확인'),
                        content: const Text(
                          '목록에서 방금 저장한 기록을 찾았나요? 기록이 없다면 측정한 시간을 유지해요. 다시 저장하기 전에는 중복 기록이 없는지 확인해 주세요.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: const Text('다시 확인'),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(dialog, false),
                            child: const Text('기록 없음 · 측정 유지'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialog, true),
                            child: const Text('저장된 기록 확인'),
                          ),
                        ],
                      ),
                    );
                    if (!mounted ||
                        found == null ||
                        !identical(api, widget.session.account) ||
                        !identical(clock, timer)) {
                      return;
                    }
                    final subject = clock!.task;
                    final done = found
                        ? await clock.reset(verified: true)
                        : await clock.retainAfterInspection();
                    if (!done) return;
                    if (found) {
                      await restoreSavedTimerSubject(
                        clock,
                        subject,
                        session,
                        api,
                      );
                    }
                  }
                  if (!mounted || !identical(api, widget.session.account)) {
                    return;
                  }
                  if (recordsScroll.hasClients) recordsScroll.jumpTo(0);
                  setState(() {
                    uncertainDate = null;
                    uncertainMinutes = null;
                    uncertainOriginalDate = null;
                    uncertainRecordId = null;
                    uncertainDelete = false;
                    checkedDates.clear();
                  });
                }
              : null,
          child: const Text('기록 확인 완료'),
        ),
      ],
      if (view == 0)
        historyToolbar()
      else ...[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final n in [7, 30])
              ChoiceChip(
                label: Text('최근 $n일'),
                selected: preset == n,
                onSelected: uncertainDate != null ? null : (_) => period(n),
              ),
            ChoiceChip(
              label: const Text('기간 선택'),
              selected: preset == 0,
              onSelected: uncertainDate != null ? null : (_) => custom(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${isoDay(start)} ~ ${isoDay(end)}',
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 18),
      ],
    ],
  );

  Widget historyToolbar() {
    final includeYear =
        start.year != end.year || end.year != widget.today().year;
    String date(DateTime day) {
      final iso = isoDay(day);
      return (includeYear ? iso : iso.substring(5)).replaceAll('-', '.');
    }

    final range = start == end ? date(start) : '${date(start)} – ${date(end)}';
    final label = preset == 0 ? range : '최근 $preset일';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          PopupMenuButton<int>(
            key: const ValueKey('history-period'),
            tooltip: '조회 기간 변경',
            enabled: uncertainDate == null,
            initialValue: preset,
            onSelected: (days) {
              if (uncertainDate != null) return;
              if (days == 0) {
                custom();
              } else if (days != preset) {
                period(days);
              }
            },
            itemBuilder: (_) => [
              for (final days in [7, 30, 0])
                CheckedPopupMenuItem<int>(
                  key: ValueKey('history-days-$days'),
                  value: days,
                  checked: days == preset,
                  child: Text(days == 0 ? '직접 선택' : '최근 $days일'),
                ),
            ],
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 18, color: muted),
                ],
              ),
            ),
          ),
          Tooltip(
            message: '공부시간 추가',
            child: TextButton.icon(
              key: const ValueKey('history-add'),
              onPressed: canWrite ? add : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('추가'),
            ),
          ),
        ],
      ),
    );
  }

  Widget dayRow(
    DateTime day,
    int minutes, {
    required bool partial,
    required bool expanded,
  }) {
    final date = start.year == end.year
        ? shortDay(day)
        : '${day.year}년 ${shortDay(day)}';
    return Semantics(
      expanded: expanded,
      child: ListTile(
        key: ValueKey('history-day-${isoDay(day)}'),
        contentPadding: EdgeInsets.zero,
        shape: const Border(top: BorderSide(color: line)),
        onTap: () => setState(() {
          dayExpansion[day] = !expanded;
        }),
        title: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              '$date · ${weekdays[day.weekday - 1]}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '총 ${durationLabel(minutes)}${partial ? ' 이상' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        trailing: Icon(
          expanded ? Icons.expand_less : Icons.expand_more,
          size: 20,
        ),
      ),
    );
  }

  Widget recordRow(StudyRecord record) {
    final hasName = record.subjectName?.trim().isNotEmpty == true;
    final color = hasName ? _recordColor(record) : null;
    final name = hasName
        ? record.subjectName!
        : record.taskId == null
        ? '과목 미연결'
        : '연결된 과목 이름 없음';
    final editable = record.inputMethod == 'MANUAL';
    final entry = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
        child: Row(
          children: [
            SizedBox(
              width: 10,
              child: color == null
                  ? null
                  : SubjectColorDot(
                      color,
                      markerKey: ValueKey('study-record-color-${record.id}'),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.tight,
              child: Text(
                durationLabel(record.minutes),
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 18,
              child: editable
                  ? const Icon(Icons.more_horiz, size: 18, color: muted)
                  : null,
            ),
          ],
        ),
      ),
    );
    return Material(
      key: ValueKey('study-record-${record.id}'),
      color: const Color(0xfff5f7fa),
      child: editable
          ? PopupMenuButton<bool>(
              key: ValueKey('study-actions-${record.id}'),
              tooltip: '기록 관리',
              enabled: canWrite,
              onSelected: (edit) {
                if (!canWrite) return;
                if (edit) {
                  add(original: record);
                } else {
                  remove(record);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: true,
                  key: ValueKey('study-edit-${record.id}'),
                  child: const Text('기록 수정'),
                ),
                PopupMenuItem(
                  value: false,
                  key: ValueKey('study-delete-${record.id}'),
                  child: const Text('기록 삭제'),
                ),
              ],
              child: entry,
            )
          : entry,
    );
  }

  Widget failure(String message) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AlertText(message),
      OutlinedButton.icon(
        onPressed: load,
        icon: const Icon(Icons.refresh),
        label: const Text('다시 불러오기'),
      ),
    ],
  );

  Widget historyFooter() {
    if (loadingRecords) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: '학습기록 불러오는 중'),
        ),
      );
    }
    if (recordError != null) return failure(recordError!);
    if (records.isEmpty) {
      return const EmptyPanel(
        Icons.history_rounded,
        '이 기간에 저장한 기록이 없어요',
        '공부한 날짜와 시간을 추가하면 이곳에 모여요.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pageError != null) AlertText(pageError!),
        if (hasNext && page < 10000)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton(
              onPressed: paging ? null : more,
              child: Text(paging ? '불러오는 중…' : '이전 기록 더 보기'),
            ),
          ),
      ],
    );
  }

  Widget statistics() {
    if (subjectTimesError != null && subjectTimesError == statsError) {
      return failure(subjectTimesError!);
    }
    final breakdown = subjectBreakdown();
    if (stats case final value? when !loadingStats && statsError == null) {
      return StudyChart(
        value,
        breakdown: breakdown,
        subjectsByDay: _dailySubjects(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadingStats)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: CircularProgressIndicator(semanticsLabel: '개인 통계 불러오는 중'),
            ),
          )
        else if (statsError != null)
          failure(statsError!),
        const SizedBox(height: 18),
        breakdown,
      ],
    );
  }

  Map<DateTime, List<StudySubjectSlice>>? _dailySubjects() {
    final times = _subjectTimes;
    if (times == null) return null;
    final days = <DateTime, List<StudySubjectSlice>>{};
    for (final subject in times) {
      final color = _subjectColor(subject);
      final minutesByDay = <DateTime, int>{};
      for (final record in subject.sources) {
        minutesByDay.update(
          record.date,
          (minutes) => minutes + record.minutes,
          ifAbsent: () => record.minutes,
        );
      }
      for (final entry in minutesByDay.entries) {
        (days[entry.key] ??= []).add((
          name: subject.name,
          minutes: entry.value,
          color: color,
        ));
      }
    }
    return days;
  }

  Color? _subjectColor(_SubjectTime subject) {
    final colors = subject.sources.map(_recordColor).toSet();
    return colors.length == 1 ? colors.single : null;
  }

  Widget subjectBreakdown() {
    final times = _subjectTimes;
    final longest = times?.firstOrNull?.minutes ?? 1;
    return Column(
      key: const ValueKey('study-subject-breakdown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading('과목별 공부시간'),
        if (subjectTimesError != null)
          failure(subjectTimesError!)
        else if (times == null)
          const HelpText('과목별 공부시간을 불러오는 중이에요.')
        else if (times.isEmpty)
          const HelpText('선택한 기간에 저장한 학습기록이 없어요.')
        else ...[
          for (final (index, subject) in times.indexed) ...[
            if (index != 0) const Divider(height: 1),
            _subjectTimeRow(index, subject, longest),
          ],
        ],
        if (times?.any((subject) => subject.name == '과목 미연결') == true)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => openRecords(0),
              icon: const Icon(Icons.link_outlined, size: 18),
              label: const Text('미연결 기록 확인'),
            ),
          ),
      ],
    );
  }

  Widget _subjectTimeRow(int index, _SubjectTime subject, int longest) {
    final color = _subjectColor(subject);
    final time = durationLabel(subject.minutes);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (color != null) ...[
                SubjectColorDot(
                  color,
                  markerKey: ValueKey('study-subject-color-$index'),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(flex: 3, child: Text(subject.name)),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  time,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: LinearProgressIndicator(
              key: ValueKey('study-subject-bar-$index'),
              value: longest > 0 ? subject.minutes / longest : 0,
              minHeight: 5,
              borderRadius: BorderRadius.circular(8),
              color: color ?? muted,
              backgroundColor: color == null ? line : subjectColorTrack(color),
            ),
          ),
        ],
      ),
    );
  }
}
