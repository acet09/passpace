import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../data/study_models.dart';
import '../data/study_timer.dart';
import '../data/study_timer_notifications.dart';
import 'design.dart';
import 'study_chart.dart';
import 'study_record_form.dart';
import 'study_delete_dialog.dart';
import 'study_timer_screen.dart';
import 'view_switch.dart';

class StudyRecordsScreen extends StatefulWidget {
  final Session session;
  final bool active;
  final DateTime Function() today;
  final VoidCallback? onOpenTimer;
  const StudyRecordsScreen(
    this.session, {
    super.key,
    required this.active,
    this.today = dayInSeoul,
    this.onOpenTimer,
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
  StudyStats? stats;
  bool loadingRecords = false, loadingStats = false, paging = false;
  bool hasNext = false, denied = false, covered = false;
  String? recordError, statsError, pageError;
  DateTime? uncertainDate;
  DateTime? uncertainOriginalDate;
  int? uncertainMinutes;
  int? uncertainRecordId;
  bool uncertainDelete = false;
  final checkedDates = <String>{};
  StudyTimer? timer;
  Timer? ticker;
  final notifications = StudyTimerNotifications();
  bool notificationOverlay = false;
  bool get canWrite =>
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
          if (!mounted) return;
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
      old.removeListener(timerChanged);
      unawaited(old.pause());
      old.dispose();
    }
    final user = widget.session.user;
    if (user == null || account == null) {
      timer = null;
      return;
    }
    final next = StudyTimer(
      widget.session.drafts,
      widget.session.origin,
      user.id,
    );
    timer = next;
    next.addListener(timerChanged);
    unawaited(next.restore());
  }

  void timerChanged() {
    if (!mounted) return;
    if (timer case final clock?) unawaited(notifications.sync(clock));
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
    if (clock == null) return;
    final elapsed = await notifications.elapsed();
    if (!mounted || !identical(timer, clock) || !identical(api, account)) {
      return;
    }
    if (elapsed != null) await clock.alignElapsed(elapsed);
    clock.tick();
    await notifications.sync(clock, refresh: true);
  }

  void clear() {
    records = [];
    stats = null;
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
    setState(() {
      epoch++;
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
    if (timer case final clock?) unawaited(clock.pause());
    setState(() {
      epoch++;
      denied = true;
      clear();
    });
  }

  bool permissionError(Object e) =>
      e is ApiError && (e.status == 401 || e.status == 403);

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
    setState(() {
      clear();
      loadingRecords = true;
      loadingStats = true;
    });
    await Future.wait([
      readRecords(api, turn, from, to),
      readStats(api, turn, from, to),
    ]);
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
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1000),
      lastDate: dayInSeoul(),
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: '공부기록 조회 기간 · 최대 366일',
      saveText: '조회',
    );
    if (!mounted || range == null || account == null || denied) return;
    final count =
        DateTime.utc(range.end.year, range.end.month, range.end.day)
            .difference(
              DateTime.utc(
                range.start.year,
                range.start.month,
                range.start.day,
              ),
            )
            .inDays +
        1;
    if (count > 366) {
      toast(context, '조회 기간은 최대 366일까지 선택해 주세요.');
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
        if (uncertainDate != null ||
            date.isBefore(start) ||
            date.isAfter(end)) {
          preset = 0;
          start = date;
          end = date;
        }
      });
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
    if (deleted == true) toast(context, '학습기록을 삭제했어요.');
    await load();
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
            onForbidden: forbid,
            canSave: () =>
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
            embedded: true,
            active: widget.active,
            notificationNotice: notifications.notice,
            onNotificationSettings: notifications.enabled
                ? notifications.openSettings
                : null,
            onForbidden: forbid,
            onUncertain: (date, minutes) {
              timerChanged();
            },
            onHistory: () => openRecords(0),
            onSaved: timerSaved,
          ),
        ),
      );
    }
    final listCount = view == 0 && !loadingRecords && recordError == null
        ? records.length
        : 0;
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: listCount + 2,
              itemBuilder: (context, index) {
                if (index == 0) return header();
                if (index <= listCount) return recordRow(records[index - 1]);
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
      Text(
        view == 0 ? '학습기록' : '개인 통계',
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      const HelpText('실제 공부시간을 기록하고 나의 학습 흐름을 확인해요.'),
      const SizedBox(height: 18),
      if (view == 0)
        OutlinedButton(
          onPressed: canWrite ? add : null,
          child: const Text('공부시간 추가'),
        ),
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
      const SizedBox(height: 20),
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
  );

  Widget recordRow(StudyRecord record) => Column(
    key: ValueKey('study-record-${record.id}'),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  start.year != end.year
                      ? '${record.date.year}년 ${shortDay(record.date)}'
                      : shortDay(record.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  durationLabel(record.minutes),
                  style: const TextStyle(
                    color: blue,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              record.subjectName?.trim().isNotEmpty == true
                  ? record.subjectName!
                  : record.taskId == null
                  ? '과목 미연결'
                  : '연결된 과목 이름 없음',
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              record.planId != null
                  ? '학습계획에 연결된 기록'
                  : record.inputMethod == 'MANUAL'
                  ? '기록한 공부시간'
                  : '공부시간 기록',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            if (record.inputMethod == 'MANUAL') ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: ValueKey('study-edit-${record.id}'),
                    onPressed: canWrite ? () => add(original: record) : null,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('수정'),
                  ),
                  OutlinedButton.icon(
                    key: ValueKey('study-delete-${record.id}'),
                    onPressed: canWrite ? () => remove(record) : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('삭제'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const Divider(),
    ],
  );

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
        if (!hasNext)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              '이 기간의 기록을 모두 확인했어요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget statistics() {
    if (loadingStats) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: '개인 통계 불러오는 중'),
        ),
      );
    }
    if (statsError != null) return failure(statsError!);
    return stats == null ? const SizedBox.shrink() : StudyChart(stats!);
  }
}
