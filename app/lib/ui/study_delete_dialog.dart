import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../data/study_models.dart';
import 'design.dart';

class StudyDeleteDialog extends StatefulWidget {
  final Session session;
  final PassApi account;
  final StudyRecord record;
  final VoidCallback onForbidden, onUncertain;
  const StudyDeleteDialog(
    this.session,
    this.account,
    this.record, {
    super.key,
    required this.onForbidden,
    required this.onUncertain,
  });
  @override
  State<StudyDeleteDialog> createState() => _StudyDeleteDialogState();
}

class _StudyDeleteDialogState extends State<StudyDeleteDialog> {
  bool busy = false, blocked = false, finishedAttempt = false;
  String? error;
  @override
  void initState() {
    super.initState();
    blocked = !identical(widget.account, widget.session.account);
    widget.session.addListener(accountChanged);
  }

  void accountChanged() {
    if (mounted && !identical(widget.account, widget.session.account)) {
      setState(() => blocked = true);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(accountChanged);
    super.dispose();
  }

  Future<void> remove() async {
    if (busy || blocked || finishedAttempt) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.account.deleteStudySession(widget.record);
      if (mounted &&
          !blocked &&
          identical(widget.account, widget.session.account)) {
        Navigator.pop(context, true);
      }
    } on StudyDeleteUncertain catch (e) {
      if (mounted &&
          !blocked &&
          identical(widget.account, widget.session.account)) {
        widget.onUncertain();
        setState(() {
          error = e.message;
          finishedAttempt = true;
        });
      }
    } catch (e) {
      if (mounted &&
          !blocked &&
          identical(widget.account, widget.session.account)) {
        if (e is ApiError && (e.status == 401 || e.status == 403)) {
          widget.onForbidden();
          setState(() => blocked = true);
        } else {
          setState(() {
            error = friendly(e);
            finishedAttempt = true;
          });
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('학습기록 삭제'),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (blocked)
            const AlertText('로그인 상태가 바뀌었거나 권한이 없어요. 기록을 다시 확인해 주세요.')
          else ...[
            Text(
              isoDay(widget.record.date),
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 8),
            Text(
              widget.record.subjectName?.trim().isNotEmpty == true
                  ? widget.record.subjectName!
                  : widget.record.taskId == null
                  ? '과목 미연결'
                  : '연결된 과목 이름 없음',
            ),
            const SizedBox(height: 8),
            Text(
              durationLabel(widget.record.minutes),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
            ),
            const SizedBox(height: 16),
            const HelpText('이 기록을 삭제할까요? 삭제한 기록은 복구할 수 없어요. 개인 통계에서도 제외돼요.'),
            if (error != null) AlertText(error!),
          ],
        ],
      ),
      actions: [
        if (blocked || finishedAttempt)
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
            child: const Text('기록 목록 확인'),
          )
        else ...[
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: busy ? null : remove,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                      semanticsLabel: '기록 삭제 중',
                    ),
                  )
                : const Text('삭제'),
          ),
        ],
      ],
    ),
  );
}
