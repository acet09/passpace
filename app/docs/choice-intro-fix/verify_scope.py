from pathlib import Path
import hashlib
import json
import os
import zipfile

APP = Path(__file__).resolve().parents[2]
OUT = APP/'docs/choice-intro-fix'
EXCLUDE = {'.git','.gradle','.idea','.dart_tool','build','.runtime','node_modules','.vscode','collect-data','logs'}

def snapshot(base):
    result = {}
    for parent, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDE)
        for name in sorted(files):
            if name.endswith(('.log','.lockfile')) or name == '.DS_Store': continue
            p = Path(parent)/name
            result[p.relative_to(base).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result

before = json.loads((OUT/'scope-before.json').read_text(encoding='utf-8'))
before = {key:{p:h for p,h in values.items() if not set(Path(p).parts)&EXCLUDE} for key,values in before.items()}
after = {'team':snapshot(Path('C:/Users/std66/passpace11144')), 'legacyBackend':snapshot(APP.parent/'backend'), 'mobile':{}}
for name in ['lib','android','scripts']:
    after['mobile'].update({name+'/'+p:h for p,h in snapshot(APP/name).items()})
for name in ['pubspec.yaml','pubspec.lock','analysis_options.yaml']:
    p = APP/name
    if p.exists(): after['mobile'][name] = hashlib.sha256(p.read_bytes()).hexdigest()
changes = {}
for key in before:
    old,new = before[key],after[key]
    changes[key] = {'added':sorted(new.keys()-old.keys()),'removed':sorted(old.keys()-new.keys()),
                    'changed':sorted(k for k in old.keys()&new.keys() if old[k]!=new[k])}
allowed = {'lib/ui/admin_widgets.dart','lib/ui/auth_intro.dart'}
unexpected = [p for values in changes['mobile'].values() for p in values if p not in allowed]
result = {'teamSourceFiles':len(before['team']), 'legacyBackendFiles':len(before['legacyBackend']),
    'mobileExistingFiles':len(before['mobile']), 'changes':changes, 'unexpectedMobileChanges':unexpected,
    'excludedGeneratedOrRuntimeDirectories':sorted(EXCLUDE),
    'verified':not unexpected and not any(v for k in ['team','legacyBackend'] for v in changes[k].values())}
(OUT/'scope-verification.json').write_text(json.dumps({'result':result,'before':before,'after':after},ensure_ascii=False,indent=2),encoding='utf-8')
apk = APP/'build/app/outputs/flutter-apk/app-debug.apk'
with zipfile.ZipFile(apk) as archive:
    kernel = archive.read('assets/flutter_assets/kernel_blob.bin')
    checks = {'normalAppIncludesAdminChoice':b'AdminChoice' in kernel,
        'integrationEntrypointsAbsent':all(s.encode() not in kernel for s in ['choice_intro_test.dart','admin_choice_visibility_test.dart','AdminFixture']),
        'proposedStudyApiNotImplemented':b'/api/study/timer' not in kernel}
artifact = {'checks':checks,'bytes':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest()}
(OUT/'apk-verification.json').write_text(json.dumps(artifact,indent=2),encoding='utf-8')
print(json.dumps({'scope':result,'apkChecks':checks},ensure_ascii=False))
if not result['verified'] or not all(checks.values()): raise SystemExit(1)
