import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'design.dart';

class EditProfile extends StatefulWidget {
  final Session session;
  const EditProfile(this.session, {super.key});
  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  late final profile = widget.session.user!;
  late final name = TextEditingController(text: profile.name),
      email = TextEditingController(text: profile.email);
  late String? major = majors.entries
      .where((e) => e.value == profile.major)
      .firstOrNull
      ?.key;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final n = name.text.trim(), mail = email.text.trim();
    if (n.isEmpty ||
        n.length > 50 ||
        mail.length > 255 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(mail) ||
        major == null) {
      setState(() => error = '닉네임, 이메일 주소, 전공 구분을 확인해 주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.updateProfile(n, mail, major!);
      if (mounted) Navigator.pop(context, true);
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
      appBar: AppBar(title: const Text('회원정보 수정')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ScrollBody(
                children: [
                  const Heading('나의 프로필'),
                  TextField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 50,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '닉네임'),
                  ),
                  const FieldGap(),
                  TextField(
                    controller: email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '이메일'),
                  ),
                  const FieldGap(),
                  DropdownButtonFormField<String>(
                    initialValue: major,
                    decoration: const InputDecoration(labelText: '전공 구분'),
                    items: majors.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: busy ? null : (v) => setState(() => major = v),
                  ),
                ],
              ),
            ),
            StickyActions('변경 저장', save, busy: busy, error: error),
          ],
        ),
      ),
    ),
  );
}
