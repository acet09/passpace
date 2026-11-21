import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'admin_api.dart';
import 'admin_widgets.dart';
import 'design.dart';

class AdminCollectScreen extends StatefulWidget {
  final AdminApi api;
  const AdminCollectScreen(this.api, {super.key});
  @override
  State<AdminCollectScreen> createState() => _AdminCollectScreenState();
}

class _AdminCollectScreenState extends State<AdminCollectScreen>
    with WidgetsBindingObserver {
  final limit = TextEditingController(text: '100');
  final form = GlobalKey<FormState>();
  String site = 'ALL', mode = 'NEW';
  bool rss = true, tsearch = true, loading = false, busy = false;
  Object? error;
  Json? crawl, naver, counts;
  Timer? timer;
  bool foreground = true;
  bool get crawlRunning => crawl?['state'] == 'RUNNING';
  bool get naverRunning => adminOptional(naver?['job'])['state'] == 'RUNNING';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    limit.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    timer?.cancel();
    if (foreground && mounted && widget.api.accessible) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        refresh();
      } else {
        schedule();
      }
    }
  }

  void schedule() {
    timer?.cancel();
    if (foreground && widget.api.accessible && (crawlRunning || naverRunning)) {
      timer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) {
          schedule();
          return;
        }
        refresh();
      });
    }
  }

  Future<void> refresh() async {
    if (loading || busy) return;
    timer?.cancel();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        widget.api.get('/reviews/status'),
        widget.api.get('/naver/status'),
        widget.api.get('/status/by-cert'),
      ]);
      if (!mounted) return;
      setState(() {
        crawl = adminObject(values[0]);
        naver = adminObject(values[1]);
        counts = adminObject(values[2]);
      });
      schedule();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> run(bool isNaver, {bool cancel = false}) async {
    if (busy || loading) return;
    if (!cancel && !isNaver && !form.currentState!.validate()) return;
    final title = cancel
        ? '수집 중단'
        : isNaver
        ? '네이버 수집 시작'
        : '수집 시작';
    final fields = <String, String>{};
    if (!isNaver && !cancel) {
      fields.addAll({
        'limit': limit.text.trim(),
        'site': site,
        'mode': mode,
        'rss': '$rss',
        'tsearch': '$tsearch',
      });
    }
    if (!await adminConfirm(
          context,
          title,
          cancel
              ? '처리 중인 글까지 처리한 뒤 서버의 수집을 중단합니다.'
              : '기존 서버의 후기 수집을 실행합니다. 앱에서 나가도 서버 작업은 계속될 수 있습니다.',
          action: cancel ? '중단하기' : '시작하기',
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    timer?.cancel();
    try {
      final path =
          '${isNaver ? '/naver' : '/reviews'}/${cancel ? 'cancel' : 'start'}';
      final value = adminObject(await widget.api.post(path, fields));
      if (!mounted) return;
      setState(() {
        if (isNaver) {
          naver = value;
        } else {
          crawl = value;
        }
      });
      schedule();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget job(Json? data) {
    if (data == null) {
      return const Text('상태를 불러와 주세요.', style: TextStyle(color: muted));
    }
    final processed = adminNumber(data['processed']),
        target = adminNumber(data['target']);
    final candidates = adminNumber(data['candidates']);
    final goal = candidates > 0 ? math.min(candidates, target) : target;
    final progress = goal > 0 ? (processed / goal).clamp(0.0, 1.0) : null;
    return Pane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            adminStates[data['state']] ?? '상태 확인 필요',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (data['state'] == 'RUNNING') ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              semanticsLabel: '후기 수집 진행률',
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '처리 ${adminText(data['processed'])}건 · 목표 ${adminText(data['target'])}건',
            style: const TextStyle(height: 1.6),
          ),
          Text(
            '저장 ${adminText(data['saved'])} · 검증 ${adminText(data['valid'])}\n건너뜀 ${adminText(data['skipped'])} · 실패 ${adminText(data['failed'])}',
            style: const TextStyle(color: muted, height: 1.7),
          ),
          if (data['phase'] != null) ...[
            const SizedBox(height: 8),
            Text(
              '${data['phase']}',
              style: const TextStyle(color: blue, height: 1.5),
            ),
          ],
          if (data['message'] != null) ...[
            const SizedBox(height: 8),
            Text(
              '${data['message']}',
              style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
            ),
          ],
          TextButton(
            onPressed: () =>
                showAdminDocument(context, '수집 상세', data, api: widget.api),
            child: const Text('실행 상세 보기'),
          ),
        ],
      ),
    );
  }

  Widget certCounts(String area) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('자격증별 건수'),
    children: [
      AdminValueTree(adminOptional(adminOptional(counts?[area])['byCert'])),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final blocked = busy || loading || !widget.api.accessible;
    final news = naver?['recentNews'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('후기 수집'),
        actions: [
          IconButton(
            tooltip: '수집 상태 새로고침',
            onPressed: blocked ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ScrollBody(
          refresh: refresh,
          children: [
            if (error != null)
              AdminFailure(error!, retry: blocked ? null : refresh),
            if (loading && crawl == null) const AdminLoading(),
            if (busy) const Text('서버에 요청 중…', style: TextStyle(color: blue)),
            AdminSection('velog·티스토리', [
              job(crawl),
              certCounts('crawl'),
              Form(
                key: form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: limit,
                      enabled: !blocked && !crawlRunning && !naverRunning,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '수집 목표 건수',
                        helperText: '10~1,000건 · 새 후보가 적으면 수집 건수도 줄어듭니다.',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        return n == null || n < 10 || n > 1000
                            ? '10~1,000 사이의 정수를 입력해 주세요.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    AdminChoice(
                      '수집 사이트',
                      site,
                      const {'ALL': '전체', 'VELOG': 'velog', 'TISTORY': '티스토리'},
                      blocked || crawlRunning || naverRunning
                          ? null
                          : (v) => setState(() => site = v),
                    ),
                    AdminChoice(
                      '수집 방식',
                      mode,
                      const {
                        'NEW': '일반 수집',
                        'RECOVER': '복구 수집',
                        'RETRY': '실패분 다시 시도',
                      },
                      blocked || crawlRunning || naverRunning
                          ? null
                          : (v) => setState(() => mode = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('티스토리 RSS에서 새 글 찾기'),
                      value: rss,
                      onChanged: blocked || crawlRunning || naverRunning
                          ? null
                          : (v) => setState(() => rss = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('티스토리 검색으로 블로그 찾기'),
                      value: tsearch,
                      onChanged: blocked || crawlRunning || naverRunning
                          ? null
                          : (v) => setState(() => tsearch = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrimaryAction(
                '수집 시작',
                blocked || crawl == null || crawlRunning || naverRunning
                    ? null
                    : () => run(false),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: blocked || !crawlRunning
                    ? null
                    : () => run(false, cancel: true),
                child: const Text('크롤링 중단'),
              ),
            ]),
            AdminSection('네이버 검색 API', [
              job(adminOptional(naver?['job'])),
              const SizedBox(height: 12),
              Text(
                '오늘 API 호출 ${adminText(naver?['usedToday'])} / ${adminText(naver?['dailyLimit'])}',
                style: const TextStyle(color: muted, height: 1.6),
              ),
              if (naver?['keyReady'] == false)
                const AlertText('서버에 네이버 검색 API 키가 설정되어 있지 않습니다.'),
              certCounts('naver'),
              PrimaryAction(
                '네이버 수집 시작',
                blocked ||
                        naver?['keyReady'] != true ||
                        crawlRunning ||
                        naverRunning
                    ? null
                    : () => run(true),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: blocked || !naverRunning
                    ? null
                    : () => run(true, cancel: true),
                child: const Text('네이버 수집 중단'),
              ),
              if (news is List && news.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('최근 뉴스 · 참고 정보'),
                  children: [AdminValueTree(news)],
                ),
            ]),
            const SizedBox(height: 20),
            const Text(
              '실행 중에는 3초마다 상태를 확인합니다. 화면을 나가거나 앱이 배경으로 가면 조회를 멈춥니다.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
