import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/models.dart';
import 'design.dart';

class ChatScreen extends StatefulWidget {
  final PassApi api;
  const ChatScreen(this.api, {super.key});
  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class _Turn {
  final String question;
  Reply? reply;
  _Turn(this.question);
}

class ChatScreenState extends State<ChatScreen> {
  final turns = <_Turn>[];
  final draft = TextEditingController(), scroll = ScrollController();
  int? conversation;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    draft.dispose();
    scroll.dispose();
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
        bottom();
      }
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
                        if ((r.notice ?? '').trim().isNotEmpty) ...[
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
