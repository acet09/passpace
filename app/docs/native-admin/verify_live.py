"""Run the mobile admin scenario against an isolated copy of the existing runtime.

Reads compiled team classes/resources and SQL without building or changing them.
Only the newly created database process and its private working directory are writable.
No credentials, tokens, HTTP bodies or server logs are printed.
"""
from pathlib import Path
import base64
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

APP = Path(__file__).resolve().parents[2]
TEAM = Path('C:/Users/std66/passpace11144')
BIN = Path('C:/Program Files/MariaDB 12.2/bin')
FLUTTER = 'C:/Users/std66/Documents/flutter_windows_3.47.2-stable/flutter/bin/flutter.bat'
PS = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
DB_PORT, API_PORT = 3325, 18085
OUT = APP / 'docs/native-admin'


def free_port(port):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', port))


def request(path, data=None):
    body = None if data is None else json.dumps(data).encode('utf-8')
    req = urllib.request.Request(f'http://127.0.0.1:{API_PORT}{path}', data=body,
                                 headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=5) as res:
            return res.status, json.load(res)
    except urllib.error.HTTPError as error:
        return error.code, None


def sql(text):
    result = subprocess.run([str(BIN/'mariadb.exe'), '--no-defaults', '--protocol=tcp',
                             '-h127.0.0.1', f'-P{DB_PORT}', '-uroot', '--default-character-set=utf8mb4'],
                            input=text.encode('utf-8'), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError('isolated SQL operation failed')


def main():
    free_port(DB_PORT); free_port(API_PORT)
    work = (APP/'.runtime'/f'native-admin-{uuid.uuid4().hex}').resolve()
    if work.parent != (APP/'.runtime').resolve():
        raise RuntimeError('invalid isolated directory')
    work.mkdir(parents=True)
    processes, logs = [], []
    result = {'isolatedDatabase': True, 'teamSourceModified': False}
    stage, exit_code = 'initialization', 1
    try:
        stage = 'database initialization'
        init = subprocess.run([str(BIN/'mariadb-install-db.exe'), f'--datadir={work/"db"}', f'--port={DB_PORT}'],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
        if init.returncode: raise RuntimeError('isolated database initialization failed')
        db_log = open(work/'db.log', 'wb'); logs.append(db_log)
        db = subprocess.Popen([str(BIN/'mariadbd.exe'), '--no-defaults', f'--datadir={work/"db"}',
                               f'--port={DB_PORT}', '--bind-address=127.0.0.1', '--console'],
                              cwd=work, stdout=db_log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        processes.append(db)
        for _ in range(60):
            try: sql('SELECT 1;'); break
            except RuntimeError: time.sleep(.5)
        else: raise RuntimeError('isolated database unavailable')
        stage = 'isolated schema import'
        for name in ['01_schema.sql','02_schema_ext.sql','03_seed.sql','08_add_user_role.sql','09_review_sources.sql']:
            prefix = '' if name == '01_schema.sql' else 'USE passpace_merged;\n'
            sql(prefix + (TEAM/'db'/name).read_text(encoding='utf-8'))
        sql("USE passpace_merged; INSERT INTO PASS_REVIEWS (source_id,certification_id,exam_type,major_type,source_url,posted_at,proof_yn,prep_days,total_hours,daily_hours,study_subjects,evidence_text,review_status,pass_yn,daily_minutes) VALUES "
            + ','.join(f"({3 if 'velog.io' in url else 7},1,'WRITTEN','NON_MAJOR','{url}','2026-11-15','Y',30,45,'1.5','소프트웨어 설계','SAMPLE 앱 내부 관리자 검증','VALID','Y',90)" for url in [
                'https://velog.io/@sample/native-admin-a','https://velog.io/@sample/native-admin-b','https://passpace-sample.tistory.com/1']) + ';')
        stage = 'existing runtime lookup'
        command = r'''$taskPid=(Get-NetTCPConnection -LocalPort 8080 -State Listen | Select-Object -First 1).OwningProcess;
$taskProcess=Get-CimInstance Win32_Process -Filter "ProcessId=$taskPid";
$taskMatch=[regex]::Match($taskProcess.CommandLine,'(?:-classpath|-cp)\s+(?:"(?<cp>[^"]+)"|(?<cp>\S+))');
@{exe=$taskProcess.ExecutablePath; cp=$taskMatch.Groups['cp'].Value} | ConvertTo-Json -Compress'''
        info = json.loads(subprocess.run([PS,'-NoProfile','-Command',command], capture_output=True, check=True, encoding='utf-8').stdout)
        if not info['cp'] or not info['exe']: raise RuntimeError('existing compiled runtime unavailable')
        stage = 'isolated Spring Boot startup'
        env = dict(os.environ, JWT_SECRET=base64.b64encode(secrets.token_bytes(48)).decode())
        server_log = open(work/'server.log','wb'); logs.append(server_log)
        server = subprocess.Popen([info['exe'],'-cp',info['cp'],'com.passpace.PasspaceApplication',
            f'--server.port={API_PORT}','--server.address=127.0.0.1',
            '--spring.config.import=optional:classpath:native-admin-test-not-found.yml',
            f'--spring.datasource.url=jdbc:mariadb://127.0.0.1:{DB_PORT}/passpace_merged',
            '--spring.datasource.username=root','--spring.datasource.password=',
            f'--passpace.collect.data-dir={work/"collect-data"}',
            '--passpace.collect.data-go-kr-key=', '--passpace.collect.naver.client-id=', '--passpace.collect.naver.client-secret=',
            '--passpace.collect.tistory-search-enabled=false', f'--logging.file.name={work/"spring.log"}'],
            env=env,cwd=work,stdout=server_log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        processes.append(server)
        for _ in range(90):
            if server.poll() is not None: raise RuntimeError('isolated server exited')
            try:
                if request('/auth/user-info')[0] == 401: break
            except (OSError,ValueError): pass
            time.sleep(.5)
        else: raise RuntimeError('isolated server unavailable')
        stage = 'isolated test accounts'
        suffix = uuid.uuid4().hex[:6]
        admin_id, user_id = f'appadmin_{suffix}', f'appuser_{suffix}'
        password = secrets.token_urlsafe(18)
        for login_id in [admin_id,user_id]:
            status,_ = request('/auth/signup',{'loginId':login_id,'password':password,'passwordConfirm':password,
                'nickname':'SAMPLE 앱 관리자 검증','email':f'{login_id}@example.invalid','majorType':'NON_MAJOR'})
            if status != 200: raise RuntimeError('isolated signup failed')
        sql(f"USE passpace_merged; UPDATE USERS SET role='ADMIN' WHERE login_id='{admin_id}';")
        defines = work/'defines.json'
        defines.write_text(json.dumps({'ADMIN_TEST_ORIGIN':f'http://10.0.2.2:{API_PORT}',
            'ADMIN_TEST_ID':admin_id,'ADMIN_TEST_USER':user_id,'ADMIN_TEST_PASSWORD':password}),encoding='utf-8')
        stage = 'Android live integration'
        print('Isolated database and unchanged Spring Boot runtime ready.',flush=True)
        with open(OUT/'live-android-run.txt','wb') as output:
            test = subprocess.run([FLUTTER,'drive','--driver=test_driver/native_admin_driver.dart',
                '--target=integration_test/admin_live_test.dart','-d','emulator-5554',
                '--no-pub',f'--dart-define-from-file={defines}'],cwd=APP,stdout=output,stderr=subprocess.STDOUT)
        result['androidScenarioExitCode'] = test.returncode
        exit_code = test.returncode
    except Exception as error:
        result['failedStage'],result['errorType'] = stage,type(error).__name__
        print(f'Verification failed at {stage} ({type(error).__name__}).',flush=True)
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=15)
                except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=10)
        for log in logs: log.close()
        result['ownedProcessesStopped'] = all(p.poll() is not None for p in processes)
        # Only this newly created directory may be removed; never the shared DB or workspace.
        resolved = work.resolve()
        if resolved.parent == (APP/'.runtime').resolve() and resolved.name.startswith('native-admin-'):
            for _ in range(10):
                try: shutil.rmtree(resolved); break
                except PermissionError: time.sleep(.5)
        result['privateRuntimeRemoved'] = not work.exists()
        (OUT/'live-result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True)
    return exit_code

if __name__ == '__main__':
    sys.exit(main())
