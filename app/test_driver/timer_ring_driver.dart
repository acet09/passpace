import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final out = Directory('docs/timer-ring/screenshots');
  await out.create(recursive: true);
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          if (!RegExp(r'^sample-[a-z-]+$').hasMatch(name)) return false;
          await File('${out.path}/$name.png').writeAsBytes(bytes);
          return true;
        },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File('docs/timer-ring/sample-android-result.json')
          .writeAsString(jsonEncode(result));
    },
  );
}
