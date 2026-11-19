import 'package:flutter/material.dart';

import 'admin_api.dart';
import 'admin_widgets.dart';
import 'design.dart';

class AdminOperationsScreen extends StatefulWidget {
  final AdminApi api;
  const AdminOperationsScreen(this.api, {super.key});
  @override
  State<AdminOperationsScreen> createState() => _AdminOperationsScreenState();
}

class _AdminOperationsScreenState extends State<AdminOperationsScreen> {
  String? busy;
  Object? error;
  Future<void> run(String title, String path, String explanation) async {
    if (busy != null) return;
    if (!await adminConfirm(context, title, explanation, action: '실행하기') ||
        !mounted) {
      return;
    }
    setState(() {
      busy = path;
      error = null;
    });
    try {
      final result = await widget.api.post(path);
      if (mounted) {
        await showAdminDocument(context, '처리 결과', result, api: widget.api);
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Widget action(String title, String path, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(description, style: const TextStyle(color: muted, height: 1.6)),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: busy != null ? null : () => run(title, path, description),
          child: Text(
            busy == path ? '서버에서 처리 중…' : title,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('시험일정')),
    body: SafeArea(
      child: ScrollBody(
        children: [
          if (error != null) AdminFailure(error!),
          if (busy != null) const AdminLoading(),
          AdminSection('시험일정 가져오기', [
            action(
              '정보처리기사 일정 가져오기',
              '/exam',
              '기존 공공데이터 API 수집을 실행합니다. 서버 설정에 따라 SAMPLE 자료가 사용될 수 있으며 결과에 구분해 표시됩니다.',
            ),
            action(
              'SQLD·ADsP 일정 가져오기',
              '/sqld-schedule',
              '기존 SQLD·ADsP 일정 수집을 실행해 서버의 시험일정을 갱신합니다.',
            ),
            action(
              'dataq 일정 가져오기',
              '/manual/dataq-schedule',
              '보조 출처인 dataq 페이지의 SQLD·ADsP 시험일정을 수동으로 수집합니다.',
            ),
          ]),
          AdminSection('후기 기반 참고시간', [
            action(
              '과목 언급 채우기',
              '/reviews/subject-backfill',
              '이미 저장한 velog·티스토리 후기 30건의 본문을 다시 읽어 과목별 시간·비율·난이도 언급만 저장합니다. 기존 후기 값은 바꾸지 않으며 1~2분 걸릴 수 있습니다. 남은 후기가 있으면 다시 눌러 주세요.',
            ),
            action(
              '참고 학습시간 재집계',
              '/reference-stats',
              '현재 서버에 저장된 후기를 기준으로 기존 참고 학습시간 집계를 실행합니다. 개인의 실제 공부시간 통계와는 별개입니다.',
            ),
          ]),
        ],
      ),
    ),
  );
}

class AdminResetScreen extends StatefulWidget {
  final AdminApi api;
  const AdminResetScreen(this.api, {super.key});
  @override
  State<AdminResetScreen> createState() => _AdminResetScreenState();
}

class _AdminResetScreenState extends State<AdminResetScreen> {
  Object? report, error;
  bool loading = false, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.api.get('/reviews/recovery-report');
      if (mounted) setState(() => report = value);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> reset() async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final preview = adminObject(await widget.api.get('/reviews/reset'));
      if (!mounted) return;
      final velog = adminNumber(preview['velog']),
          tistory = adminNumber(preview['tistory']);
      if (velog + tistory == 0) {
        toast(context, '초기화할 크롤링 후기가 없습니다.');
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ResetConfirmationDialog(
          velog,
          tistory,
          preview['message'] as String?,
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await widget.api.post('/reviews/reset', {
        'confirm': '초기화',
      });
      if (!mounted) return;
      await showAdminDocument(context, '초기화 결과', result, api: widget.api);
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('복구·초기화')),
    body: SafeArea(
      child: ScrollBody(
        refresh: load,
        children: [
          if (error != null)
            AdminFailure(
              error!,
              retry: !busy && widget.api.accessible ? load : null,
            ),
          AdminSection('복구 리포트', [
            if (loading)
              const AdminLoading()
            else if (report != null)
              AdminValueTree(report),
          ]),
          AdminSection('크롤링 후기 초기화', [
            const AlertText(
              'velog·티스토리 수집 후기를 삭제하는 작업입니다. 실행 전 삭제할 건수를 확인하고 확인 문구를 입력해야 합니다.',
            ),
            OutlinedButton(
              onPressed: busy || loading || !widget.api.accessible
                  ? null
                  : reset,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(busy ? '처리 중…' : '후기 초기화'),
            ),
          ]),
        ],
      ),
    ),
  );
}

class _ResetConfirmationDialog extends StatefulWidget {
  final int velog, tistory;
  final String? message;
  const _ResetConfirmationDialog(this.velog, this.tistory, this.message);
  @override
  State<_ResetConfirmationDialog> createState() =>
      _ResetConfirmationDialogState();
}

class _ResetConfirmationDialogState extends State<_ResetConfirmationDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('크롤링 후기 초기화'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'velog ${widget.velog}건 · 티스토리 ${widget.tistory}건\n\n삭제 후 되돌릴 수 없습니다. 회원·시험일정·다른 출처의 후기는 대상이 아닙니다.',
          style: const TextStyle(height: 1.6),
        ),
        if (widget.message != null) ...[
          const SizedBox(height: 12),
          Text(widget.message!),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '확인 문구',
            helperText: '초기화를 정확히 입력해 주세요.',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('취소'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: controller.text == '초기화'
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('초기화 실행'),
      ),
    ],
  );
}
