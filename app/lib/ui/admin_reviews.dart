import 'package:flutter/material.dart';

import '../data/models.dart';
import 'admin_api.dart';
import 'admin_widgets.dart';
import 'design.dart';

class AdminReviewsScreen extends StatefulWidget {
  final AdminApi api;
  const AdminReviewsScreen(this.api, {super.key});
  @override
  State<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends State<AdminReviewsScreen> {
  final keyword = TextEditingController();
  String source = 'ALL',
      cert = 'ALL',
      status = 'ALL',
      sort = 'id',
      dir = 'desc',
      size = '20';
  Map<String, String> applied = {
    'source': 'ALL',
    'cert': 'ALL',
    'status': 'ALL',
    'q': '',
    'sort': 'id',
    'dir': 'desc',
    'size': '20',
  };
  Json? data;
  Object? error;
  bool loading = false;
  int page = 0;
  @override
  void initState() {
    super.initState();
    load(0);
  }

  @override
  void dispose() {
    keyword.dispose();
    super.dispose();
  }

  Future<void> load(int next, {bool apply = false}) async {
    if (loading) return;
    final query = apply
        ? {
            'source': source,
            'cert': cert,
            'status': status,
            'q': keyword.text.trim(),
            'sort': sort,
            'dir': dir,
            'size': size,
          }
        : Map<String, String>.of(applied);
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = adminObject(
        await widget.api.get('/data/reviews', {...query, 'page': '$next'}),
      );
      if (!mounted) return;
      setState(() {
        data = value;
        page = adminNumber(value['page']);
        applied = query;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget pager() {
    final total = adminNumber(data?['total']);
    final count = adminNumber(data?['size']);
    final pages = count > 0 ? (total / count).ceil().clamp(1, 10000000) : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '전체 ${adminText(data?['total'])}건 · ${page + 1} / $pages쪽',
          style: const TextStyle(color: muted, height: 1.6),
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton.icon(
              onPressed: loading || page == 0 ? null : () => load(page - 1),
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('이전'),
            ),
            TextButton.icon(
              onPressed: loading || page + 1 >= pages
                  ? null
                  : () => load(page + 1),
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('다음'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = loading || !widget.api.accessible;
    return Scaffold(
      appBar: AppBar(title: const Text('수집 데이터')),
      body: SafeArea(
        child: ScrollBody(
          refresh: () => load(page),
          children: [
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('조회 조건'),
              subtitle: Text(
                '${adminSources[applied['source']]} · ${adminCertificates[applied['cert']]}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              children: [
                AdminChoice(
                  '출처',
                  source,
                  adminSources,
                  blocked ? null : (v) => setState(() => source = v),
                ),
                AdminChoice(
                  '자격증',
                  cert,
                  adminCertificates,
                  blocked ? null : (v) => setState(() => cert = v),
                ),
                AdminChoice(
                  '검증 상태',
                  status,
                  adminStatuses,
                  blocked ? null : (v) => setState(() => status = v),
                ),
                TextField(
                  controller: keyword,
                  enabled: !blocked,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: '후기 검색어',
                    helperText: '요약문·주소·제외 이유에서 검색합니다.',
                  ),
                ),
                AdminChoice('정렬 기준', sort, const {
                  'id': '후기 번호',
                  'source': '출처',
                  'cert': '자격증',
                  'exam': '시험 종류',
                  'status': '검증 상태',
                  'pass': '합격 여부',
                  'major': '전공 여부',
                  'prep': '준비 기간',
                  'daily': '하루 학습량',
                  'total': '총 학습량',
                  'subjects': '과목',
                  'method': '방식',
                  'summary': '요약문',
                  'posted': '작성일',
                  'collected': '수집일',
                  'url': '주소',
                }, blocked ? null : (v) => setState(() => sort = v)),
                AdminChoice('정렬 순서', dir, const {
                  'desc': '내림차순',
                  'asc': '오름차순',
                }, blocked ? null : (v) => setState(() => dir = v)),
                AdminChoice('페이지당 항목', size, const {
                  '20': '20건',
                  '50': '50건',
                  '100': '100건',
                  '200': '200건',
                }, blocked ? null : (v) => setState(() => size = v)),
                PrimaryAction(
                  '조회 조건 적용',
                  blocked
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          load(0, apply: true);
                        },
                ),
                const SizedBox(height: 16),
              ],
            ),
            if (loading)
              const AdminLoading()
            else if (error != null)
              AdminFailure(
                error!,
                retry: widget.api.accessible ? () => load(page) : null,
              )
            else if (data != null) ...[
              const SizedBox(height: 18),
              pager(),
              if (rows(data!['rows']).isEmpty)
                const EmptyPanel(
                  Icons.search_rounded,
                  '조건에 맞는 후기가 없어요',
                  '출처·자격증·검증 상태 또는 검색어를 바꿔 확인해 주세요.',
                ),
              ...rows(data!['rows']).map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Pane(
                    padding: 0,
                    child: InkWell(
                      onTap: () => showAdminDocument(
                        context,
                        '후기 상세',
                        r,
                        api: widget.api,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Text(
                                  '#${adminText(r['reviewId'])}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  adminSources[r['source']] ??
                                      adminText(r['source']),
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  adminStatuses[r['reviewStatus']] ??
                                      adminText(r['reviewStatus']),
                                  style: const TextStyle(
                                    color: blue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${adminText(r['certName'])} · ${r['examType'] == 'WRITTEN'
                                  ? '필기'
                                  : r['examType'] == 'PRACTICAL'
                                  ? '실기'
                                  : adminText(r['examType'])}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              adminText(r['evidenceText']),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: muted, height: 1.6),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '후기 학습량 · ${adminText(r['prepDays'])}일 / 하루 ${adminText(r['dailyMinutes'])}분 / 총 ${adminText(r['totalHours'])}시간',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '상세 보기',
                              style: TextStyle(
                                color: blue,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (rows(data!['rows']).length > 3) pager(),
            ],
          ],
        ),
      ),
    );
  }
}
