// [11-26] 지원 자격증 정보 메뉴: 홈 섹션 → 목록 → 상세, 학습계획 만들기의 ⓘ 요약 시트.
// 서버: GET /api/certifications, /api/certifications/{id} (로그인 없이 열림)
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/certification_info.dart';
import 'design.dart';

const _categories = ['전체', 'IT', '데이터', '사무·회계', '안전'];
const _checkOfficial = '공식 사이트에서 확인';

/// 공식 사이트를 기기 브라우저로 연다. 실패하면 안내만 띄운다.
Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('사이트를 열지 못했어요: $url')),
    );
  }
}

/// 홈 탭 "지원 자격증" 섹션. 읽지 못하면 홈을 막지 않고 숨는다.
class SupportedCertsSection extends StatefulWidget {
  final PassApi api;
  final VoidCallback? onPlan;
  const SupportedCertsSection(this.api, {super.key, this.onPlan});
  @override
  State<SupportedCertsSection> createState() => _SupportedCertsSectionState();
}

class _SupportedCertsSectionState extends State<SupportedCertsSection> {
  late Future<List<CertSummary>> certs = widget.api.certifications();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CertSummary>>(
    future: certs,
    builder: (context, snap) {
      final list = snap.data;
      // 디버그 빌드에서는 실패 이유를 보여 준다 (릴리스는 홈을 막지 않게 숨김)
      if (snap.hasError && kDebugMode) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HelpText('[디버그] 지원 자격증 불러오기 실패: ${snap.error}'),
        );
      }
      if (snap.hasError || list == null || list.isEmpty) return const SizedBox.shrink();
      return Column(
        key: const ValueKey('home-supported-certs'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionRow(
            '지원 자격증',
            action: '전체 보기',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CertListScreen(widget.api, onPlan: widget.onPlan)),
            ),
          ),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _CertChip(
                list[i],
                onTap: () => openCertDetail(context, widget.api, list[i].id, onPlan: widget.onPlan),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      );
    },
  );
}

