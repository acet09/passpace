import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'admin_link.dart';
import 'auth_intro.dart';
import 'design.dart';
import 'profile_edit.dart';

class AuthScreen extends StatefulWidget {
  final Session session;
  const AuthScreen(this.session, {super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final id = TextEditingController(), password = TextEditingController();
  bool busy = false, hidden = true;
  String? error, success;
  @override
  void dispose() {
    id.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> enter() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
      success = null;
    });
    try {
      await widget.session.signIn(id.text.trim(), password.text);
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> register() async {
    final registered = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => SignupScreen(widget.session.publicApi)),
    );
    if (registered == null || !mounted) return;
    setState(() {
      id.text = registered;
      password.clear();
      error = null;
      success = '회원가입이 완료됐어요. 가입한 아이디로 로그인해 주세요.';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ScrollBody(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(child: Brand()),
              IconButton(
                tooltip: '서버 연결 설정',
                onPressed: busy
                    ? null
                    : () => showConnection(context, widget.session),
                icon: const Icon(Icons.tune_rounded, color: muted, size: 21),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const AuthIntro(),
          const SizedBox(height: 24),
          if (success != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Pane(
                  color: const Color(0xffeaf6f0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: green,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          success!,
                          style: const TextStyle(
                            color: green,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.session.notice != null) AlertText(widget.session.notice!),
          Form(
            key: form,
            child: AutofillGroup(
              child: Column(
                children: [
                  TextFormField(
                    controller: id,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '아이디',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 21),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? '아이디를 입력해 주세요.' : null,
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: password,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.password],
                    obscureText: hidden,
                    onFieldSubmitted: (_) => enter(),
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 21,
                      ),
                      suffixIcon: IconButton(
                        tooltip: hidden ? '비밀번호 보기' : '비밀번호 숨기기',
                        onPressed: () => setState(() => hidden = !hidden),
                        icon: Icon(
                          hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 21,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        (v ?? '').isEmpty ? '비밀번호를 입력해 주세요.' : null,
                  ),
                ],
              ),
            ),
          ),
          if (error != null) AlertText(error!),
          const SizedBox(height: 21),
          PrimaryAction('로그인', enter, busy: busy),
          const SizedBox(height: 13),
          OutlinedButton(
            onPressed: busy ? null : register,
            child: const Text('회원가입'),
          ),
        ],
      ),
    ),
  );
}

class SignupScreen extends StatefulWidget {
  final PassApi api;
  const SignupScreen(this.api, {super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final form = GlobalKey<FormState>();
  final fields = List.generate(5, (_) => TextEditingController());
  String? major, error;
  bool busy = false, hidden = true;
  @override
  void dispose() {
    for (final f in fields) {
      f.dispose();
    }
    super.dispose();
  }

  String? validate(int i, String? v) {
    final s = v ?? '';
    if (s.trim().isEmpty) return '입력해 주세요.';
    switch (i) {
      case 0:
        if (!RegExp(r'^[A-Za-z0-9_]{4,20}$').hasMatch(s.trim())) {
          return '영문, 숫자, 밑줄로 4~20자를 입력해 주세요.';
        }
      case 1:
        if (s.length < 8 || s.length > 50 || utf8.encode(s).length > 72) {
          return '비밀번호는 8~50자, UTF-8 기준 72바이트 이내예요.';
        }
      case 2:
        if (s != fields[1].text) return '비밀번호가 일치하지 않아요.';
      case 3:
        if (s.trim().length > 50) return '닉네임은 50자까지 입력할 수 있어요.';
      case 4:
        if (s.trim().length > 255 ||
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim())) {
          return '이메일 주소를 확인해 주세요.';
        }
    }
    return null;
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = fields[0].text.trim();
      await widget.api.signup({
        'loginId': id,
        'password': fields[1].text,
        'passwordConfirm': fields[2].text,
        'nickname': fields[3].text.trim(),
        'email': fields[4].text.trim(),
        'majorType': major,
      });
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ScrollBody(
                children: [
                  const Text(
                    '나에게 맞는 준비,\n지금 시작해 보세요.',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 9),
                  const HelpText('계정 하나로 웹과 앱에서 학습계획을 이어가세요.'),
                  Form(
                    key: form,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Heading('로그인 정보'),
                          for (final (i, label) in [
                            '아이디',
                            '비밀번호',
                            '비밀번호 확인',
                            '닉네임',
                            '이메일',
                          ].indexed) ...[
                            if (i == 3) const Heading('나의 프로필'),
                            TextFormField(
                              controller: fields[i],
                              enabled: !busy,
                              obscureText: (i == 1 || i == 2) && hidden,
                              autocorrect: false,
                              keyboardType: i == 4
                                  ? TextInputType.emailAddress
                                  : TextInputType.text,
                              textInputAction: TextInputAction.next,
                              autofillHints: [
                                [AutofillHints.newUsername],
                                [AutofillHints.newPassword],
                                [AutofillHints.newPassword],
                                [AutofillHints.nickname],
                                [AutofillHints.email],
                              ][i],
                              decoration: InputDecoration(
                                labelText: label,
                                helperText: i == 0
                                    ? '영문·숫자·밑줄 4~20자'
                                    : i == 1
                                    ? '8~50자 입력'
                                    : null,
                                suffixIcon: i == 1
                                    ? IconButton(
                                        tooltip: hidden
                                            ? '가입 비밀번호 보기'
                                            : '가입 비밀번호 숨기기',
                                        onPressed: () =>
                                            setState(() => hidden = !hidden),
                                        icon: Icon(
                                          hidden
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 21,
                                        ),
                                      )
                                    : null,
                              ),
                              validator: (v) => validate(i, v),
                            ),
                            const FieldGap(),
                          ],
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '전공 구분',
                            ),
                            items: majors.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                            onChanged: busy
                                ? null
                                : (v) => setState(() => major = v),
                            validator: (v) =>
                                v == null ? '전공 구분을 선택해 주세요.' : null,
                          ),
                          const SizedBox(height: 10),
                          const HelpText('선택한 전공 구분은 학습계획과 상담에 활용해요.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            StickyActions('가입 완료', submit, busy: busy, error: error),
          ],
        ),
      ),
    ),
  );
}

Future<void> showConnection(BuildContext context, Session session) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => _Connection(session)),
    );

