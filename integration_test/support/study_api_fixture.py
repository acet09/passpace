"""Serve the previously verified backend binary against its disposable test DB.

Only for local app verification. Never loads .env or the production database.
Credentials stay in native temporary storage and are not printed.
"""
import argparse
import base64
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    assert port not in (3306, 3308, 8080, 8082, 18080)
    return port


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fixture-root', type=Path, required=True)
    parser.add_argument('--control-file', type=Path, required=True)
    parser.add_argument('--project-root', type=Path)
    parser.add_argument('--study-edit-checks', action='store_true')
    parser.add_argument('--record-actions-checks', action='store_true')
    parser.add_argument('--timer-checks', action='store_true')
    parser.add_argument('--navigation-checks', action='store_true')
    args = parser.parse_args()
    args.timer_checks = args.timer_checks or args.navigation_checks
    args.study_edit_checks = args.study_edit_checks or args.record_actions_checks
    root = args.fixture_root.resolve()
    assert root.parent == Path(tempfile.gettempdir()).resolve()
    assert root.name.startswith('passpace-study-api-')
    datadir = (root / 'database').resolve()
    assert datadir.parent == root and datadir.is_dir()
    project = (args.project_root or root / 'project').resolve()
    if args.project_root:
        assert project.parent.parent == Path(tempfile.gettempdir()).resolve()
        assert project.parent.name.startswith(('passpace-study-edit-', 'passpace-study-actions-'))
    jar = project / 'build/libs/passpace-0.1.0.jar'
    assert jar.is_file()
    # The six API sources used for the binary must still match the actual project.
    source = Path(r'C:\Users\std66\passpace11144/src/main/java/com/passpace/study')
    copied = project / 'src/main/java/com/passpace/study'
    for file in source.glob('*.java'):
        assert file.read_bytes() == (copied / file.name).read_bytes()
    assert len(list(source.glob('*.java'))) == 6
    run = Path(tempfile.mkdtemp(prefix='passpace-app-records-'))
    dbport, port = free_port(), free_port()
    assert dbport != port
    db_env = os.environ.copy()
    db_env.pop('MYSQL_PWD', None)
    db_log = (run / 'database.log').open('w', encoding='utf-8')
    dbproc = subprocess.Popen([
        r'C:\Program Files\MariaDB 12.2\bin\mariadbd.exe', '--no-defaults',
        '--datadir=' + str(datadir), '--port=' + str(dbport), '--bind-address=127.0.0.1',
        '--skip-name-resolve', '--max-connections=40', '--pid-file=' + str(run / 'db.pid'),
        '--log-error=' + str(run / 'database-error.log')],
        env=db_env, stdout=db_log, stderr=db_log, creationflags=subprocess.CREATE_NO_WINDOW)
    proc = None
    log = None
    try:
        command = [r'C:\Program Files\MariaDB 12.2\bin\mariadb.exe', '--no-defaults',
                   '--host=127.0.0.1', '--port=' + str(dbport), '--user=root',
                   '--batch', '--skip-column-names', '--execute=SELECT @@datadir;']
        deadline = time.monotonic() + 30
        while True:
            check = subprocess.run(command, env=db_env, capture_output=True, text=True, timeout=5)
            if check.returncode == 0:
                assert Path(check.stdout.strip()).resolve() == datadir
                break
            if dbproc.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('Private test database did not start')
            time.sleep(.25)
        empty = run / 'empty.properties'
        empty.write_text('', encoding='utf-8')
        env = os.environ.copy()
        env.update({
            'SPRING_CONFIG_LOCATION': 'optional:file:' + empty.as_posix(),
            'SPRING_CONFIG_IMPORT': '', 'SPRING_SQL_INIT_MODE': 'never',
            'SPRING_DATASOURCE_URL': f'jdbc:mariadb://127.0.0.1:{dbport}/study_api_test',
            'SPRING_DATASOURCE_USERNAME': 'root', 'SPRING_DATASOURCE_PASSWORD': '',
            'JWT_ISSUER': 'isolated-app-records',
            'JWT_SECRET': base64.b64encode(secrets.token_bytes(64)).decode(),
            'JWT_ACCESS_TOKEN_VALIDITY_IN_SECONDS': '7200',
            'PASSPACE_CERTIFICATION_CODE': '1320',
            'PASSPACE_COLLECT_USER_AGENT': 'PASS-PACE-ISOLATED-APP-VERIFY/1.0',
            'PASSPACE_OLLAMA_BASE_URL': 'http://127.0.0.1:9',
            'PASSPACE_OLLAMA_MODEL': 'isolated-unused',
            'PASSPACE_COLLECT_REVIEW_MAX_CHARS': '12000',
            'PASSPACE_COLLECT_DATA_DIR': str(run / 'collect'),
        })
        log = (run / 'server.log').open('w', encoding='utf-8')
        proc = subprocess.Popen([r'C:\Program Files\Java\jdk-21.0.12\bin\java.exe',
            '-jar', str(jar), '--server.address=127.0.0.1', '--server.port=' + str(port)],
            cwd=jar.parent, env=env, stdout=log, stderr=log,
            creationflags=subprocess.CREATE_NO_WINDOW)
        env.pop('JWT_SECRET', None)

        def call(method, path, body=None, token=None):
            headers = {'Accept': 'application/json'}
            if token:
                headers['Authorization'] = 'Bearer ' + token
            data = None
            if body is not None:
                data = json.dumps(body).encode()
                headers['Content-Type'] = 'application/json'
            request = urllib.request.Request(f'http://127.0.0.1:{port}' + path,
                                             data=data, headers=headers, method=method)
            try:
                response = urllib.request.urlopen(request, timeout=5)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, json.loads(response.read())

        deadline = time.monotonic() + 45
        while True:
            if proc.poll() is not None:
                raise RuntimeError('Private Spring Boot exited')
            try:
                status, spec = call('GET', '/v3/api-docs')
                if status == 200:
                    assert '/study/sessions' in spec['paths']
                    assert '/dashboard/study-stats' in spec['paths']
                    break
            except (OSError, ValueError):
                pass
            if time.monotonic() > deadline:
                raise TimeoutError('Private Spring Boot startup timed out')
            time.sleep(.25)
        login = 'app_verify_' + uuid.uuid4().hex[:8]
        password = secrets.token_urlsafe(18)
        status, _ = call('POST', '/auth/signup', {
            'loginId': login, 'password': password, 'passwordConfirm': password,
            'nickname': 'SAMPLE 앱 기록 검증', 'email': login + '@example.invalid',
            'majorType': 'MAJOR',
        })
        assert status == 200
        _, auth = call('POST', '/auth/login', {'loginId': login, 'password': password})
        token = auth['data']['accessToken']
        today = datetime.now(timezone(timedelta(hours=9))).date()
        def seed_plan(login_id):
            assert re.fullmatch(r'[A-Za-z0-9_]{4,20}', login_id)
            def sql(statement):
                result = subprocess.run([r'C:\Program Files\MariaDB 12.2\bin\mariadb.exe',
                    '--no-defaults', '--host=127.0.0.1', '--port=' + str(dbport), '--user=root',
                    '--default-character-set=utf8mb4', '--database=study_api_test', '--batch',
                    '--skip-column-names'], input=statement, env=db_env, capture_output=True,
                    text=True, encoding='utf-8', timeout=5)
                if result.returncode:
                    raise RuntimeError('Disposable plan fixture SQL failed')
                return result.stdout.strip()
            user_id = int(sql("SELECT user_id FROM USERS WHERE login_id='" + login_id + "';"))
            plan_end = today + timedelta(days=45 if args.navigation_checks else 7)
            plan_id = int(sql(f"INSERT INTO STUDY_PLANS(user_id,plan_name,plan_type,version_no,status,start_date,end_date) "
                f"VALUES({user_id},'SAMPLE 학습계획','CHATBOT',3,'ACTIVE','{today-timedelta(days=7)}','{plan_end}'); SELECT LAST_INSERT_ID();"))
            ids=[]
            subjects = [('SAMPLE 데이터베이스', today), ('SAMPLE 소프트웨어 설계', today-timedelta(days=1))]
            if args.timer_checks:
                subjects = [(subject, today+timedelta(days=offset)) for offset in range(-7, 9)
                    for subject in ['SAMPLE 소프트웨어 설계','SAMPLE 데이터베이스','SAMPLE 프로그래밍','SAMPLE 정보시스템']]
            for subject, date in subjects:
                task_id = int(sql(f"INSERT INTO STUDY_PLAN_DETAILS(user_id,plan_id,subject_name,study_category,scheduled_date,estimated_minutes) "
                    f"VALUES({user_id},{plan_id},'{subject}','SAMPLE 자격증','{date}',60); SELECT LAST_INSERT_ID();"))
                ids.append(task_id)
            return ids
        app_tasks = seed_plan(login) if args.record_actions_checks or args.timer_checks else []
        for offset, minutes in [(-4, 20), (-2, 50), (-1, 30), (0, 60)]:
            status, _ = call('POST', '/study/sessions', {
                'studyDate': (today + timedelta(days=offset)).isoformat(),
                'durationMinutes': minutes}, token)
            assert status == 200
        defines = run / 'defines.json'
        defines.write_text(json.dumps({
            'STUDY_TEST_ORIGIN': f'http://10.0.2.2:{port}',
            'STUDY_TEST_ID': login, 'STUDY_TEST_PASSWORD': password,
            'STUDY_TEST_ISOLATED': True,
        }), encoding='utf-8')
        postman_environment = None
        if args.study_edit_checks:
            checks = []
            def check(name, passed):
                if not passed:
                    raise AssertionError(name)
                checks.append(name)
            check('patch-auto-discovered', 'patch' in spec['paths'].get('/study/sessions/{sessionId}', {}))
            api_login = 'api_verify_' + uuid.uuid4().hex[:8]
            api_password = secrets.token_urlsafe(18)
            status, _ = call('POST', '/auth/signup', {'loginId': api_login,
                'password': api_password, 'passwordConfirm': api_password,
                'nickname': 'SAMPLE API 수정 검증', 'email': api_login + '@example.invalid',
                'majorType': 'MAJOR'})
            check('isolated-api-account', status == 200)
            _, auth_api = call('POST', '/auth/login', {'loginId': api_login, 'password': api_password})
            api_token = auth_api['data']['accessToken']
            yesterday = (today - timedelta(days=1)).isoformat()
            status, saved = call('POST', '/study/sessions', {'studyDate': today.isoformat(),
                'durationMinutes': 17}, api_token)
            check('existing-post-still-works', status == 200)
            record_id = saved['data']['sessionId']
            route = '/study/sessions/' + str(record_id)
            body = {'studyDate': yesterday, 'durationMinutes': 23,
                'expectedStudyDate': today.isoformat(), 'expectedDurationMinutes': 17}
            status, updated = call('PATCH', route, body, api_token)
            check('real-patch-same-id-date-minutes', status == 200 and
                updated['data']['sessionId'] == record_id and updated['data']['studyDate'] == yesterday and
                updated['data']['durationMinutes'] == 23 and updated['data']['taskId'] is None)
            status, _ = call('PATCH', route, body, api_token)
            check('stale-edit-json-409', status == 409)
            status, _ = call('PATCH', route, body, token)
            check('foreign-record-json-403', status == 403)
            status, _ = call('PATCH', route, body)
            check('unauthenticated-json-401', status == 401)
            invalid = {**body, 'durationMinutes': 0, 'expectedStudyDate': yesterday,
                       'expectedDurationMinutes': 23}
            status, _ = call('PATCH', route, invalid, api_token)
            check('invalid-patch-json-400', status == 400)
            target = (today - timedelta(days=2)).isoformat()
            status, _ = call('POST', '/study/sessions', {'studyDate': target, 'durationMinutes': 1400}, api_token)
            check('isolated-cap-fixture', status == 200)
            status, _ = call('PATCH', route, {**body, 'studyDate': target, 'durationMinutes': 50,
                'expectedStudyDate': yesterday, 'expectedDurationMinutes': 23}, api_token)
            check('date-move-cap-409', status == 409)
            query = '?startDate=' + yesterday + '&endDate=' + today.isoformat()
            status, rows = call('GET', '/study/sessions' + query, token=api_token)
            check('failed-patches-preserve-one-updated-record', status == 200 and len(rows['data']['items']) == 1
                and rows['data']['items'][0]['sessionId'] == record_id and rows['data']['items'][0]['durationMinutes'] == 23)
            status, stats = call('GET', '/dashboard/study-stats' + query + '&period=CUSTOM', token=api_token)
            check('both-date-totals-reflect-edit', status == 200 and stats['data']['totalMinutes'] == 23 and
                [d['durationMinutes'] for d in stats['data']['dailyStudyMinutes']] == [23, 0])
            postman_environment = run / 'postman-environment.json'
            values = {'baseUrl': f'http://127.0.0.1:{port}', 'token': api_token,
                      'startDate': yesterday, 'endDate': today.isoformat(), 'expectedId': str(record_id),
                      'expectedDate': yesterday, 'expectedMinutes': '23', 'expectedTotal': '23'}
            if args.record_actions_checks:
                api_tasks = seed_plan(api_login)
                status, choices = call('GET', '/study/plan-tasks?date=' + today.isoformat(), token=api_token)
                check('real-owned-task-lookup', status == 200 and len(choices['data']['items']) == 1 and
                    choices['data']['items'][0]['taskId'] == api_tasks[0] and choices['data']['items'][0]['subjectId'] is None)
                check('other-users-tasks-hidden', all(v['taskId'] not in app_tasks for v in choices['data']['items']))
                linked = {'studyDate': yesterday, 'durationMinutes': 23, 'expectedStudyDate': yesterday,
                    'expectedDurationMinutes': 23, 'expectedTask': {'taskId': None},
                    'taskLink': {'taskId': api_tasks[0], 'expectedPlanVersion': 3, 'expectedTaskId': None}}
                status, response = call('PATCH', route, linked, api_token)
                check('existing-record-linked-with-null-subject-id', status == 200 and response['data']['taskId'] == api_tasks[0]
                    and response['data']['subjectName'] == 'SAMPLE 데이터베이스' and response['data']['subjectId'] is None)
                status, _ = call('PATCH', route, {**linked, 'expectedTask': {'taskId': api_tasks[0]},
                    'taskLink': {'taskId': app_tasks[0], 'expectedPlanVersion': 3, 'expectedTaskId': api_tasks[0]}}, api_token)
                check('foreign-task-relink-forbidden', status == 403)
                status, doomed = call('POST', '/study/sessions', {'studyDate': today.isoformat(), 'durationMinutes': 5}, api_token)
                check('disposable-delete-target-created', status == 200)
                deleted_id = doomed['data']['sessionId']
                status, removed = call('DELETE', '/study/sessions/' + str(deleted_id), {
                    'expectedStudyDate': today.isoformat(), 'expectedDurationMinutes': 5, 'expectedTaskId': None}, api_token)
                check('real-delete-confirmed', status == 200 and removed['data'] == {'sessionId': deleted_id, 'deleted': True})
                status, _ = call('DELETE', route, {'expectedStudyDate': yesterday,
                    'expectedDurationMinutes': 23, 'expectedTaskId': None}, api_token)
                check('stale-link-delete-rejected', status == 409)
                status, stats = call('GET', '/dashboard/study-stats' + query + '&period=CUSTOM', token=api_token)
                check('delete-statistics-recalculated', status == 200 and stats['data']['totalMinutes'] == 23)
                values.update({'deletedId': str(deleted_id), 'expectedTaskId': str(api_tasks[0]), 'planDate': today.isoformat()})
            postman_environment.write_text(json.dumps({'name': 'isolated-study-edit',
                'values': [{'key': k, 'value': v, 'enabled': True, 'type': 'secret' if k == 'token' else 'default'}
                           for k, v in values.items()]}), encoding='utf-8')
            api_token = api_password = None
            (args.control_file.parent / 'http-result.json').write_text(json.dumps({
                'mode': 'real HTTP original Spring Boot binary against disposable MariaDB',
                'checks': checks, 'productionWrites': False}, indent=2), encoding='utf-8')
        token = password = None
        args.control_file.write_text(json.dumps({
            'run': str(run), 'defines': str(defines), 'port': port,
            'stopFile': str(run / 'stop'), 'productionWrites': False,
            'postmanEnvironment': str(postman_environment) if postman_environment else None,
        }), encoding='utf-8')
        print('Private study API ready; only synthetic account and disposable DB.', flush=True)
        deadline = time.monotonic() + 2400
        while not (run / 'stop').exists() and time.monotonic() < deadline:
            if proc.poll() is not None or dbproc.poll() is not None:
                raise RuntimeError('Private fixture stopped unexpectedly')
            time.sleep(.5)
    finally:
        for child in (proc, dbproc):
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
        if log:
            log.close()
            logfile = run / 'server.log'
            text = logfile.read_text(encoding='utf-8', errors='replace')
            text = re.sub(r'(Using generated security password:)\s*[^\r\n]+',
                          r'\1 [REDACTED EPHEMERAL TEST VALUE]', text)
            logfile.write_text(text, encoding='utf-8')
        db_log.close()
        if (run / 'defines.json').exists():
            (run / 'defines.json').unlink()
        if (run / 'postman-environment.json').exists():
            (run / 'postman-environment.json').unlink()
        print('Private fixture stopped; temporary login material removed.', flush=True)


if __name__ == '__main__':
    main()
