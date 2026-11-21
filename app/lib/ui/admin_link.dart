import 'package:flutter/material.dart';

import '../data/session.dart';
import 'admin_api.dart';
import 'admin_screen.dart';
import 'admin_widgets.dart';
import 'design.dart';

export 'admin_api.dart' show showsAdminPage;

class AdminPageLink extends StatelessWidget {
  final Session session;
  const AdminPageLink(this.session, {super.key});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    leading: const Icon(Icons.admin_panel_settings_outlined, color: blue),
    title: const Text(
      '관리자 페이지',
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: const Text(
      '데이터 조회 · 수집 관리',
      style: TextStyle(fontSize: 12, color: muted, height: 1.5),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, size: 22),
    onTap: () {
      if (!showsAdminPage(session)) {
        toast(context, '관리자 권한을 다시 확인해 주세요.');
        return;
      }
      final api = AdminApi(session);
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              AdminAccessGate(api, ownsApi: true, child: AdminScreen(api)),
        ),
      );
    },
  );
}