class _Connection extends StatefulWidget {
  final Session session;
  const _Connection(this.session);
  @override
  State<_Connection> createState() => _ConnectionState();
}

class _ConnectionState extends State<_Connection> {
  late final field = TextEditingController(text: widget.session.origin);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.changeOrigin(field.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('서버 연결')),
    body: SafeArea(
      child: ScrollBody(
        children: [
          const Heading('팀 서버 주소'),
          const HelpText('같은 서버에 연결하면 웹의 계정과 학습계획을 앱에서 사용할 수 있어요.'),
          const SizedBox(height: 19),
          TextField(
            controller: field,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '서버 주소'),
            onSubmitted: (_) => save(),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('에뮬레이터'),
                  onPressed: () => setState(() => field.text = emulatorOrigin),
                ),
                ActionChip(
                  label: const Text('USB 연결'),
                  onPressed: () => setState(() => field.text = usbOrigin),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const HelpText('USB 연결은 PC에서 서버 켜기를 실행한 뒤 사용하세요.'),
          ],
          if (error != null) AlertText(error!),
          const SizedBox(height: 21),
          PrimaryAction('연결 주소 저장', save, busy: busy),
        ],
      ),
    ),
  );
}

class ProfileScreen extends StatelessWidget {
  final Session session;
  final VoidCallback openPlan;
  const ProfileScreen(this.session, this.openPlan, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = session.user!;
    return ScrollBody(
      children: [
        Pane(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: pale,
                child: Text(
                  p.name.isEmpty ? 'P' : p.name.characters.first,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: blue,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    HelpText(p.email),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Heading('나의 계정'),
        Pane(
          child: Column(
            children: [
              _InfoRow('아이디', p.id),
              const SizedBox(height: 15),
              _InfoRow('전공 구분', p.major),
              const SizedBox(height: 15),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '회원정보 수정',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => EditProfile(session)),
                  );
                  if (ok == true && context.mounted) {
                    toast(context, '회원정보를 수정했어요.');
                  }
                },
              ),
            ],
          ),
        ),
        const Heading('학습 설정'),
        Pane(
          padding: 0,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: const ExamIcon('SQL', size: 39),
            title: const Text(
              '학습계획 관리',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '목표 설정 · 계획 만들기 · 저장된 일정',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: openPlan,
          ),
        ),
        if (showsAdminPage(session)) ...[
          const Heading('관리자'),
          Pane(padding: 0, child: AdminPageLink(session)),
        ],
        const SizedBox(height: 25),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await session.logout();
            } catch (e) {
              if (context.mounted) toast(context, friendly(e));
            }
          },
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('로그아웃'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, b) {
      final name = Text(
        label,
        style: const TextStyle(color: muted, fontSize: 14),
      );
      final content = Text(
        value,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      );
      if (b.maxWidth < 260 || MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [name, const SizedBox(height: 5), content],
        );
      }
      return Row(
        children: [
          Expanded(child: name),
          Flexible(child: content),
        ],
      );
    },
  );
}
