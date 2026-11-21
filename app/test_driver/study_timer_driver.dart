import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('docs/study-timer/screenshots');
  await directory.create(recursive: true);
  final names = <String>{};
  var background = false;
  const adb = 'C:/Users/std66/AppData/Local/Android/Sdk/platform-tools/adb.exe';
  final pidResult = await Process.run(adb, [
    '-s',
    'emulator-5554',
    'shell',
    'pidof',
    'kr.passpace.mobile.passpace_mobile',
  ]);
  final pid = (pidResult.stdout as String).trim();
  if (!RegExp(r'^\d+$').hasMatch(pid)) {
    throw StateError('Test app PID unavailable');
  }
  final log = await Process.start(adb, [
    '-s',
    'emulator-5554',
    'logcat',
    '--pid=$pid',
    '-s',
    'flutter',
  ]);
  unawaited(log.stderr.drain<void>());
  var triggered = false;
  Future<void>? roundTrip;
  final subscription = log.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (triggered || !line.contains('SAMPLE_TIMER_BACKGROUND_READY')) {
          return;
        }
        triggered = true;
        roundTrip = () async {
          final home = await Process.run(adb, [
            '-s',
            'emulator-5554',
            'shell',
            'input',
            'keyevent',
            'KEYCODE_HOME',
          ]);
          if (home.exitCode != 0) return;
          await Future<void>.delayed(const Duration(seconds: 20));
          final resume = await Process.run(adb, [
            '-s',
            'emulator-5554',
            'shell',
            'am',
            'start',
            '-n',
            'kr.passpace.mobile.passpace_mobile/.MainActivity',
          ]);
          background = resume.exitCode == 0;
        }();
      });
  try {
    await integrationDriver(
      onScreenshot:
          (String name, List<int> bytes, [Map<String, Object?>? args]) async {
            if (!RegExp(r'^live-timer-[a-z-]+$').hasMatch(name)) return false;
            await File('${directory.path}/$name.png').writeAsBytes(bytes);
            names.add(name);
            return true;
          },
      responseDataCallback: (data) async {
        await roundTrip;
        await File('docs/study-timer/android-result.json').writeAsString(
          jsonEncode({
            'result': data == null
                ? null
                : {
                    for (final e in data.entries)
                      if (e.key != 'screenshots') e.key: e.value,
                  },
            'nativeBackgroundRoundTrip': background,
            'screenshots': names.toList()..sort(),
          }),
        );
        if (!background) {
          throw StateError('Android HOME/resume was not verified');
        }
      },
      writeResponseOnFailure: true,
    );
  } finally {
    await subscription.cancel();
    log.kill();
  }
}
