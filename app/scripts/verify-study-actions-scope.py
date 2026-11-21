"""Compare this task's source snapshot without reading/logging private values."""
import hashlib
import json
import os
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
EVIDENCE = APP / 'docs/study-actions'
BEFORE = json.loads((EVIDENCE / 'scope-before.json').read_text(encoding='utf-8-sig'))
ROOTS = {
    'team': Path('C:/Users/std66/passpace11144'),
    'legacyBackend': APP.parent / 'backend',
    'app': APP,
}
SKIP = {'.git', '.gradle', 'build', '.dart_tool', '.idea', 'logs',
        'collect-data', '.runtime', 'out', '__pycache__'}
NAMES = {'JdbcStudyRepository.java', 'StudyController.java', 'StudyDtos.java',
         'StudyRepository.java', 'StudyService.java', 'StudyServiceImpl.java'}
OWNED = {str(ROOTS['team'] / 'src/main/java/com/passpace/study' / n) for n in NAMES}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inventory(root):
    paths = []
    for directory, folders, files in os.walk(root):
        folders[:] = [f for f in folders if f not in SKIP]
        paths.extend(str(Path(directory) / f) for f in files)
    return set(paths)


result = {}
for key, root in ROOTS.items():
    baseline = {v['path']: v['hash'] for v in BEFORE[key]}
    current = inventory(root)
    changed = sorted(p for p, h in baseline.items() if p in current and digest(p) != h)
    missing = sorted(set(baseline) - current)
    added = sorted(current - set(baseline))
    if key == 'team':
        assert set(changed) == OWNED, 'Team changes exceeded the six owned files'
        assert not missing and not added, 'Team files added or removed'
    elif key == 'legacyBackend':
        assert not changed and not missing and not added, 'Legacy backend changed'
    result[key] = {
        'baselineFiles': len(baseline),
        'unchanged': len(baseline) - len(changed) - len(missing),
        'changed': changed, 'missing': missing, 'added': added,
    }

workspace = json.loads((EVIDENCE / 'workspace.json').read_text(encoding='utf-8-sig'))
tested = Path(workspace['project']) / 'src/main/java/com/passpace/study'
assert all(digest(tested / n) == digest(ROOTS['team'] / 'src/main/java/com/passpace/study' / n)
           for n in NAMES), 'Actual source differs from tested Java source'
result['testedJavaMatchesActual'] = True
result['productionTestWrites'] = False
(EVIDENCE / 'scope-result.json').write_text(
    json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k: {'unchanged': v['unchanged'], 'changed': len(v['changed']),
                     'added': len(v['added']), 'missing': len(v['missing'])}
                  for k, v in result.items() if isinstance(v, dict)}))
