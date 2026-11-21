import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';

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
  static const _subjectPath = '/reviews/subject-backfill';
  static const _subjectStatusPath = '/reviews/subject-backfill/status';
  static const _subjectAutoPath = '/reviews/subject-backfill/auto';
  static const _subjectStopPath = '/reviews/subject-backfill/stop';
  static const _referencePath = '/reference-stats';
  final subjectLimit = TextEditingController(text: '30');
  final subjectForm = GlobalKey<FormState>();
  String? busy;
  Object? error;
  Json? subject;
  bool subjectLoading = false;
  Timer? timer;

  /// 수동 실행 또는 [11-19] 끝까지 자동이 서버에서 도는 중인지
  bool get subjectRunning =>
      subject?['running'] == true ||
      subject?['autoRunning'] == true ||
      busy == _subjectPath;
  bool get autoRunning => subject?['autoRunning'] == true;

  @override
  void initState() {
    super.initState();
    loadSubject();
  }

  @override
  void dispose() {
    timer?.cancel();
    subjectLimit.dispose();
    super.dispose();
  }

  /// 과목 언급 채우기가 도는 동안만 3초마다 진행 상황을 다시 읽는다.
  void schedule() {
    timer?.cancel();
    if (!subjectRunning || !widget.api.accessible) return;
    timer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) {
        schedule();
        return;
      }
      loadSubject();
    });
  }

  Future<void> loadSubject() async {
    if (subjectLoading) return;
    timer?.cancel();
    setState(() => subjectLoading = true);
    try {
      final value = adminObject(await widget.api.get(_subjectStatusPath));
      if (mounted) setState(() => subject = value);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) {
        setState(() => subjectLoading = false);
        schedule();
      }
    }
  }

  Future<void> runSubject() async {
    if (busy != null || !subjectForm.currentState!.validate()) return;
    if (!await adminConfirm(
          context,
          '과목 언급 채우기',
          '저장된 velog·티스토리 후기 본문을 다시 읽어 과목별 언급만 채웁니다. 후기 자료는 바뀌지 않으며, 건수가 많으면 몇 분 걸릴 수 있습니다.',
          action: '실행하기',
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      busy = _subjectPath;
      error = null;
    });
    schedule();
    try {
      final result = await widget.api.post(_subjectPath, {
        'limit': subjectLimit.text.trim(),
      });
      if (mounted) {
        await showAdminDocument(context, '처리 결과', result, api: widget.api);
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) {
        setState(() => busy = null);
        loadSubject();
      }
    }
  }

  /// [11-19] 끝까지 자동 시작·멈추기: 서버가 바로 답하고 실제 처리는 뒤에서 한다.
  Future<void> runSubjectAuto({required bool stop}) async {
    if (busy != null) return;
    final title = stop ? '자동 채우기 멈추기' : '끝까지 자동 채우기';
    final explanation = stop
        ? '지금 읽고 있는 글까지만 처리하고 멈춥니다. 이미 저장한 과목 언급은 그대로 남습니다.'
        : '남은 후기를 200건씩 이어서 끝까지 읽습니다. 서버가 뒤에서 처리하므로 화면을 닫아도 계속되며, 30분~1시간 정도 걸릴 수 있습니다. 사이트가 접근을 막으면(403·429) 자동으로 멈춥니다.';
    if (!await adminConfirm(
          context,
          title,
          explanation,
          action: stop ? '멈추기' : '시작하기',
        ) ||
        !mounted) {
      return;
    }
    final path = stop ? _subjectStopPath : _subjectAutoPath;
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
      if (mounted) {
        setState(() => busy = null);
        loadSubject();
      }
    }
  }

  /// 한글 주소는 읽기 쉽게 풀어서 보여 주고, 풀 수 없으면 그대로 둔다.
  static String readableUrl(Object? value) {
    try {
      return Uri.decodeFull('$value');
    } catch (_) {
      return '$value';
    }
  }

  Widget subjectStatus() {
    final data = subject;
    if (data == null) {
      return Text(
        subjectLoading ? '상태를 불러오는 중…' : '상태를 불러와 주세요.',
        style: const TextStyle(color: muted),
      );
    }
    if (data['tableReady'] == false) {
      return const Text(
        '서버 DB에 과목 언급 테이블이 없어요. db/10_review_subject_mentions.sql 실행 후 다시 확인해 주세요.',
        style: TextStyle(color: muted, height: 1.6),
      );
    }
    final running = data['running'] == true;
    final auto = data['autoRunning'] == true;
    final done = adminNumber(data['done']), target = adminNumber(data['target']);
    return Pane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            auto
                ? '끝까지 자동 채우는 중 · ${adminNumber(data['autoRounds']) + 1}회차'
                : running
                ? '채우는 중'
                : '대기 중',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: target > 0 ? (done / target).clamp(0.0, 1.0) : null,
              semanticsLabel: '과목 언급 채우기 진행률',
            ),
            const SizedBox(height: 10),
            Text(
              '이번 회차 처리 ${adminText(data['done'])}건 · 목표 ${adminText(data['target'])}건',
              style: const TextStyle(height: 1.6),
            ),
            Text(
              '과목 언급 나온 후기 ${adminText(data['reviewsWithMentions'])} · 저장 ${adminText(data['savedRows'])}줄',
              style: const TextStyle(color: muted, height: 1.7),
            ),
            if (data['current'] != null) ...[
              const SizedBox(height: 8),
              Text(
                '지금 읽는 글: ${readableUrl(data['current'])}',
                style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            '남은 후기 약 ${adminText(data['remaining'])}건',
            style: const TextStyle(height: 1.6),
          ),
          const Text(
            'velog·티스토리 후기 중 과목 언급이 없고, 이번 서버 실행에서 아직 확인하지 않은 글 (서버를 다시 켜면 다시 늘어날 수 있어요)',
            style: TextStyle(fontSize: 12, color: muted, height: 1.5),
          ),
          if (data['autoMessage'] != null) ...[
            const SizedBox(height: 8),
            Text(
              '자동 실행 기록: ${data['autoMessage']}',
              style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
            ),
          ],
          TextButton(
            onPressed: subjectLoading ? null : loadSubject,
            child: const Text('상태 새로고침'),
          ),
        ],
      ),
    );
  }

  /// [11-19] 참고 학습시간 재집계: 결과를 표로 보여 준다 (웹 관리자 화면과 같은 내용).
  Future<void> runReference() async {
    if (busy != null) return;
    if (!await adminConfirm(
          context,
          '참고 학습시간 재집계',
          '현재 서버에 저장된 후기를 기준으로 참고 학습시간을 다시 집계합니다. 개인의 실제 공부시간 통계와는 별개입니다.',
          action: '실행하기',
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      busy = _referencePath;
      error = null;
    });
    try {
      final result = await widget.api.post(_referencePath);
      if (!mounted) return;
      final lines = result is List
          ? result.whereType<Map>().map((e) => Json.from(e)).toList()
          : <Json>[];
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ReferenceResultScreen(lines),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

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
          AdminSection('시험일정 가져오기', info: 'schedule', [
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
          AdminSection('후기 기반 참고시간', info: 'reference', [
            const Text(
              '합격 후기로 자격증별 총 공부시간(중앙값)을 계산해요. 학습계획의 기준값이에요. 결과는 표로 보여 줘요.',
              style: TextStyle(color: muted, height: 1.6),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: busy != null ? null : runReference,
              child: Text(
                busy == _referencePath ? '서버에서 처리 중…' : '참고 학습시간 재집계',
                textAlign: TextAlign.center,
              ),
            ),
          ]),
          AdminSection('과목 언급 채우기', info: 'subject', [
            const Text(
              '저장된 후기를 다시 읽어 과목별 시간·비율·난이도 언급을 모아요. 과목별 학습량의 재료이며, 아직 계산에는 쓰지 않아요. 새로 수집하는 후기는 자동으로 채워져요.',
              style: TextStyle(color: muted, height: 1.6),
            ),
            const SizedBox(height: 12),
            subjectStatus(),
            const SizedBox(height: 12),
            Form(
              key: subjectForm,
              child: TextFormField(
                controller: subjectLimit,
                enabled: busy == null && !subjectRunning,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '한 번에 읽을 후기 수',
                  helperText: '1~200건 · 서버는 한 번에 최대 200건까지 처리합니다.',
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 1 || n > 200
                      ? '1~200 사이의 정수를 입력해 주세요.'
                      : null;
                },
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: busy != null || subjectRunning ? null : runSubject,
              child: Text(
                busy == _subjectPath ? '서버에서 처리 중…' : '과목 언급 채우기',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: busy != null || subjectRunning
                  ? null
                  : () => runSubjectAuto(stop: false),
              child: Text(
                busy == _subjectAutoPath ? '서버에 요청 중…' : '끝까지 자동 채우기',
                textAlign: TextAlign.center,
              ),
            ),
            if (autoRunning) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: busy != null
                    ? null
                    : () => runSubjectAuto(stop: true),
                child: Text(
                  busy == _subjectStopPath ? '서버에 요청 중…' : '자동 채우기 멈추기',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ]),
        ],
      ),
    ),
  );
}

/// [11-19] 참고 학습시간 재집계 결과 표. 기본은 "전공 전체" 줄만, 스위치로 전공별 줄까지 본다.
class _ReferenceResultScreen extends StatefulWidget {
  final List<Json> lines;
  const _ReferenceResultScreen(this.lines);
  @override
  State<_ReferenceResultScreen> createState() => _ReferenceResultScreenState();
}

class _ReferenceResultScreenState extends State<_ReferenceResultScreen> {
  bool allMajors = false;
  static const _exams = {'WRITTEN': '필기', 'PRACTICAL': '실기'};
  static const _majors = {'MAJOR': '전공', 'NON_MAJOR': '비전공'};
  /// CERTIFICATIONS.certification_id → 이름 (db/03·09 기준)
  static const _certs = {
    1: '정보처리기사',
    2: 'SQLD',
    3: '컴활 1급',
    4: 'ADsP',
  };

  static String _cert(Object? id) {
    final name = id is num ? _certs[id.toInt()] : null;
    return name == null ? '자격증 ${adminText(id)}' : '자격증 ${adminText(id)}($name)';
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.lines
        .where((l) => allMajors || l['majorType'] == null)
        .toList();
    final verified = rows.where((l) => l['meanHours'] != null).length;
    return Scaffold(
      appBar: AppBar(title: const Text('처리 결과')),
      body: SafeArea(
        child: ScrollBody(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('전공별 줄도 보기'),
              subtitle: const Text('끄면 전공 전체 줄만 보여요'),
              value: allMajors,
              onChanged: (v) => setState(() => allMajors = v),
            ),
            Text(
              '실측값 저장 $verified줄 / 표시 ${rows.length}줄 (전체 ${widget.lines.length}줄)',
              style: const TextStyle(color: muted, height: 1.6),
            ),
            const SizedBox(height: 12),
            for (final l in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Pane(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_cert(l['certificationId'])} · '
                        '${_exams[l['examType']] ?? adminText(l['examType'])} · '
                        '${l['majorType'] == null ? '전공 전체' : _majors[l['majorType']] ?? l['majorType']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l['meanHours'] == null
                            ? '표본 ${adminText(l['sampleCount'])}건 · 잠정값 사용'
                            : '표본 ${adminText(l['sampleCount'])}건 · 중앙값 ${adminText(l['meanHours'])}시간',
                        style: const TextStyle(height: 1.6),
                      ),
                      // [11-21] 네이버 요약 후기: 보충 건수와 비교용 단독 중앙값
                      if (adminNumber(l['naverCount']) > 0)
                        Text(
                          '네이버 비교 ${adminText(l['naverCount'])}건 · 중앙값 ${adminText(l['naverMedian'])}시간'
                          '${adminNumber(l['naverUsed']) > 0 ? ' · 이 중 ${adminText(l['naverUsed'])}건 보충' : ''}',
                          style: const TextStyle(fontSize: 12, color: blue, height: 1.5),
                        ),
                      Text(
                        adminText(l['result']),
                        style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
