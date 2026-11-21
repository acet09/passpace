import 'package:flutter/material.dart';

import '../data/models.dart';
import 'admin_api.dart';
import 'admin_widgets.dart';
import 'design.dart';

class AdminSourcesScreen extends StatefulWidget {
  final AdminApi api;
  const AdminSourcesScreen(this.api, {super.key});
  @override
  State<AdminSourcesScreen> createState() => _AdminSourcesScreenState();
}

class _AdminSourcesScreenState extends State<AdminSourcesScreen> {
  final keyword = TextEditingController(),
      urls = TextEditingController(),
      filter = TextEditingController();
  Json? sources;
  String site = 'velog';
  bool loading = false, busy = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    keyword.dispose();
    urls.dispose();
    filter.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = adminObject(await widget.api.get('/sources'));
      if (mounted) setState(() => sources = value);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<String> get entries {
    final all = <String>[
      ...strings(sources?['listings']),
      ...strings(sources?['seeds']),
      ...strings(sources?['tistoryKeywords']),
      ...strings(sources?['naverKeywords']),
    ];
    return all.toSet().where((s) {
      final uri = Uri.tryParse(s), host = uri?.host ?? '';
      final matches = switch (site) {
        'velog' => host == 'velog.io' || host.endsWith('.velog.io'),
        'tistory' => host == 'tistory.com' || host.endsWith('.tistory.com'),
        _ => host == 'search.naver.com',
      };
      return matches &&
          label(s).toLowerCase().contains(filter.text.trim().toLowerCase());
    }).toList();
  }

  String label(String value) {
    final u = Uri.tryParse(value);
    if (u == null) return value;
    return u.queryParameters['keyword'] ??
        u.queryParameters['query'] ??
        u.queryParameters['q'] ??
        value;
  }

  Future<void> add(bool isUrl) async {
    if (busy || loading) return;
    final text = (isUrl ? urls : keyword).text.trim();
    if (text.isEmpty) {
      toast(context, isUrl ? '주소를 입력해 주세요.' : '검색어를 입력해 주세요.');
      return;
    }
    final path = isUrl ? '/sources/urls' : '/sources/$site-keyword';
    final fields = {isUrl ? 'text' : 'keyword': text};
    await perform(
      path,
      fields,
      title: '출처 추가 결과',
      onSuccess: () => (isUrl ? urls : keyword).clear(),
    );
  }

  Future<void> perform(
    String path,
    Map<String, String> fields, {
    required String title,
    VoidCallback? onSuccess,
  }) async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.api.post(path, fields);
      if (!mounted) return;
      onSuccess?.call();
      await showAdminDocument(context, title, value, api: widget.api);
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(String url) async {
    if (busy || loading) return;
    if (!await adminConfirm(
          context,
          '수집 범위에서 삭제',
          '${label(url)}\n\n이 검색어·주소를 수집 범위에서 제외합니다. 이미 저장된 후기는 삭제하지 않습니다.',
          action: '삭제',
          danger: true,
        ) ||
        !mounted) {
      return;
    }
    await perform('/sources/remove', {'url': url}, title: '출처 삭제 결과');
  }

  @override
  Widget build(BuildContext context) {
    final blocked = loading || busy || !widget.api.accessible;
    final values = entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('수집 범위'),
        actions: [
          IconButton(
            tooltip: '수집 범위 새로고침',
            onPressed: blocked ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ScrollBody(
          refresh: load,
          children: [
            if (error != null)
              AdminFailure(error!, retry: blocked ? null : load),
            if (busy) const AdminLoading(),
            AdminSection('출처 관리', [
              AdminChoice(
                '사이트',
                site,
                const {'velog': 'velog', 'tistory': '티스토리', 'naver': '네이버'},
                blocked
                    ? null
                    : (v) => setState(() {
                        site = v;
                        filter.clear();
                      }),
              ),
              TextField(
                controller: keyword,
                enabled: !blocked,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: '검색어',
                  hintText: '예: 정보처리기사 실기 합격',
                ),
              ),
              PrimaryAction('검색어 추가', blocked ? null : () => add(false)),
              if (site != 'naver') ...[
                const SizedBox(height: 18),
                TextField(
                  controller: urls,
                  enabled: !blocked,
                  minLines: 2,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: '수집 주소',
                    helperText: '글 주소·velog 검색·태그·티스토리 RSS를 줄마다 입력해 주세요.',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: blocked ? null : () => add(true),
                  child: const Text('주소 추가'),
                ),
              ],
            ]),
            AdminSection('등록된 항목', [
              TextField(
                controller: filter,
                decoration: const InputDecoration(
                  labelText: '목록에서 찾기',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              if (loading)
                const AdminLoading()
              else ...[
                Text(
                  '${values.length}개 표시',
                  style: const TextStyle(color: muted),
                ),
                if (values.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '조건에 맞는 등록 항목이 없습니다.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                ...values.map((url) {
                  final uri = Uri.tryParse(url)!;
                  final listing =
                      (site == 'velog' &&
                          (uri.path.startsWith('/search') ||
                              uri.path.startsWith('/tags'))) ||
                      uri.path.endsWith('/rss');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          label(url),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          url,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (site != 'naver' &&
                                !url.startsWith(
                                  'https://www.tistory.com/search',
                                ))
                              TextButton(
                                onPressed: blocked
                                    ? null
                                    : () => perform(
                                        listing
                                            ? '/sources/inspect'
                                            : '/reviews/preview',
                                        {'url': url},
                                        title: listing ? '목록 검사 결과' : '후기 미리보기',
                                      ),
                                child: Text(listing ? '목록 검사' : '미리보기'),
                              ),
                            TextButton(
                              onPressed: blocked ? null : () => remove(url),
                              child: const Text('삭제'),
                            ),
                          ],
                        ),
                        const Divider(),
                      ],
                    ),
                  );
                }),
              ],
            ]),
            AdminSection('후기 후보 확인', [
              const Text(
                '기존 수집 범위에서 후보를 탐색합니다. 미리보기는 후기를 저장하지 않습니다.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: blocked
                    ? null
                    : () => perform('/reviews/discover', {}, title: '후기 후보'),
                child: const Text('후기 후보 탐색'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
