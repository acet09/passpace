"""This task must leave all team/backend sources byte-identical."""
import hashlib
import json
import os
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
OUT = APP / 'docs/timer-navigation'
BEFORE = json.loads((OUT / 'scope-before.json').read_text(encoding='utf-8-sig'))
ROOTS = {'team': Path('C:/Users/std66/passpace11144'),
         'legacyBackend': APP.parent / 'backend', 'app': APP}
SKIP = {'.git', '.gradle', 'build', '.dart_tool', '.idea', 'logs',
        'collect-data', '.runtime', 'out', '__pycache__'}
ALLOWED_LIB = {'lib/data/study_timer.dart','lib/data/study_timer_notifications.dart',
  'lib/ui/dashboard.dart','lib/ui/plan_month_calendar.dart','lib/ui/study_records.dart','lib/ui/study_timer_screen.dart'}
ALLOWED_ANDROID = {'android/app/src/main/AndroidManifest.xml',
  'android/app/src/main/kotlin/kr/passpace/mobile/passpace_mobile/MainActivity.kt',
  'android/app/src/main/kotlin/kr/passpace/mobile/passpace_mobile/StudyTimerService.kt',
  'android/app/src/main/kotlin/kr/passpace/mobile/passpace_mobile/StudyTimerBridge.kt',
  'android/app/src/main/res/drawable/ic_study_timer.xml'}



def inventory(root):
    paths = set()
    for folder, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP]
        paths.update(str(Path(folder) / f) for f in files)
    return paths


result = {}
for kind, root in ROOTS.items():
    baseline = {r['path']: r['hash'] for r in BEFORE[kind]}
    current = inventory(root)
    missing = sorted(set(baseline) - current)
    added = sorted(current - set(baseline))
    changed = sorted(p for p, h in baseline.items() if p in current and
                     hashlib.sha256(Path(p).read_bytes()).hexdigest() != h)
    assert not missing, 'Existing files removed'
    if kind != 'app':
        assert not changed and not added, 'Protected project modified'
    else:
        for p in changed + added:
            rel = Path(p).relative_to(APP).as_posix()
            if rel.startswith('lib/'):
                assert rel in ALLOWED_LIB, 'Unrelated app production code modified'
            if rel.startswith('android/'):
                assert rel in ALLOWED_ANDROID, 'Unrelated Android file modified'
        for p in changed:
            rel = Path(p).relative_to(APP).as_posix()
            assert not rel.startswith('android/') or rel in ALLOWED_ANDROID, 'Unrelated Android file changed'
            assert rel not in {'pubspec.yaml', 'pubspec.lock', 'scripts/Start-TeamServer.ps1'}, 'Protected app setting changed'
    result[kind] = {'baselineFiles': len(baseline),
        'unchanged': len(baseline) - len(changed), 'changed': changed,
        'added': added, 'missing': missing}
result['productionTestWrites'] = False
(OUT / 'scope-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:{'unchanged':r['unchanged'],'changed':len(r['changed']),
    'added':len(r['added']),'missing':len(r['missing'])} for k,r in result.items() if isinstance(r,dict)}))
