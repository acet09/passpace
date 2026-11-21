import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;

import 'data/session.dart';
import 'ui/auth.dart';
import 'ui/dashboard.dart';
import 'ui/design.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PassPaceApp(Session(AndroidStore(), http.Client())..restore()));
}

class PassPaceApp extends StatelessWidget {
  final Session session;
  const PassPaceApp(this.session, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => MaterialApp(
      key: ValueKey(session.user?.id),
      title: 'PASS PACE',
      debugShowCheckedModeBanner: false,
      theme: paceTheme(),
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: session.restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : session.restoreError != null
          ? _RestoreScreen(session)
          : session.user != null
          ? Dashboard(session)
          : AuthScreen(session),
    ),
  );
}

class _RestoreScreen extends StatelessWidget {
  final Session session;
  const _RestoreScreen(this.session);
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ScrollBody(
        children: [
          const Brand(),
          const Heading('로그인 연결 확인'),
          AlertText(session.restoreError!),
          const FieldGap(),
          PrimaryAction('다시 연결', session.restore),
          TextButton(
            onPressed: () => showConnection(context, session),
            child: const Text('서버 연결 설정'),
          ),
          OutlinedButton(
            onPressed: () async {
              try {
                await session.logout();
              } catch (_) {
                if (context.mounted) toast(context, '기기에서 로그인 정보를 지우지 못했어요.');
              }
            },
            child: const Text('로그인 화면으로'),
          ),
        ],
      ),
    ),
  );
}