class _CertChip extends StatelessWidget {
  final CertSummary cert;
  final VoidCallback onTap;
  const _CertChip(this.cert, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final urgent = cert.next?.urgent == true;
    return SizedBox(
      width: 140,
      child: Material(
        color: urgent ? pale : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: urgent ? acid : line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cert.alwaysOpen ? '상시 시험' : (cert.next == null ? '일정 준비 중' : '${cert.next!.label.split(' ').last} ${cert.next!.dDayText}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: urgent ? amber : green),
                ),
                const SizedBox(height: 5),
                Text(
                  cert.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3),
                ),
                const Spacer(),
                Text(cert.partsText, style: const TextStyle(fontSize: 11, color: muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 자격증 목록: 이름 검색 + 분야 필터, 다음 일정이 가까운 순 (서버 정렬)
class CertListScreen extends StatefulWidget {
  final PassApi api;
  final VoidCallback? onPlan;
  const CertListScreen(this.api, {super.key, this.onPlan});
  @override
  State<CertListScreen> createState() => _CertListScreenState();
}

class _CertListScreenState extends State<CertListScreen> {
  late Future<List<CertSummary>> certs = widget.api.certifications();
  String category = '전체';
  String query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('지원 자격증')),
    body: SafeArea(
      child: FutureBuilder<List<CertSummary>>(
        future: certs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingPanel();
          if (snap.hasError) {
            return ScrollBody(children: [
              EmptyPanel(Icons.cloud_off_outlined, '불러오지 못했어요', friendly(snap.error!),
                  action: '다시 시도', onTap: () => setState(() => certs = widget.api.certifications())),
            ]);
          }
          final q = query.replaceAll(RegExp(r'\s+'), '').toLowerCase();
          final shown = snap.data!
              .where((c) => category == '전체' || c.category == category)
              .where((c) => q.isEmpty || c.name.replaceAll(RegExp(r'\s+'), '').toLowerCase().contains(q))
              .toList();
          return ScrollBody(
            refresh: () async {
              final next = widget.api.certifications();
              setState(() => certs = next);
              await next;
            },
            children: [
              TextField(
                key: const ValueKey('cert-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: '자격증 이름 검색',
                ),
                onChanged: (v) => setState(() => query = v),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _categories)
                    ChoiceChip(
                      label: Text(c),
                      selected: category == c,
                      onSelected: (_) => setState(() => category = c),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text('${shown.length}개 · 다음 일정이 가까운 순', style: const TextStyle(fontSize: 12, color: muted)),
              ),
              if (shown.isEmpty)
                const EmptyPanel(Icons.search_off_rounded, '맞는 자격증이 없어요', '검색어나 분야를 바꿔 보세요.'),
              for (final c in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Pane(
                    padding: 0,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      title: Row(
                        children: [
                          Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                          if (c.certType != null) ...[
                            const SizedBox(width: 6),
                            StatusTag(c.certType!.contains('민간') ? '국가공인' : '국가기술', color: muted, background: paper),
                          ],
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${c.issuingOrg ?? ''} · ${c.partsText}\n${c.nextText}',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: c.next?.urgent == true ? amber : muted,
                          ),
                        ),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openCertDetail(context, widget.api, c.id, onPlan: widget.onPlan),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

void openCertDetail(BuildContext context, PassApi api, int id, {VoidCallback? onPlan}) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => CertDetailScreen(api, id, onPlan: onPlan)),
);

/// 자격증 상세
class CertDetailScreen extends StatelessWidget {
  final PassApi api;
  final int id;

  /// "이 자격증으로 학습계획 만들기" (없으면 버튼을 숨김)
  final VoidCallback? onPlan;
  const CertDetailScreen(this.api, this.id, {super.key, this.onPlan});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('자격증 정보')),
    body: SafeArea(
      child: LoadBox<CertDetail>(
        load: () => api.certification(id),
        content: (d) => _DetailBody(d),
      ),
    ),
    bottomNavigationBar: onPlan == null
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: PrimaryAction('이 자격증으로 학습계획 만들기', () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                onPlan!();
              }),
            ),
          ),
  );
}

class _DetailBody extends StatefulWidget {
  final CertDetail d;
  const _DetailBody(this.d);
  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  int exam = 0;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final b = d.basic;
    final e = d.exams.isEmpty ? null : d.exams[exam < d.exams.length ? exam : 0];
    return ScrollBody(
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (b.certType != null) StatusTag([b.certType!, if (b.grade != null) b.grade!].join(' · ')),
          if (b.category != null) StatusTag(b.category!, color: muted, background: paper),
        ]),
        const SizedBox(height: 10),
        Text(b.name, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -1)),
        if (b.issuingOrg != null) ...[
          const SizedBox(height: 4),
          Text('시행 ${b.issuingOrg}', style: const TextStyle(fontSize: 13, color: muted)),
        ],
        if (b.summary != null) ...[const SizedBox(height: 10), HelpText(b.summary!)],
        const SizedBox(height: 14),
        _NextExamCard(d),
        if (e != null) ...[
          const SectionRow('시험 정보'),
          Pane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.exams.length > 1) ...[
                  SegmentedButton<int>(
                    segments: [
                      for (var i = 0; i < d.exams.length; i++)
                        ButtonSegment(value: i, label: Text(d.exams[i].label)),
                    ],
                    selected: {exam},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => exam = s.first),
                  ),
                  const SizedBox(height: 14),
                ],
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                  children: [
                    _Fact('응시료', e.fee == null ? _checkOfficial : won(e.fee!)),
                    _Fact('문항 수', e.questionCount == null ? _checkOfficial : '${e.questionCount}문항'),
                    _Fact('시험 시간', e.durationMinutes == null ? _checkOfficial : _minutes(e.durationMinutes!)),
                    _Fact('시험 방식', e.method ?? _checkOfficial),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('합격 기준', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xffe6f5ed), borderRadius: BorderRadius.circular(12)),
                  child: Text(e.passCriteria ?? _checkOfficial,
                      style: const TextStyle(color: green, height: 1.5, fontWeight: FontWeight.w500)),
                ),
                if (e.subjects.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('과목 ${e.subjects.length}개${e.scopeYear == null ? '' : ' · 출제기준 ${e.scopeYear}년'}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
                  const SizedBox(height: 4),
                  for (var i = 0; i < e.subjects.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('${i + 1}. ${e.subjects[i]}', style: const TextStyle(fontSize: 14)),
                    ),
                ],
              ],
            ),
          ),
        ],
        const SectionRow('응시자격'),
        Pane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.eligibility ?? _checkOfficial, style: const TextStyle(fontSize: 14, height: 1.6)),
              if (d.eligibilityCheckUrl != null)
                TextButton.icon(
                  onPressed: () => openLink(context, d.eligibilityCheckUrl!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('응시자격 자가진단'),
                ),
            ],
          ),
        ),
        if (d.notes.isNotEmpty) ...[
          const SectionRow('알아두면 좋은 정보'),
          Pane(
            child: Column(
              children: [
                for (final (k, v) in d.notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 92, child: Text(k, style: const TextStyle(fontSize: 14, color: muted))),
                        Expanded(child: Text(v, style: const TextStyle(fontSize: 14, height: 1.5))),
                      ],
                    ),
                  ),
                if (d.refundUrl != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(onPressed: () => openLink(context, d.refundUrl!), child: const Text('환불 규정 보기')),
                  ),
              ],
            ),
          ),
        ],
        if (d.passRates.isNotEmpty) ...[
          const SectionRow('최근 합격률'),
          Pane(
            child: Column(
              children: [
                for (final r in d.passRates)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 104,
                          child: Text('${r.year ?? ''} ${r.round == null ? '' : '${r.round}회 '}${r.label ?? ''}',
                              style: const TextStyle(fontSize: 13, color: muted)),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: ((r.rate ?? 0) / 100).clamp(0, 1).toDouble(),
                              minHeight: 10,
                              backgroundColor: pale,
                              color: blue,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(r.rate == null ? '-' : '${r.rate!.toStringAsFixed(1)}%',
                              textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (d.schedule.isNotEmpty) ...[
          const SectionRow('전체 일정'),
          Pane(
            padding: 0,
            child: ExpansionTile(
              title: Text('${d.schedule.length}개 회차', style: const TextStyle(fontSize: 14)),
              shape: const Border(),
              children: [
                for (final r in d.schedule)
                  ListTile(
                    dense: true,
                    title: Text(r.title + (r.projected ? ' (예상)' : ''),
                        style: TextStyle(color: r.past ? muted : ink, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '접수 ${span(r.regStart, r.regEnd)}\n시험 ${span(r.examStart, r.examEnd)} · 발표 ${dot(r.result)}',
                      style: TextStyle(color: r.past ? muted : ink, height: 1.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (d.officialUrl != null)
          OutlinedButton.icon(
            onPressed: () => openLink(context, d.officialUrl!),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('공식 시험 안내'),
          ),
        if (d.applyUrl != null && d.applyUrl != d.officialUrl) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => openLink(context, d.applyUrl!),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('원서 접수 사이트'),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          [
            if (d.relatedCerts != null) '관련 자격: ${d.relatedCerts}',
            '${d.verifiedAt == null ? '' : '정보 확인일 ${dot(d.verifiedAt)} · '}정확한 내용은 공식 사이트에서 확인하세요.',
          ].join('\n'),
          style: const TextStyle(fontSize: 12, color: muted, height: 1.6),
        ),
      ],
    );
  }

  static String _minutes(int m) => m % 60 == 0 ? '${m ~/ 60}시간' : (m > 60 ? '${m ~/ 60}시간 ${m % 60}분' : '$m분');
}

class _Fact extends StatelessWidget {
  final String k, v;
  const _Fact(this.k, this.v);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(k, style: const TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 2),
        Text(v, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: v == _checkOfficial ? 12 : 15, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _NextExamCard extends StatelessWidget {
  final CertDetail d;
  const _NextExamCard(this.d);
  @override
  Widget build(BuildContext context) {
    final b = d.basic;
    if (b.alwaysOpen) {
      return const Pane(child: HelpText('상시 시험이에요. 원하는 날짜에 시행처에서 접수해 응시할 수 있어요.'));
    }
    final r = d.nextExam;
    if (r == null) return const Pane(child: HelpText('다가오는 시험 일정이 아직 없어요. 공식 사이트를 확인해 주세요.'));
    return Pane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('다음 시험 · ${r.title}${r.projected ? ' (예상)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (b.next != null)
                StatusTag(b.next!.dDayText,
                    color: b.next!.urgent ? amber : blue, background: b.next!.urgent ? const Color(0xfffff1df) : pale),
            ],
          ),
          if (b.next != null) ...[
            const SizedBox(height: 4),
            Text(b.next!.label, style: const TextStyle(fontSize: 12, color: muted)),
          ],
          const SizedBox(height: 10),
          _row('원서 접수', span(r.regStart, r.regEnd)),
          if (r.addRegStart != null) _row('추가 접수', span(r.addRegStart, r.addRegEnd)),
          _row('시험일', span(r.examStart, r.examEnd)),
          _row('합격 발표', dot(r.result)),
        ],
      ),
    );
  }

  static Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 76, child: Text(k, style: const TextStyle(fontSize: 14, color: muted))),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 14))),
    ]),
  );
}

