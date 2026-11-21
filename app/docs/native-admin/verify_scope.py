"""Compare the recorded pre-work snapshot and verify the normal APK."""
from pathlib import Path
import hashlib
import json
import os
import zipfile

APP = Path(__file__).resolve().parents[2]
OUT = APP/'docs/native-admin'
EXCLUDE = {'.git','.gradle','.idea','.dart_tool','build','.runtime','node_modules','.vscode'}


def snapshot(base):
    result = {}
    for parent, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDE)
        for name in sorted(files):
            if name.endswith(('.log','.lockfile')) or name == '.DS_Store':
                continue
            path = Path(parent)/name
            result[path.relative_to(base).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def delta(before, after):
    return {'added':sorted(after.keys()-before.keys()), 'removed':sorted(before.keys()-after.keys()),
            'changed':sorted(p for p in before.keys() & after.keys() if before[p] != after[p])}


before = json.loads((OUT/'scope-before.json').read_text(encoding='utf-8'))
after = {'team': snapshot(Path('C:/Users/std66/passpace11144')), 'legacyBackend': snapshot(APP.parent/'backend'), 'mobile':{}}
for name in ['lib','android','scripts']:
    after['mobile'].update({f'{name}/{p}':h for p,h in snapshot(APP/name).items()})
for name in ['pubspec.yaml','pubspec.lock','analysis_options.yaml']:
    path = APP/name
    if path.exists(): after['mobile'][name] = hashlib.sha256(path.read_bytes()).hexdigest()
changes = {k:delta(before[k],after[k]) for k in before}
unexpected = [p for values in changes['mobile'].values() for p in values
              if not (p.startswith('lib/ui/admin_') and p.endswith('.dart'))]
result = {'teamFiles':len(before['team']), 'legacyBackendFiles':len(before['legacyBackend']),
          'mobileFilesBefore':len(before['mobile']), 'changes':changes, 'unexpectedMobileChanges':unexpected,
          'excludedGeneratedDirectories':sorted(EXCLUDE),
          'verified':not unexpected and not any(v for k in ['team','legacyBackend'] for v in changes[k].values())}
(OUT/'scope-verification.json').write_text(json.dumps({'result':result,'before':before,'after':after},ensure_ascii=False,indent=2),encoding='utf-8')
apk = APP/'build/app/outputs/flutter-apk/app-debug.apk'
with zipfile.ZipFile(apk) as archive:
    kernel = archive.read('assets/flutter_assets/kernel_blob.bin')
    checks = {'nativeAdminIncluded':all(s.encode() in kernel for s in ['AdminScreen','AdminAccessGate','수집 관리']),
              'browserBridgeNotCalledByDart':b'openAdminPage' not in kernel,
              'testEntrypointAbsent':all(s.encode() not in kernel for s in ['ADMIN_TEST_PASSWORD','SAMPLE 앱 내부 관리자 검증','http://10.0.2.2:18085','SAMPLE: 앱 내부 관리자 조회'])}
artifact = {'checks':checks,'bytes':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest()}
(OUT/'apk-verification.json').write_text(json.dumps(artifact,indent=2),encoding='utf-8')
print(json.dumps({'scope':result,'apkChecks':checks},ensure_ascii=False))
if not result['verified'] or not all(checks.values()): raise SystemExit(1)
