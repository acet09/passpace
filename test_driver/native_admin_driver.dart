import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('docs/native-admin/screenshots');
  await directory.create(recursive: true);
  final names = <String>{};
  await integrationDriver(
    onScreenshot:
        (
          String name,
          List<int> bytes, [
          Map<String, Object?>? arguments,
        ]) async {
          if (!RegExp(r'^(live-)?admin-[a-z-]+$').hasMatch(name)) return false;
          await File('${directory.path}/$name.png').writeAsBytes(bytes);
          names.add(name);
          return true;
        },
    responseDataCallback: (_) async {
      final live = names.any((n) => n.startsWith('live-'));
      await File('docs/native-admin/${live ? 'live' : 'sample'}-captures.json')
          .writeAsString(
            jsonEncode({
              'data': live
                  ? 'isolated real API with synthetic SAMPLE data'
                  : 'SAMPLE MockClient',
              'screenshots': names.toList()..sort(),
            }),
          );
    },
    writeResponseOnFailure: true,
  );
}
