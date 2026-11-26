import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/session.dart';
import 'design.dart';

class AccountWithdrawalScreen extends StatefulWidget {
  final Session session;
  final Future<bool> Function()? prepare;
  const AccountWithdrawalScreen(this.session, {super.key, this.prepare});

  @override
  State<AccountWithdrawalScreen> createState() =>
      _AccountWithdrawalScreenState();
}

class _AccountWithdrawalScreenState extends State<AccountWithdrawalScreen> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  late final PassApi? account;
  late final String phrase;
  bool busy = false, uncertain = false, changed = false;
  String? error;
  bool get ready =>
      !busy &&
      !uncertain &&
      !changed &&
      password.text.isNotEmpty &&
      confirmation.text == phrase;

  @override
  void initState() {
    super.initState();
    // Capture the identity when opening the confirmation screen.
    account = widget.session.account;
    phrase = '${widget.session.user!.id}회원탈퇴';
    widget.session.addListener(accountChanged);
  }

  void accountChanged() {
    if (identical(account, widget.session.account)) return;
    password.clear();
    if (mounted && !busy) {
      setState(() {
        changed = true;
        error = '계정이 바뀌었어요. 현재 로그인 정보를 확인하고 화면을 다시 열어 주세요.';
      });
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(accountChanged);
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!ready || !identical(account, widget.session.account)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final request = widget.session.withdrawAccount(
        password.text,
        confirmation.text,
        prepare: widget.prepare,
      );
      password.clear();
      await request;
    } catch (e) {
      if (mounted) {
        setState(() {
          error = friendly(e);
          uncertain = e is AccountWithdrawalUncertain;
        });
      }
    } finally {
      if (mounted) {
        password.clear();
        setState(() => busy = false);
      }
    }
  }

  Future<void> checkAccount() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.session.logout();
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
      appBar: AppBar(
        title: const Text('회원탈퇴'),
        leading: IgnorePointer(
          ignoring: busy,
          child: BackButton(
            onPressed: busy ? null : () => Navigator.maybePop(context),
          ),
        ),
      ),
      body: SafeArea(
        child: ScrollBody(
          children: [
            const Heading('회원탈퇴 전 확인해 주세요'),
            const Pane(
              color: pale,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '회원정보와 본인의 학습계획·학습기록·대화를 서버에서 영구 삭제해요.',
                    style: TextStyle(fontWeight: FontWeight.w700, height: 1.6),
                  ),
                  SizedBox(height: 12),
                  Text('삭제된 정보는 복구할 수 없어요.', style: TextStyle(height: 1.6)),
                  SizedBox(height: 12),
                  Text(
                    '탈퇴가 확인되면 이 기기의 로그인 정보와 학습계획 초안·타이머를 정리해요. '
                    '현재 측정은 요청 전에 일시정지해요.',
                    style: TextStyle(height: 1.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('withdrawal-password'),
              controller: password,
              enabled: !busy && !uncertain && !changed,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [],
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '현재 비밀번호'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            const HelpText('아래 문구를 정확히 입력해 주세요.'),
            const SizedBox(height: 8),
            SelectableText(
              phrase,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.6),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('withdrawal-confirmation'),
              controller: confirmation,
              enabled: !busy && !uncertain && !changed,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [],
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: '아이디 확인 문구'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 12),
            const HelpText('취소하거나 서버가 요청을 거부하면 계정을 유지해요.'),
            if (error != null) AlertText(error!),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('withdrawal-submit'),
              onPressed: ready ? submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: busy
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Flexible(child: Text('처리 중')),
                      ],
                    )
                  : const Text('계정과 내 데이터 영구 삭제'),
            ),
            if (uncertain) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('withdrawal-check-account'),
                onPressed: busy ? null : checkAccount,
                child: const Text('로그인 화면에서 확인'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
