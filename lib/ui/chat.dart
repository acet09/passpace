import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/chat_plan.dart';
import '../data/models.dart';
import 'chat_plan.dart';
import 'design.dart';

class ChatScreen extends StatefulWidget {
  final PassApi api;

  /// 채팅 안에서 만든 계획을 저장했을 때 (홈·학습계획 새로고침용).
  final VoidCallback? onPlanSaved;
  const ChatScreen(this.api, {super.key, this.onPlanSaved});
  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class _Turn {
  final String question;
  Reply? reply;
  ChatPlanSetup? plan;
  String? planError, planNote;
  bool planLoading = false, planRetry = false;
  final key = GlobalKey();
  _Turn(this.question);
}

class ChatScreenState extends State<ChatScreen> {
  final turns = <_Turn>[];
  final draft = TextEditingController(), scroll = ScrollController();
  final planInputs = ChatPlanInputs();
  int? conversation;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    draft.dispose();
    scroll.dispose();
    planInputs.dispose();
    super.dispose();
  }

  void prepareQuestion(String question) {
    draft.text = draft.text.trim().isEmpty
        ? question
        : '${draft.text}\n$question';
    draft.selection = TextSelection.collapsed(offset: draft.text.length);
  }

  void bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 계획 카드는 길어서 맨 아래 대신 질문부터 보이게 올린다.
  void _reveal(_Turn turn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = turn.key.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> send([String? preset]) async {
    final text = (preset ?? draft.text).trim();
    if (busy || text.isEmpty) return;
    final turn = _Turn(text);
    FocusScope.of(context).unfocus();
    setState(() {
      turns.add(turn);
      busy = true;
      error = null;
      draft.clear();
    });
    bottom();
    try {
      final reply = await widget.api.chat(text, conversation);
      if (!mounted) return;
      setState(() {
        turn.reply = reply;
        conversation = reply.conversation;
      });
      if (reply.notice == autoPlanNotice) {
        await _openPlan(turn);
      } else {
        _applyWeekdays(turn);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          turns.remove(turn);
          error = friendly(e);
          draft.text = text;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (turn.plan == null) {
          bottom();
        } else {
          _reveal(turn);
        }
      }
    }
  }

  /// 계획 카드를 연 뒤 "화요일은 안 돼"처럼 요일만 다시 말하면 열려 있는 카드의 공부 요일을 바꾼다.
  void _applyWeekdays(_Turn turn) {
    if (!turns.any((t) => t.plan != null)) return;
    // "평일 1시간, 주말 3시간"처럼 요일마다 다른 시간을 말했으면 요일별 시간으로 바꾼다.
    final perDay = weekdayMinutesInMessage(turn.question);
    if (perDay != null) {
      planInputs.update(() {
        planInputs.split = false;
        planInputs.byWeekday = true;
        planInputs.setDayMinutes(perDay);
      });
      final text = [
        for (final day in perDay.keys.toList()..sort())
          '${weekdays[day - 1]} ${durationLabel(perDay[day]!)}',
      ].join(' · ');
      setState(
        () => turn.planNote =
            '요일별 공부시간을 바꿨어요: $text. '
            '위 계획 카드에서 다시 계산하면 반영됩니다.',
      );
      return;
    }
    final days = weekdaysInMessage(turn.question);
    if (days == null) return;
    planInputs.update(() {
      planInputs.weekdays
        ..clear()
        ..addAll(days);
      // 요일별 시간을 쓰는 중이면 안 되는 요일의 시간을 지운다.
      planInputs.dayMinutes.removeWhere((day, _) => !days.contains(day));
    });
    setState(
      () => turn.planNote =
          '공부 요일을 바꿨어요: ${weekdayNames(days)}. '
          '위 계획 카드에서 다시 계산하면 이 요일에만 배정됩니다.',
    );
  }

  /// 서버가 계획 입력을 요청한 답변: 과목 목록을 읽어 같은 대화 안에 계획 카드를 연다.
  Future<void> _openPlan(_Turn turn) async {
    if (turn.planLoading) return;
    setState(() {
      turn.planLoading = true;
      turn.planError = null;
    });
    try {
      // 목록을 못 읽은 경우에만 다시 시도할 수 있다. 질문 자체의 문제는 다시 열어도 같다.
      turn.planRetry = true;
      final catalog = await widget.api.catalog();
      turn.planRetry = false;
      turn.plan = ChatPlanSetup.from(
        turn.question,
        catalog,
        planInputs,
        dayInSeoul(),
      );
    } catch (e) {
      turn.planError = e is ApiError ? e.message : '과목 목록을 불러오지 못했어요.';
    } finally {
      turn.planLoading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> newChat() async {
    if (busy) {
      toast(context, '답변을 받은 뒤 새 대화를 열 수 있어요.');
      return;
    }
    if (turns.isEmpty && draft.text.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('새 대화를 시작할까요?'),
        content: const Text('화면에 표시된 대화와 작성 중인 질문을 지웁니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('새 대화'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      setState(() {
        turns.clear();
        draft.clear();
        conversation = null;
        error = null;
      });
    }
  }

  Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) toast(context, '복사했어요.');
  }

