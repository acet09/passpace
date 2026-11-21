import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const adb = 'C:/Users/std66/AppData/Local/Android/Sdk/platform-tools/adb.exe';
  const package = 'kr.passpace.mobile.passpace_mobile';
  final dir = Directory('docs/timer-navigation/screenshots');
  await dir.create(recursive: true);
  final names = <String>{};
  final checks = <String, bool>{
    'foregroundService': false,
    'notificationVisible': false,
    'chronometerVisible': false,
    'notificationTapped': false,
    'pauseRemovesService': false,
  };
  var nativeStage = '';
  Future<String> shell(List<String> args) async {
    nativeStage = args.first;
    final r = await Process.run(
      adb,
      ['-s', 'emulator-5554', 'shell', ...args],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) throw StateError('SAMPLE Android command failed');
    return r.stdout as String;
  }

  await shell([
    'pm',
    'grant',
    package,
    'android.permission.POST_NOTIFICATIONS',
  ]);
  final pid = (await shell(['pidof', package])).trim();
  if (!RegExp(r'^\d+$').hasMatch(pid)) throw StateError('Test app PID missing');
  final log = await Process.start(adb, [
    '-s',
    'emulator-5554',
    'logcat',
    '--pid=$pid',
    '-s',
    'flutter',
  ]);
  unawaited(log.stderr.drain<void>());
  Future<void>? roundTrip, paused;
  var began = false, didPause = false;
  String? nativeError;
  final sub = log.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (!began && line.contains('SAMPLE_NOTIFICATION_READY')) {
          began = true;
          roundTrip = () async {
            try {
              await Future<void>.delayed(const Duration(seconds: 2));
              final services = await shell([
                'dumpsys',
                'activity',
                'services',
                package,
              ]);
              checks['foregroundService'] =
                  services.contains('foregroundId=17041') &&
                  services.contains('isForeground=true');
              await shell(['input', 'keyevent', 'KEYCODE_HOME']);
              await Future<void>.delayed(const Duration(seconds: 3));
              await shell(['cmd', 'statusbar', 'expand-notifications']);
              await Future<void>.delayed(const Duration(seconds: 2));
              String xml = '';
              RegExpMatch? title;
              for (var attempt = 0; attempt < 4; attempt++) {
                final output =
                    'passpace-${DateTime.now().microsecondsSinceEpoch}.xml';
                await shell([
                  'CLASSPATH=/system/framework/android.test.base.jar:/system/framework/android.test.runner.jar:/system/framework/uiautomator.jar:/data/local/tmp/passpace-ui-snapshot.jar',
                  'app_process',
                  '/system/bin',
                  'com.android.commands.uiautomator.Launcher',
                  'runtest',
                  '-c',
                  'com.passpace.tools.NotificationDumpTest',
                  '-e',
                  'out',
                  output,
                  '-e',
                  'jars',
                  '/data/local/tmp/passpace-ui-snapshot.jar',
                ]);
                xml = await shell(['cat', '/data/local/tmp/$output']);
                title = RegExp(
                  r'<node[^>]*text="집중 타이머[^\"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
                ).firstMatch(xml);
                if (title != null) break;
                await Future<void>.delayed(const Duration(seconds: 2));
              }
              checks['notificationVisible'] = title != null;
              checks['chronometerVisible'] =
                  xml.contains('chronometer') || xml.contains('Chronometer');
              final shot = await Process.run(adb, [
                '-s',
                'emulator-5554',
                'exec-out',
                'screencap',
                '-p',
              ], stdoutEncoding: null);
              await File('${dir.path}/live-navigation-notification.png')
                  .writeAsBytes(shot.stdout as List<int>);
              names.add('live-navigation-notification');
              if (title == null) {
                throw StateError('SAMPLE ongoing notification missing');
              }
              final x = (int.parse(title[1]!) + int.parse(title[3]!)) ~/ 2,
                  y = (int.parse(title[2]!) + int.parse(title[4]!)) ~/ 2;
              await shell(['input', 'tap', '$x', '$y']);
              checks['notificationTapped'] = true;
            } catch (e) {
              nativeError =
                  'notification-drawer-flow:$nativeStage:${e.runtimeType}';
            }
          }();
        }
        if (!didPause && line.contains('SAMPLE_NOTIFICATION_PAUSED')) {
          didPause = true;
          paused = () async {
            try {
              for (var i = 0; i < 20; i++) {
                final services = await shell([
                  'dumpsys',
                  'activity',
                  'services',
                  package,
                ]);
                if (!services.contains('foregroundId=17041')) {
                  checks['pauseRemovesService'] = true;
                  break;
                }
                await Future<void>.delayed(const Duration(milliseconds: 250));
              }
            } catch (_) {
              nativeError = 'notification-pause-flow';
            }
          }();
        }
      });
  try {
    await integrationDriver(
      onScreenshot:
          (String name, List<int> bytes, [Map<String, Object?>? args]) async {
            if (!RegExp(r'^live-navigation-[a-z-]+$').hasMatch(name)) {
              return false;
            }
            await File('${dir.path}/$name.png').writeAsBytes(bytes);
            names.add(name);
            return true;
          },
      responseDataCallback: (data) async {
        await roundTrip;
        await paused;
        await File('docs/timer-navigation/android-result.json').writeAsString(
          jsonEncode({
            'result': data == null
                ? null
                : {
                    for (final e in data.entries)
                      if (e.key != 'screenshots') e.key: e.value,
                  },
            'nativeChecks': checks,
            'nativeError': nativeError,
            'screenshots': names.toList()..sort(),
            'permission': 'pregranted only on test emulator',
            'productionWrites': false,
          }),
        );
        if (nativeError != null || checks.values.any((v) => !v)) {
          throw StateError('SAMPLE native notification checks failed');
        }
      },
      writeResponseOnFailure: true,
    );
  } finally {
    await sub.cancel();
    log.kill();
  }
}
