"""Run Java regressions only in a source copy and verified disposable MariaDB."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', choices=['red', 'green'], required=True)
    parser.add_argument('--fixture-root', type=Path, required=True)
    parser.add_argument('--feature', choices=['study-edit', 'study-actions'], default='study-edit')
    args = parser.parse_args()
    app = Path(__file__).resolve().parents[1]
    evidence = app / 'docs' / args.feature
    meta = json.loads((evidence / 'workspace.json').read_text(encoding='utf-8'))
    project = Path(meta['project']).resolve()
    assert project.parent.parent == Path(tempfile.gettempdir()).resolve()
    assert project.parent.name.startswith('passpace-' + args.feature + '-')
    fixture = args.fixture_root.resolve()
    assert fixture.parent == Path(tempfile.gettempdir()).resolve()
    assert fixture.name.startswith('passpace-study-api-')
    datadir = (fixture / 'database').resolve()
    assert datadir.parent == fixture and datadir.is_dir()
    tests = project / 'src/test/java/com/passpace/study'
    tests.mkdir(parents=True, exist_ok=True)
    shutil.copy2(app / 'integration_test/support/java/StudyApiContractTest.java',
                 tests / 'StudyApiContractTest.java')
    if args.phase == 'green':
        for filename in meta['sixFiles']:
            shutil.copy2(Path(meta['candidate']) / filename,
                         project / 'src/main/java/com/passpace/study' / filename)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    assert port not in (3306, 3308, 8080, 18080)
    env = os.environ.copy()
    env.pop('MYSQL_PWD', None)
    env.update({'JAVA_HOME': r'C:\Program Files\Java\jdk-21.0.12',
                'STUDY_TEST_DB_PORT': str(port), 'STUDY_TEST_DB_DATADIR': str(datadir)})
    log = (project.parent / 'database.log').open('w', encoding='utf-8')
    db = subprocess.Popen([r'C:\Program Files\MariaDB 12.2\bin\mariadbd.exe', '--no-defaults',
        '--datadir=' + str(datadir), '--port=' + str(port), '--bind-address=127.0.0.1',
        '--skip-name-resolve', '--max-connections=50', '--pid-file=' + str(project.parent / 'database.pid'),
        '--log-error=' + str(project.parent / 'database-error.log')],
        env=env, stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        deadline = time.monotonic() + 30
        while True:
            check = subprocess.run([r'C:\Program Files\MariaDB 12.2\bin\mariadb.exe',
                '--no-defaults', '--host=127.0.0.1', '--port=' + str(port), '--user=root',
                '--batch', '--skip-column-names', '--execute=SELECT @@datadir;'],
                env=env, capture_output=True, text=True, timeout=5)
            if check.returncode == 0:
                assert Path(check.stdout.strip()).resolve() == datadir
                break
            if db.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('Private database failed to start')
            time.sleep(.25)
        command = ['cmd.exe', '/d', '/c', 'gradlew.bat', '--offline', '--no-daemon',
                   '--console=plain', 'test']
        if args.phase == 'red':
            names = ['deleteRemovesOnlyOwnedRecordAndUpdatesStats', 'planTaskChoicesExposeRealOwnedIdentifiers'] if args.feature == 'study-actions' else ['patchChangesDateAndMinutesPreservingRecordAndPlanMetadata']
            for name in names:
                command += ['--tests', 'com.passpace.study.StudyApiContractTest.' + name]
        else:
            command += ['bootJar']
        logfile = evidence / ('java-' + args.phase + '.log')
        with logfile.open('w', encoding='utf-8') as output:
            completed = subprocess.run(command, cwd=project, env=env,
                stdout=output, stderr=output, timeout=300, creationflags=subprocess.CREATE_NO_WINDOW)
        content = logfile.read_text(encoding='utf-8', errors='replace')
        content = re.sub(r'(Using generated security password:)\s*[^\r\n]+', r'\1 [REDACTED]', content)
        logfile.write_text(content, encoding='utf-8')
        totals = {'tests': 0, 'failures': 0, 'errors': 0, 'skipped': 0}
        failures = []
        for file in (project / 'build/test-results/test').glob('TEST-*.xml'):
            suite = ET.parse(file).getroot()
            for key in totals:
                totals[key] += int(suite.attrib.get(key, 0))
            for case in suite.findall('testcase'):
                failure = case.find('failure')
                if failure is not None:
                    failures.append({'name': case.attrib['name'], 'message': failure.attrib.get('message', '')[:300]})
        result = {'phase': args.phase, 'exitCode': completed.returncode, **totals,
                  'failedTests': failures, 'database': 'verified disposable MariaDB',
                  'originalProjectWrites': False}
        (evidence / ('java-' + args.phase + '-result.json')).write_text(
            json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps(result))
        raise SystemExit(completed.returncode)
    finally:
        if db.poll() is None:
            db.terminate()
            try:
                db.wait(timeout=10)
            except subprocess.TimeoutExpired:
                db.kill()
                db.wait(timeout=5)
        log.close()


if __name__ == '__main__':
    main()