  @override
  Widget build(BuildContext context) => WidthLimit(
    child: Column(
      children: [
        Expanded(
          child: ListView(
            controller: scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            children: [
              if (turns.isEmpty)
                Entrance(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: pale,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.forum_outlined,
                            color: blue,
                            size: 23,
                          ),
                        ),
                      ),
                      const SizedBox(height: 21),
                      const Text(
                        '자격증 준비,\n무엇이 궁금한가요?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const HelpText('공부 순서부터 과목별 학습 방법까지\n지금 고민하는 내용을 물어보세요.'),
                      const Heading('이렇게 질문해 보세요'),
                      for (final (i, q) in [
                        'SQLD는 어떤 과목부터 공부할까요?',
                        '하루 2시간이면 정보처리기사 필기를 어떻게 준비할까요?',
                        '기출문제와 이론 공부는 어떻게 병행할까요?',
                      ].indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Material(
                            color: Colors.transparent,
                            shape: const Border(
                              bottom: BorderSide(color: line),
                            ),
                            child: InkWell(
                              onTap: () => send(q),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(
                                      [
                                        Icons.route_outlined,
                                        Icons.schedule_rounded,
                                        Icons.auto_stories_outlined,
                                      ][i],
                                      color: blue,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        q,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_outward_rounded,
                                      size: 17,
                                      color: muted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              for (final turn in turns) ...[
                Align(
                  key: turn.key,
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(
                      left: 24,
                      top: 14,
                      bottom: 16,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 13,
                    ),
                    decoration: const BoxDecoration(
                      color: blue,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(5),
                      ),
                    ),
                    child: SelectableText(
                      turn.question,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
                if (turn.reply case final r?)
                  Pane(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 17,
                              color: blue,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                r.llm ? 'AI 상담 답변' : '기본 학습 안내',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: blue,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '답변 복사',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => copy(r.answer),
                              icon: const Icon(
                                Icons.content_copy_rounded,
                                size: 16,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          r.answer,
                          style: const TextStyle(fontSize: 14, height: 1.7),
                        ),
                        if ((r.notice ?? '').trim().isNotEmpty &&
                            r.notice != autoPlanNotice) ...[
                          const SizedBox(height: 14),
                          const Divider(),
                          const SizedBox(height: 12),
                          HelpText(r.notice!),
                        ],
                        if (r.sources.isNotEmpty)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text(
                              '참고 출처',
                              style: TextStyle(fontSize: 12),
                            ),
                            children: r.sources
                                .map(
                                  (s) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: SelectableText(
                                      s,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: blue,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      tooltip: '출처 주소 복사',
                                      onPressed: () => copy(s),
                                      icon: const Icon(
                                        Icons.content_copy_rounded,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                if (turn.plan case final plan?)
                  ChatPlanCard(
                    widget.api,
                    plan,
                    planInputs,
                    conversation: () =>
                        turns.contains(turn) ? conversation : null,
                    onSaved: widget.onPlanSaved,
                  ),
                if (turn.planNote case final note?)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Semantics(
                      liveRegion: true,
                      child: Pane(
                        color: pale,
                        padding: 14,
                        child: Text(
                          note,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                    ),
                  ),
                if (turn.planError case final message?) ...[
                  AlertText(message),
                  if (turn.planRetry)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: turn.planLoading
                            ? null
                            : () => _openPlan(turn),
                        child: const Text('계획 입력 다시 열기'),
                      ),
                    ),
                ],
              ],
              if (busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Pane(
                    child: Row(
                      children: [
                        const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '질문에 맞는 답변을 준비하고 있어요.',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (error != null) AlertText(error!),
            ],
          ),
        ),
        Material(
          color: Colors.white,
          shape: const Border(top: BorderSide(color: line)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: draft,
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '궁금한 학습 내용을 입력하세요',
                    ),
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: draft,
                  builder: (_, _) => IconButton.filled(
                    tooltip: '질문 보내기',
                    onPressed: busy || draft.text.trim().isEmpty
                        ? null
                        : () => send(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
