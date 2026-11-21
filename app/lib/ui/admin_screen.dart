import 'package:flutter/material.dart';

import '../data/models.dart';
import 'admin_api.dart';
import 'admin_collect.dart';
import 'admin_operations.dart';
import 'admin_reviews.dart';
import 'admin_sources.dart';
import 'admin_widgets.dart';
import 'design.dart';

class AdminScreen extends StatefulWidget {
  final AdminApi api;
  const AdminScreen(this.api, {super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool loading = true;
  Object? error;
  Json? database, summary, crawl, naver;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        widget.api.get('/db-status'),
        widget.api.get('/data/summary'),
        widget.api.get('/reviews/status'),
        widget.api.get('/naver/status'),
      ]);
      if (!mounted) return;
      setState(() {
        database = adminObject(values[0]);
        summary = adminObject(values[1]);
        crawl = adminObject(values[2]);
        naver = adminObject(values[3]);
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AdminAccessGate(widget.api, child: page),
      ),
    );
    if (mounted && widget.api.accessible) await load();
  }

  Widget entry(IconData icon, String title, String description, Widget page) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Icon(icon, color: blue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          description,
          style: const TextStyle(color: muted, height: 1.5, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: !widget.api.accessible ? null : () => open(page),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('수집 관리'),
      actions: [
        IconButton(
          tooltip: '관리자 정보 새로고침',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: ScrollBody(
        refresh: load,
        children: [
          const Text(
            '관리자',
            style: TextStyle(
              color: blue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '학습 정보의 출처와 수집 상태를 관리하세요.',
            style: TextStyle(color: muted, height: 1.6),
          ),
          if (loading)
            const AdminLoading()
          else if (error != null)
            AdminFailure(error!, retry: widget.api.accessible ? load : null)
          else ...[
            const SizedBox(height: 20),
            Pane(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        database?['connected'] == true
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        color: database?['connected'] == true ? green : amber,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          database?['connected'] == true
                              ? 'DB 연결 정상'
                              : 'DB 연결 확인 필요',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '수집된 후기 ${adminText(summary?['total'])}건',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '마지막 수집 ${adminText(summary?['lastCollectedAt']).replaceAll('T', ' ')}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '크롤링 · ${adminStates[crawl?['state']] ?? '상태 확인 필요'}\n네이버 · ${adminStates[adminOptional(naver?['job'])['state']] ?? '상태 확인 필요'}',
                    style: const TextStyle(height: 1.7),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => showAdminDocument(
                          context,
                          'DB 상태',
                          database,
                          api: widget.api,
                        ),
                        child: const Text('DB 상세'),
                      ),
                      TextButton(
                        onPressed: () => showAdminDocument(
                          context,
                          '수집 요약',
                          summary,
                          api: widget.api,
                        ),
                        child: const Text('출처별·자격증별 건수'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          AdminSection('관리 메뉴', [
            Pane(
              padding: 0,
              child: Column(
                children: [
                  entry(
                    Icons.sync_rounded,
                    '후기 수집',
                    '수집 시작·중단과 진행 상태',
                    AdminCollectScreen(widget.api),
                  ),
                  const Divider(),
                  entry(
                    Icons.article_outlined,
                    '수집 데이터',
                    '후기 검색·필터와 상세 정보',
                    AdminReviewsScreen(widget.api),
                  ),
                  const Divider(),
                  entry(
                    Icons.travel_explore_rounded,
                    '수집 범위',
                    '검색어·주소 관리와 미리보기',
                    AdminSourcesScreen(widget.api),
                  ),
                  const Divider(),
                  entry(
                    Icons.event_note_outlined,
                    '시험일정',
                    '일정 수집 · 참고시간 집계 · 과목 언급 채우기',
                    AdminOperationsScreen(widget.api),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: widget.api.accessible
                ? () => open(AdminResetScreen(widget.api))
                : null,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('복구 리포트·후기 초기화'),
          ),
        ],
      ),
    ),
  );
}
