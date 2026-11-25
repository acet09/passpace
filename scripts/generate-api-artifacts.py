"""Generate this Flutter client's team study API contract and read-only checks.

This intentionally does not edit the older React/cookie API contract in the
parent workspace. No dependencies, credentials, publishing or DB operations.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def integer(minimum=1, maximum=None, **extra):
    return {'type': 'integer', 'minimum': minimum,
            **({'maximum': maximum} if maximum is not None else {}), **extra}


def obj(properties, required):
    return {'type': 'object', 'properties': properties, 'required': required,
            'additionalProperties': False}


def ref(name):
    return {'$ref': '#/components/schemas/' + name}


def main():
    date = {'type': 'string', 'format': 'date', 'pattern': r'^\d{4}-\d{2}-\d{2}$'}
    minutes = integer(1, 1440)
    record = {'sessionId': integer(format='int64'), 'studyDate': date,
              'durationMinutes': minutes, **{k: integer(nullable=True, format='int64')
              for k in ('taskId', 'planId', 'subjectId')},
              'subjectName': {'type': 'string', 'nullable': True},
              'inputMethod': {'type': 'string', 'nullable': True}}
    schemas = {
        'SaveSession': obj({'studyDate': date, 'durationMinutes': minutes,
            **{k: integer(nullable=True, format='int64') for k in ('taskId','planId','subjectId')},
            'expectedPlanVersion': integer(nullable=True)}, ['studyDate', 'durationMinutes']),
        'UpdateSession': obj({'studyDate': date, 'durationMinutes': minutes,
            'expectedStudyDate': date, 'expectedDurationMinutes': minutes,
            'taskLink':ref('TaskLinkChange'),'expectedTask':ref('TaskLinkSnapshot')},
            ['studyDate','durationMinutes','expectedStudyDate','expectedDurationMinutes']),
        'TaskLinkChange':obj({'taskId':integer(nullable=True,format='int64'),
            'expectedTaskId':integer(nullable=True,format='int64'),
            'expectedPlanVersion':integer(nullable=True)},[]),
        'TaskLinkSnapshot':obj({'taskId':integer(nullable=True,format='int64')},[]),
        'DeleteSession':obj({'expectedStudyDate':date,'expectedDurationMinutes':minutes,
            'expectedTaskId':integer(nullable=True,format='int64')},['expectedStudyDate','expectedDurationMinutes']),
        'DeleteResult':obj({'sessionId':integer(format='int64'),'deleted':{'type':'boolean','enum':[True]}},['sessionId','deleted']),
        'PlanTaskChoice':obj({'taskId':integer(format='int64'),'planId':integer(format='int64'),
            'planName':{'type':'string','nullable':True},'planVersion':integer(),
            'subjectId':integer(nullable=True,format='int64'),'subjectName':{'type':'string','nullable':True},
            'certificationName':{'type':'string','nullable':True},'scheduledDate':{**date,'nullable':True},
            'planStatus':{'type':'string','enum':['ACTIVE','REPLACED']}},
            ['taskId','planId','planName','planVersion','subjectId','subjectName','certificationName','scheduledDate','planStatus']),
        'PlanTaskPage':obj({'items':{'type':'array','items':ref('PlanTaskChoice')},'page':integer(0,10000),
            'pageSize':integer(1,100),'hasNext':{'type':'boolean'}},['items','page','pageSize','hasNext']),
        'Session': obj(record, list(record)),
        'SessionPage': obj({'items': {'type':'array','items':ref('Session')},
            'page':integer(0,10000), 'pageSize':integer(1,100), 'hasNext':{'type':'boolean'}},
            ['items','page','pageSize','hasNext']),
        'StudyStats': obj({'period':{'type':'string','enum':['LAST_7_DAYS','LAST_30_DAYS','CUSTOM']},
            'startDate':date, 'endDate':date, 'timezone':{'type':'string','enum':['Asia/Seoul']},
            'totalMinutes':integer(0,1440*366),
            'dailyStudyMinutes':{'type':'array','minItems':1,'maxItems':366,'items':obj(
                {'studyDate':date,'durationMinutes':integer(0,1440)}, ['studyDate','durationMinutes'])},
            'completionRate':{'type':'number','nullable':True,'enum':[None]}},
            ['period','startDate','endDate','timezone','totalMinutes','dailyStudyMinutes','completionRate']),
    }
    def response(name):
        return {'description':'기존 SUCCESS JSON envelope', 'content':{'application/json':{'schema':
            obj({'status':{'type':'string','enum':['SUCCESS']},'code':{'type':'integer','enum':[200]},
                 'data':ref(name)}, ['status','code','data'])}}}
    def operation(summary, result, body=None, parameters=None):
        value={'summary':summary,'security':[{'BearerAuth':[]}], 'responses':{'200':response(result),
               **{str(code):{'description':description} for code,description in [
                   (400,'입력/기간/전공 누락'),(401,'JSON 인증 오류'),(403,'소유권/전공 불일치'),
                   (409,'오래된 값/같은 날짜 한도/경합/수정 불가 기록'),(503,'기존 기록 데이터 불량')]}}}
        if body:
            value['requestBody']={'required':True,'content':{'application/json':{'schema':ref(body)}}}
        if parameters:
            value['parameters']=parameters
        return value
    def query(name,schema,required=False):
        return {'in':'query','name':name,'required':required,'schema':schema}
    paths={
        '/study/sessions':{
            'post':operation('실제 공부시간 직접 기록','Session','SaveSession'),
            'get':operation('본인의 기간별 기록 조회','SessionPage',parameters=[query('startDate',date,True),
                query('endDate',date,True),query('page',{**integer(0,10000),'default':0}),
                query('pageSize',{**integer(1,100),'default':20})])},
        '/study/sessions/{sessionId}':{'patch':operation('직접 입력 기록의 날짜/시간/과목 연결 수정','Session','UpdateSession',
            [{'in':'path','name':'sessionId','required':True,'schema':integer(format='int64')}]),
            'delete':operation('본인 직접 입력 기록 삭제','DeleteResult','DeleteSession',
            [{'in':'path','name':'sessionId','required':True,'schema':integer(format='int64')}])},
        '/study/plan-tasks':{'get':operation('기록에 연결할 본인 학습계획 항목','PlanTaskPage',parameters=[
            query('date',date),query('includeReplaced',{'type':'boolean','default':False}),
            query('page',{**integer(0,10000),'default':0}),query('pageSize',{**integer(1,100),'default':50})])},
        '/dashboard/study-stats':{'get':operation('본인의 실제 공부시간 통계','StudyStats',parameters=[
            query('period',{'type':'string','enum':['LAST_7_DAYS','LAST_30_DAYS','CUSTOM'],'default':'LAST_7_DAYS'}),
            query('startDate',date),query('endDate',date)])},
    }
    spec={'openapi':'3.0.3','info':{'title':'PASS PACE team study API','version':'1.2.0'},
          'servers':[{'url':'http://127.0.0.1:8082'}], 'paths':paths,
          'components':{'securitySchemes':{'BearerAuth':{'type':'http','scheme':'bearer','bearerFormat':'JWT'}},
                        'schemas':schemas}}
    (ROOT/'docs/study-api.openapi.json').write_text(json.dumps(spec,ensure_ascii=False,indent=2),encoding='utf-8')
    markdown='''# 추가한 학습기록 API 목록 · 담당 한결

2026-11-16 기준. 이후 “추가한 API 목록”을 요청하면 이 파일과 실제 `com.passpace.study` 소스를 함께 확인한다.
프로필/이해도 등록은 이번에 새로 추가한 API가 아니다. 아래 기존4개 + 삭제/과목 조회2개, 총6개다.

| 시점 | 메서드/경로 | 역할 |
| --- | --- | --- |
| 앞서 추가 | POST `/study/sessions` | 실제 공부시간 직접 입력 저장 |
| 앞서 추가 | GET `/study/sessions` | 본인의 기간별 기록 조회 |
| 앞서 추가 | GET `/dashboard/study-stats` | 본인의 실제 공부시간 합계·일별 통계 |
| 앞서 추가·이번 확장 | PATCH `/study/sessions/{sessionId}` | 직접 입력 기록의 날짜·공부시간·과목 연결 수정 |
| 이번 추가 | DELETE `/study/sessions/{sessionId}` | 직접 입력 기록 삭제 |
| 이번 추가 | GET `/study/plan-tasks` | 기록에 연결할 본인 계획 항목·과목 조회 |

## 공통

- 기존 Bearer JWT 인증/전공 검증/본인 소유권 적용. 성공HTTP200 `{status:"SUCCESS",code:200,data:...}`. 오류도 기존 JSON 규칙, 인증 오류는401/403이다.
- 실제 정수 분1~1440, 같은 날짜 합계1440분 이하. 날짜 YYYY-MM-DD, 한국 시간(Asia/Seoul) 기준. 미래 날짜로 저장/수정할 수 없다.
- 요청의 사용자 ID를 받지 않는다. 로그인한 사용자만 사용하며 기존 계획·과목·인증·DB 구조·다른 팀원 파일은 수정하지 않는다.

## POST /study/sessions

필수 `studyDate`, `durationMinutes`. 미연결 수동 입력은 두 값만 보낸다.
계획 연결은 `taskId`와 `expectedPlanVersion`이 필요하며 `subjectId`/`planId`는 일치 확인용이다. 기존 계획 조회에 taskId가 없던 문제를 별도 학습기록 소유 조회인 GET /study/plan-tasks로 해결했다. 앱에서 해당 항목을 선택해 실제 ID와 계획 버전을 전송한다. subjectId가 null이어도 실제 taskId와 저장된 과목명으로 연결한다.
반복 POST는 별도 기록이다. 영속 중복 제거를 보장하지 않아 앱은 응답 유실 때 자동 재전송하지 않는다.

## GET /study/sessions

필수 `startDate`, `endDate`(양 끝 포함1~366일). `page`0~10000 기본0, `pageSize`1~100 기본20.
응답 `items`, `page`, `pageSize`, `hasNext`. 날짜DESC/기록IDDESC. 과목 없는 기록과 교체된 계획의 기록도 본인 기록이면 포함한다.

## GET /dashboard/study-stats

`period=LAST_7_DAYS`(기본), `LAST_30_DAYS`, `CUSTOM`. CUSTOM만 startDate/endDate 필수, 다른 기간과 날짜 동시 지정은400.
응답 `period`, `startDate`, `endDate`, `timezone:"Asia/Seoul"`, `totalMinutes`, `dailyStudyMinutes[{studyDate,durationMinutes}]`, `completionRate:null`.
일별 날짜ASC, 기록 없는 날짜0분. 계획 시간이 아닌 실제 분이며 완료율을 만들지 않는다.

## PATCH /study/sessions/{sessionId}

본인의 `inputMethod=MANUAL` 기록만 수정한다. 다음 네 필드는 필수이며 아래 선택 항목 `expectedTask`, `taskLink` 외의 알 수 없는 필드는400이다.

```json
{
  "studyDate": "2026-11-13",
  "durationMinutes": 45,
  "expectedStudyDate": "2026-11-14",
  "expectedDurationMinutes": 30
}
```

- expected 두 값은 수정 화면을 열었을 때 조회한 원래 값이다. DB의 현재 값과 다르면409이며 목록을 새로 조회한 뒤 다시 수정한다.
- 사용자 행/기록 행 잠금과 기존 값 비교로 저장/수정을 직렬화한다. 같은 날짜 수정은 자기 원래 분을 제외하고 한도를 검사한다. 새 날짜 이동도 대상 날짜 한도를 검사한다.
- `expectedTask:{taskId:기존ID또는null}`을 새 앱에서 함께 보내 연결만 바뀐 경합도 확인한다. 구형 요청에서 생략하면 기존4필드 요청을 계속 허용한다.
- `taskLink` 생략 시 기존 연결 유지. 지정하면 `{taskId:새ID또는null,expectedPlanVersion:새계획버전또는null,expectedTaskId:기존ID또는null}`로 연결/해제한다. 양수 새ID는 본인 계획/버전을 검증한다. null 새ID는 연결 해제이며 버전도null이어야 한다. null/생략 expectedTaskId는 미연결을 의미해 이미 연결된 기록에서는409다.
- 기존 ID, 입력 방식, 시작/종료 시간, 이해도는 유지한다. 과목/계획 연결은 명시적으로 변경할 때만 갱신하며 계획 승인/재계산/완료 상태를 바꾸지 않는다.
- 반환은 기존 Session 응답과 동일하다. 본인 소유 아님/없음403, 입력400, 오래된 값/한도/경합/TIMER 등 수동 아닌 기록409, 불량 기존 연결/시간503.
- DB version 컬럼을 추가하지 않은 값 비교 방식이다. A→B→A 전체 이력 감지와 감사 로그, 영속 idempotency는 보장하지 않는다. 앱은 불확실한 PATCH를 자동 재전송하지 않는다.

## DELETE /study/sessions/{sessionId}

본인의 직접 입력 기록만 삭제한다. 본문 필수 `expectedStudyDate`, `expectedDurationMinutes`와 기존 `expectedTaskId`(미연결null)를 확인한다. 저장된 날짜/분/연결과 다르면409다.200 data는 `{sessionId,deleted:true}`다.
사용자·기록 행을 잠그고 해당 STUDY_SESSIONS 한 행만 삭제한다. 계획/과목/다른 기록은 유지하며 통계는 남은 실제 기록을 집계한다. 다른 사용자/없음403, 입력400, 자동 기록/오래된 값409, 불량 기존 기록503. 반복 DELETE도 미발견403이며 자동 재전송하지 않는다. 앱에서 복구 불가 확인 후 요청한다.

## GET /study/plan-tasks

선택 `date`(YYYY-MM-DD, 생략하면 전체 일정), `includeReplaced` 기본false, `page`0~10000, `pageSize`1~100 기본50.
본인의 ACTIVE 계획만 기본 조회하며 옵션으로 REPLACED도 포함한다. 다른 사용자·DRAFT·정상 버전이 없는 계획은 선택 대상에서 제외한다.
data `{items,page,pageSize,hasNext}`. 항목 `taskId,planId,planName,planVersion,subjectId?,subjectName?,certificationName?,scheduledDate?,planStatus`.
실제 DB 식별자만 전달한다. 배정 시간을 실제 공부시간에 자동 입력하지 않는다. 학습계획이 없으면 빈 목록이며 연결 없이도 기록할 수 있다.

## Session 응답 필드

`sessionId`, `studyDate`, `durationMinutes`, `taskId?`, `planId?`, `subjectId?`, `subjectName?`, `inputMethod?`.
null인 과목/계획 식별자를 앱에서 만들지 않는다.

## 실제 백엔드 파일 · 기존6개만

`C:/Users/std66/passpace11144/src/main/java/com/passpace/study/`

- `StudyController.java`: HTTP 요청·인증 주체 전달
- `StudyService.java`: 업무 인터페이스
- `StudyServiceImpl.java`: 소유권·입력·동시성·같은 날짜 한도/집계
- `StudyRepository.java`: 저장소 인터페이스
- `JdbcStudyRepository.java`: 본인 조건 SQL·행 잠금·기록 저장/수정/조회
- `StudyDtos.java`: 요청/응답과 엄격한 날짜·정수 역직렬화

기존4개 API 요청을 하위 호환하며 응답 형식은 유지한다. 타이머/완료율/새 테이블은 추가하지 않았다.
기계 판독 계약은 `docs/study-api.openapi.json`, 재생성은 앱 폴더에서 `python scripts/generate-api-artifacts.py`.
`postman/study-records-readonly.postman_collection.json`은 격리 검증 환경의 수정 결과를 읽어 검증하는 컬렉션이며 쓰기 요청은 없다. 비밀번호/토큰은 저장하지 않는다.
'''
    (ROOT/'docs/api-contract.md').write_text(markdown,encoding='utf-8')
    def item(name,path,script):
        return {'name':name,'request':{'method':'GET','url':'{{baseUrl}}'+path,
                'header':[{'key':'Accept','value':'application/json'}]},
                'event':[{'listen':'test','script':{'type':'text/javascript','exec':script.splitlines()}}]}
    collection={'info':{'name':'PASS PACE study read-only verification',
                'schema':'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'},
                'auth':{'type':'bearer','bearer':[{'key':'token','value':'{{token}}','type':'string'}]},
                'item':[
                    item('수정된 본인 기록 조회','/study/sessions?startDate={{startDate}}&endDate={{endDate}}&pageSize=100',
'''pm.test('HTTP 200',()=>pm.response.to.have.status(200));
const d=pm.response.json();
pm.test('SUCCESS envelope',()=>pm.expect(d.status).to.eql('SUCCESS'));
pm.test('updated record',()=>{const r=d.data.items.find(x=>x.sessionId===Number(pm.environment.get('expectedId')));pm.expect(r.studyDate).to.eql(pm.environment.get('expectedDate'));pm.expect(r.durationMinutes).to.eql(Number(pm.environment.get('expectedMinutes')));});'''),
                    item('수정 후 실제 시간 통계','/dashboard/study-stats?period=CUSTOM&startDate={{startDate}}&endDate={{endDate}}',
'''pm.test('HTTP 200',()=>pm.response.to.have.status(200));
const d=pm.response.json().data;
pm.test('actual total',()=>pm.expect(d.totalMinutes).to.eql(Number(pm.environment.get('expectedTotal'))));
pm.test('Seoul date',()=>{pm.expect(d.timezone).to.eql('Asia/Seoul');pm.expect(d.startDate).to.eql(pm.environment.get('startDate'));pm.expect(d.endDate).to.eql(pm.environment.get('endDate'));});
pm.test('daily minutes',()=>pm.expect(d.dailyStudyMinutes.find(x=>x.studyDate===pm.environment.get('expectedDate')).durationMinutes).to.eql(Number(pm.environment.get('expectedMinutes'))));
pm.test('no invented completion',()=>pm.expect(d.completionRate).to.eql(null));''')],
                'variable':[{'key':'baseUrl','value':''},{'key':'token','value':''}]}
    (ROOT/'postman').mkdir(exist_ok=True)
    (ROOT/'postman/study-records-readonly.postman_collection.json').write_text(
        json.dumps(collection,ensure_ascii=False,indent=2),encoding='utf-8')
    actions=json.loads(json.dumps(collection))
    actions['info']['name']='PASS PACE delete and task link read-only verification'
    actions['item'][0]['event'][0]['script']['exec'] += [
        "pm.test('deleted ID absent',()=>pm.expect(pm.response.json().data.items.some(x=>x.sessionId===Number(pm.environment.get('deletedId')))).to.eql(false));",
        "pm.test('linked task preserved',()=>pm.expect(pm.response.json().data.items.find(x=>x.sessionId===Number(pm.environment.get('expectedId'))).taskId).to.eql(Number(pm.environment.get('expectedTaskId'))));",
    ]
    actions['item'].append(item('본인 과목 선택 목록','/study/plan-tasks?date={{planDate}}',
        "pm.test('HTTP 200',()=>pm.response.to.have.status(200));\npm.test('real task and version',()=>{const t=pm.response.json().data.items.find(x=>x.taskId===Number(pm.environment.get('expectedTaskId')));pm.expect(t.planVersion).to.eql(3);pm.expect(t.subjectId).to.eql(null);});"))
    (ROOT/'postman/study-actions-readonly.postman_collection.json').write_text(
        json.dumps(actions,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Generated six-operation contract, API memory list, and read-only Postman checks.')


if __name__ == '__main__':
    main()
