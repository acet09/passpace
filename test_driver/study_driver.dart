import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('docs/study-records/screenshots');
  await directory.create(recursive: true);
  final names = <String>{};
  await integrationDriver(
    onScreenshot:
        (
          String name,
          List<int> bytes, [
          Map<String, Object?>? arguments,
        ]) async {
          if (!RegExp(r'^live-study-[a-z-]+$').hasMatch(name)) return false;
          await File('${directory.path}/$name.png').writeAsBytes(bytes);
          names.add(name);
          return true;
        },
    responseDataCallback: (data) async {
      await File('docs/study-records/live-result.json').writeAsString(
        jsonEncode({
          'result': data == null
              ? null
              : {
                  for (final entry in data.entries)
                    if (entry.key != 'screenshots') entry.key: entry.value,
                },
          'screenshots': names.toList()..sort(),
        }),
      );
    },
    writeResponseOnFailure: true,
  );
}
