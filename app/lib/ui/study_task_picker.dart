import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/session.dart';
import '../data/study_models.dart';
import 'design.dart';

class StudyTaskSelection {
  final StudyTaskChoice? task;
  const StudyTaskSelection(this.task);
}

class StudyTaskPicker extends StatefulWidget {
  final Session session;
  final DateTime date;
  final int? selectedId;
  final VoidCallback onForbidden;
  const StudyTaskPicker(
    this.session, {
    super.key,
    required this.date,
    required this.selectedId,
    required this.onForbidden,
  });
  @override
  State<StudyTaskPicker> createState() => _StudyTaskPickerState();
}

class _StudyTaskPickerState extends State<StudyTaskPicker> {
  late final PassApi? account;
  List<StudyTaskChoice> items = [];
  bool loading = false, blocked = false;
  int epoch = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    account = widget.session.account;
    blocked = account == null;
    widget.session.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    if (mounted && !identical(account, widget.session.account)) {
      setState(() {
        epoch++;
        blocked = true;
        loading = false;
        items = [];
      });
    }
  }

  @override
  void dispose() {
    epoch++;
    widget.session.removeListener(accountChanged);
    super.dispose();
  }

  bool current(int turn) =>
      mounted &&
      !blocked &&
      turn == epoch &&
      identical(account, widget.session.account);
  Future<void> load() async {
    final api = account;
    if (api == null || blocked) {
      return;
    }
    final turn = ++epoch;
    setState(() {
      loading = true;
      error = null;
      items = [];
    });
    try {
      final all = <StudyTaskChoice>[];
      for (var next = 0; next <= 10000; next++) {
        final result = await api.studyPlanTasks(page: next);
        if (!current(turn)) return;
        if (result.page != next ||
            result.items.any((t) => t.status != 'ACTIVE')) {
          throw const FormatException('Unexpected plan choices');
        }
        all.addAll(result.items);
        if (!result.hasNext) break;
        if (next == 10000 || result.items.isEmpty) {
          throw const FormatException('Incomplete plan choices');
        }
      }
      setState(() {
        items = distinctStudySubjects(
          all,
          widget.date,
          selectedId: widget.selectedId,
        );
        loading = false;
      });
    } catch (e) {
      if (!current(turn)) return;
      if (e is ApiError && (e.status == 401 || e.status == 403)) {
        widget.onForbidden();
        setState(() {
          blocked = true;
          items = [];
          loading = false;
        });
      } else {
        setState(() {
          error = friendly(e);
          loading = false;
        });
      }
    }
  }

  void select(StudyTaskChoice? task) {
    if (!blocked && identical(account, widget.session.account)) {
      Navigator.pop(context, StudyTaskSelection(task));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('과목 연결')),
    body: SafeArea(
      child: blocked
          ? const ScrollBody(
              children: [AlertText('로그인 상태가 바뀌었어요. 이전 화면으로 돌아가 다시 확인해 주세요.')],
            )
          : WidthLimit(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                itemCount: items.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '공부한 과목을 선택해요',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const HelpText('현재 학습계획의 과목만 한 번씩 보여드려요.'),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => select(null),
                          child: const Text('과목 연결 없음'),
                        ),
                        const SizedBox(height: 12),
                        if (!loading && error == null)
                          Text(
                            '${items.length}개 과목',
                            style: const TextStyle(color: muted),
                          ),
                      ],
                    );
                  }
                  if (index <= items.length) {
                    final item = items[index - 1];
                    return Column(
                      children: [
                        ListTile(
                          key: ValueKey('study-task-${item.id}'),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          selected: widget.selectedId == item.id,
                          onTap: () => select(item),
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              if (item.certificationName?.trim().isNotEmpty ==
                                  true)
                                item.certificationName!,
                            ].join(' · '),
                            style: const TextStyle(color: muted, height: 1.6),
                          ),
                          trailing: widget.selectedId == item.id
                              ? const Icon(Icons.check_circle, color: blue)
                              : const Icon(Icons.chevron_right),
                        ),
                        const Divider(),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: '연결할 과목 불러오는 중',
                            ),
                          ),
                        ),
                      if (error != null) ...[
                        AlertText(error!),
                        OutlinedButton(
                          onPressed: load,
                          child: const Text('다시 불러오기'),
                        ),
                      ],
                      if (!loading && error == null && items.isEmpty)
                        EmptyPanel(
                          Icons.link_outlined,
                          '연결할 학습계획이 없어요',
                          '학습계획을 저장한 뒤 선택하거나 과목 연결 없이 기록할 수 있어요.',
                        ),
                    ],
                  );
                },
              ),
            ),
    ),
  );
}
