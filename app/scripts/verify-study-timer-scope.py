"""This task must leave all team/backend sources byte-identical."""
import hashlib
import json
import os
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
OUT = APP / 'docs/study-timer'
BEFORE = json.loads((OUT / 'scope-before.json').read_text(encoding='utf-8-sig'))
ROOTS = {'team': Path('C:/Users/std66/passpace11144'),
         'legacyBackend': APP.parent / 'backend', 'app': APP}
SKIP = {'.git', '.gradle', 'build', '.dart_tool', '.idea', 'logs',
        'collect-data', '.runtime', 'out', '__pycache__'}
ALLOWED_LIB = {'lib/data/study_models.dart', 'lib/data/study_timer.dart',
               'lib/ui/study_timer_screen.dart', 'lib/ui/study_task_picker.dart',
               'lib/ui/study_chart.dart', 'lib/ui/study_records.dart',
               'lib/ui/study_record_form.dart'}


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
        for p in changed:
            rel = Path(p).relative_to(APP).as_posix()
            assert not rel.startswith('android/'), 'Android configuration changed'
            assert rel not in {'pubspec.yaml', 'pubspec.lock', 'scripts/Start-TeamServer.ps1'}, 'Protected app setting changed'
    result[kind] = {'baselineFiles': len(baseline),
        'unchanged': len(baseline) - len(changed), 'changed': changed,
        'added': added, 'missing': missing}
result['productionTestWrites'] = False
(OUT / 'scope-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:{'unchanged':r['unchanged'],'changed':len(r['changed']),
    'added':len(r['added']),'missing':len(r['missing'])} for k,r in result.items() if isinstance(r,dict)}))