/// 학습계획 만들기에서 자격증 옆 ⓘ: 요약 시트 → "자세히 보기"
Future<void> showCertInfoSheet(BuildContext context, PassApi api, int id) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: FutureBuilder<CertDetail>(
        future: api.certification(id),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          if (snap.hasError) return SizedBox(height: 120, child: Center(child: HelpText(friendly(snap.error!))));
          final d = snap.data!;
          final w = d.exams.isEmpty ? null : d.exams.first;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text([d.basic.certType, d.basic.issuingOrg].whereType<String>().join(' · '),
                  style: const TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 2),
              Text(d.basic.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Pane(color: const Color(0xfffff1df), padding: 12, child: Text(d.basic.nextText)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Fact('응시료(${w?.label ?? '필기'})', w?.fee == null ? _checkOfficial : won(w!.fee!))),
                const SizedBox(width: 8),
                Expanded(child: _Fact('${w?.label ?? '필기'} 과목', w == null || w.subjects.isEmpty ? _checkOfficial : '${w.subjects.length}과목')),
              ]),
              const SizedBox(height: 10),
              HelpText('합격 기준: ${w?.passCriteria ?? _checkOfficial}'),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  openCertDetail(context, api, id);
                },
                child: const Text('자세히 보기'),
              ),
            ],
          );
        },
      ),
    ),
  ),
);
