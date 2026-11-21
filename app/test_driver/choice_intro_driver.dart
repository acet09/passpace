import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final out = Directory('docs/choice-intro-fix/screenshots');
  await out.create(recursive: true);
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          if (!RegExp(r'^after-[a-z-]+$').hasMatch(name)) return false;
          await File('${out.path}/$name.png').writeAsBytes(bytes);
          return true;
        },
    responseDataCallback: (_) async {},
  );
}
