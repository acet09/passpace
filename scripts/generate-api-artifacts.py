"""Generate the local withdrawal extension contract; no credentials or network I/O."""
from pathlib import Path
import json

root=Path(__file__).resolve().parents[1]
request={'type':'object','additionalProperties':False,'required':['password','confirmation','deletePersonalData'],'properties':{
    'password':{'type':'string','writeOnly':True,'description':'현재 비밀번호. 최대72 UTF-8바이트. 로그/예시에 값을 남기지 않는다.'},
    'confirmation':{'type':'string','description':'정확히 현재 로그인아이디 뒤에 회원탈퇴를 붙인 문구'},
    'deletePersonalData':{'type':'boolean','enum':[True],'description':'계정과 본인 자료 영구 삭제 확인. 구 앱의 누락 요청은 거부한다.'}}}
success={'type':'object','required':['status','code','data'],'properties':{
    'status':{'type':'string','enum':['SUCCESS']},'code':{'type':'integer','enum':[200]},
    'data':{'type':'object','required':['withdrawn','personalDataDeleted'],'properties':{
        'withdrawn':{'type':'boolean','enum':[True]},'personalDataDeleted':{'type':'boolean','enum':[True]}}}}}
operation={'tags':['회원탈퇴'],'summary':'본인 회원탈퇴 및 자료 영구 삭제','description':'명시적 동의 후 계정·본인 목표/계획/기록/대화/AI제안을 실제 삭제한다. 실패 시 전체 rollback, 타회원·공용 자료 유지.',
    'security':[{'bearerAuth':[]}], 'requestBody':{'required':True,'content':{'application/json':{'schema':request}}},
    'responses':{'200':{'description':'탈퇴 완료','content':{'application/json':{'schema':success}}}}}
for code,text in {'400':'입력/비밀번호/확인 문구 오류','401':'인증/계정 식별 오류','403':'전공 구분 변경','409':'변경 경합','503':'DB 처리 실패'}.items():
    operation['responses'][code]={'description':text}
spec={'openapi':'3.0.3','info':{'title':'PASS PACE 회원탈퇴 확장 API','version':'2026-11-18-plain-confirmation'},
    'paths':{'/users/me':{'delete':operation}},
    'components':{'securitySchemes':{'bearerAuth':{'type':'http','scheme':'bearer','bearerFormat':'JWT'}}}}
collection={'info':{'name':'PASS PACE SAMPLE 회원탈퇴 검증','description':'confirmation 예시: SAMPLE_MEMBER회원탈퇴. 괄호 없이 입력합니다.','schema':'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'},
    'variable':[{'key':'baseUrl','value':'http://127.0.0.1:0'}],
    'item':[
        {'name':'SAMPLE account withdrawal','request':{'method':'DELETE','header':[
            {'key':'Authorization','value':'Bearer {{accessToken}}'},{'key':'Content-Type','value':'application/json'}],
            'url':'{{baseUrl}}/users/me','body':{'mode':'raw','raw':'{\n  "password": "{{withdrawalPassword}}",\n  "confirmation": "{{withdrawalConfirmation}}",\n  "deletePersonalData": true\n}'}},
            'event':[{'listen':'test','script':{'type':'text/javascript','exec':[
                'pm.test("withdrawal200",()=>pm.response.to.have.status(200));',
                'const data=pm.response.json();',
                'pm.test("existing envelope",()=>{pm.expect(data.status).to.eql("SUCCESS");pm.expect(data.code).to.eql(200);});',
                'pm.test("confirmed withdrawal",()=>pm.expect(data.data.withdrawn).to.eql(true));',
                'pm.test("personal data deleted",()=>pm.expect(data.data.personalDataDeleted).to.eql(true));']}}]},
        {'name':'Old token cannot read profile','request':{'method':'GET','header':[{'key':'Authorization','value':'Bearer {{accessToken}}'}],
            'url':'{{baseUrl}}/auth/user-info'},'event':[{'listen':'test','script':{'type':'text/javascript','exec':[
                'pm.test("old token rejected",()=>pm.response.to.have.status(401));',
                'pm.test("JSON error without redirect",()=>{pm.expect(pm.response.json().status).to.eql("ERROR");pm.expect(pm.response.headers.has("Location")).to.eql(false);});']}}]}
    ]}
root_path = '/api/chat/planner/review-based/plans/{planId}'
date = {'type':'string','format':'date'}
minutes = {'type':'integer','minimum':1,'maximum':960}
identity = {'type':'integer','format':'int64','minimum':1}
version = {'type':'integer','minimum':1}

def patch_operation(summary, paths, fields, required, response, **schema_rules):
    return {
        'summary':summary,
        'security':[{'bearerAuth':[]}],
        'parameters':[
            {'name':name,'in':'path','required':True,'schema':identity} for name in paths
        ],
        'requestBody':{'required':True,'content':{'application/json':{'schema':{
            'type':'object','additionalProperties':False,'properties':fields,
            'required':required, **schema_rules,
        }}}},
        'responses':{
            '200':{'description':'계획 수정 완료','content':{'application/json':{'schema':{
                'type':'object','required':['status','code','data'],'properties':{
                    'status':{'type':'string','enum':['SUCCESS']},
                    'code':{'type':'integer','enum':[200]},
                    'data':{'type':'object','required':list(response),'properties':response},
                }
            }}}},
            '400':{'description':'입력 값 또는 일정 범위 오류'},
            '401':{'description':'인증 필요'},
            '403':{'description':'세션의 전공 정보가 변경됨'},
            '404':{'description':'본인의 계획이나 과목을 찾을 수 없음'},
            '409':{'description':'계획 충돌 또는 보호된 일정'},
        }
    }

spec['info'] = {'title':'PASS PACE 1122jhg 확장 API','version':'2026-11-22'}
spec['paths'][root_path+'/tasks/{taskId}'] = {'patch':patch_operation(
    '저장된 계획의 학습 날짜 또는 배정시간 수정', ['planId','taskId'],
    {'expectedPlanVersion':version,'scheduledDate':date,'estimatedMinutes':minutes},
    ['expectedPlanVersion'],
    {'planId':identity,'taskId':identity,'planVersion':version,'scheduledDate':date,'estimatedMinutes':minutes},
    anyOf=[{'required':['scheduledDate']},{'required':['estimatedMinutes']}],
)}
spec['paths'][root_path+'/period'] = {'patch':patch_operation(
    '저장된 계획의 시작일과 종료일 수정', ['planId'],
    {'expectedPlanVersion':version,'startDate':date,'endDate':date},
    ['expectedPlanVersion','startDate','endDate'],
    {'planId':identity,'planVersion':version,'startDate':date,'endDate':date},
)}

schedule_fields = {
    'expectedPlanVersion': version, 'startDate': date, 'endDate': date,
    'weekdayMinutes': {'type':'object', 'minProperties':1, 'maxProperties':7, 'additionalProperties':minutes},
    'subjects': {'type':'array','items':{'type':'object','required':['key','minutes'],'properties':{
        'key':identity, 'minutes':{'type':'integer','minimum':0,'maximum':519360},
    }}},
}
allocation = {'type':'array','items':{'type':'object','properties':{
    'date':date, 'exam':{'type':'string','nullable':True},
    'subject':{'type':'string'}, 'minutes':minutes,
}}}
approval = {'type':'string','pattern':'^[0-9a-f]{64}$'}
protected = {'type':'integer','minimum':0}
edit_response = {'planId':identity,'planVersion':version,'startDate':date,'endDate':date}
editor = patch_operation('전체 수정 입력 조회', ['planId'], {}, [], {
    **edit_response, 'planName':{'type':'string','nullable':True}, 'today':date,
    'weekdayMinutes':{'type':'object','maxProperties':7,'additionalProperties':minutes},
    'subjects':{'type':'array','items':{'type':'object','properties':{
        'key':identity,'exam':{'type':'string','nullable':True},'name':{'type':'string'},
        'minutes':{'type':'integer','minimum':0},
    }}}, 'protectedTasks':protected,
})
del editor['requestBody']
spec['paths'][root_path+'/schedule'] = {
    'get':editor,
    'patch':patch_operation('확인한 변경을 같은 계획에 저장', ['planId'],
        {**schedule_fields,'approval':approval}, [*schedule_fields,'approval'], edit_response),
}
spec['paths'][root_path+'/schedule/preview'] = {'post':patch_operation(
    '전체 수정 미리보기', ['planId'], schedule_fields, list(schedule_fields),
    {'approval':approval, 'changed':{'type':'boolean'}, 'protectedTasks':protected,
     'removed':allocation, 'added':allocation},
)}

collection['info']['name'] = 'PASS PACE 1122jhg SAMPLE 계획·계정 검증'
collection['info']['description'] = '격리된 SAMPLE 계정과 DB에서만 실행합니다. 회원탈퇴는 마지막에 수행됩니다.'
edit_checks = []
for label, suffix, body, field, variable in [
    ('오늘 항목 날짜 이동', '/tasks/{{taskId}}',
        {'expectedPlanVersion':'{{planVersion}}','scheduledDate':'{{destinationDate}}'},
        'scheduledDate','destinationDate'),
    ('항목 배정시간 수정', '/tasks/{{taskId}}',
        {'expectedPlanVersion':'{{planVersion}}','estimatedMinutes':'{{scheduledMinutes}}'},
        'estimatedMinutes','scheduledMinutes'),
    ('계획 기간 수정', '/period',
        {'expectedPlanVersion':'{{planVersion}}','startDate':'{{planStartDate}}','endDate':'{{planEndDate}}'},
        'endDate','planEndDate'),
]:
    raw = json.dumps(body, ensure_ascii=False, indent=2)
    for key in ('planVersion','scheduledMinutes'):
        raw = raw.replace('"{{'+key+'}}"','{{'+key+'}}')
    edit_checks.append({
        'name':label, 'request':{'method':'PATCH','header':[
            {'key':'Authorization','value':'Bearer {{accessToken}}'},
            {'key':'Content-Type','value':'application/json'},
        ],'url':'{{baseUrl}}/api/chat/planner/review-based/plans/{{planId}}'+suffix,
            'body':{'mode':'raw','raw':raw}},
        'event':[{'listen':'test','script':{'type':'text/javascript','exec':[
            'pm.test("plan write succeeds", () => pm.response.to.have.status(200));',
            'const data = pm.response.json().data;',
            f'pm.test("updated value", () => pm.expect(String(data.{field})).to.eql(String(pm.variables.get("{variable}"))));',
            'if (pm.response.code === 200) pm.environment.set("planVersion", data.planVersion);',
        ]}}],
    })
collection['item'] = edit_checks + collection['item']

whole_plan_base = '{{baseUrl}}/api/chat/planner/review-based/plans/{{planId}}/schedule'
whole_plan_headers = [
    {'key':'Authorization','value':'Bearer {{accessToken}}'},
    {'key':'Content-Type','value':'application/json'},
]
whole_plan_checks = [
    {'name':'SAMPLE 전체 수정 입력 조회', 'request':{
        'method':'GET','header':whole_plan_headers,'url':whole_plan_base},
     'event':[{'listen':'test','script':{'type':'text/javascript','exec':[
         'pm.test("editor read", () => pm.response.to.have.status(200));',
         'pm.collectionVariables.set("wholePlanVersion", pm.response.json().data.planVersion);',
     ]}}]},
    {'name':'SAMPLE 전체 수정 미리보기', 'request':{
        'method':'POST','header':whole_plan_headers,'url':whole_plan_base+'/preview',
        'body':{'mode':'raw','raw':'{{wholePlanPreviewBody}}'}},
     'event':[
         {'listen':'prerequest','script':{'type':'text/javascript','exec':[
             'const edit = JSON.parse(pm.environment.get("wholePlanRequest"));',
             'edit.expectedPlanVersion = Number(pm.collectionVariables.get("wholePlanVersion"));',
             'pm.collectionVariables.set("wholePlanPreviewBody", JSON.stringify(edit));',
         ]}},
         {'listen':'test','script':{'type':'text/javascript','exec':[
             'pm.test("preview with changes", () => { pm.response.to.have.status(200); pm.expect(pm.response.json().data.changed).to.be.true; });',
             'const edit = JSON.parse(pm.collectionVariables.get("wholePlanPreviewBody"));',
             'edit.approval = pm.response.json().data.approval;',
             'pm.collectionVariables.set("wholePlanApprovedBody", JSON.stringify(edit));',
         ]}},
     ]},
    {'name':'SAMPLE 같은 계획에 전체 수정 저장', 'request':{
        'method':'PATCH','header':whole_plan_headers,'url':whole_plan_base,
        'body':{'mode':'raw','raw':'{{wholePlanApprovedBody}}'}},
     'event':[{'listen':'test','script':{'type':'text/javascript','exec':[
         'pm.test("same plan and next version", () => { pm.response.to.have.status(200);',
         'const data = pm.response.json().data;',
         'pm.expect(String(data.planId)).to.eql(String(pm.variables.get("planId")));',
         'pm.expect(data.planVersion).to.eql(Number(pm.collectionVariables.get("wholePlanVersion")) + 1); });',
     ]}}]},
]
whole_plan_collection = {
    'info': {**collection['info'], 'name':'PASS PACE SAMPLE 전체 학습계획 수정',
             'description':'격리된 SAMPLE DB용. accessToken, planId, baseUrl, wholePlanRequest JSON을 설정한다.'},
    'variable': collection['variable'],
    'item': whole_plan_checks,
}

for relative,data in [
    ('docs/1122jhg.openapi.json',spec),
    ('postman/collections/integration/1122jhg-sample.postman_collection.json',collection),
    ('postman/collections/whole-plan/1122jhg-whole-plan.postman_collection.json',whole_plan_collection),
]:
    path=root/relative;path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert spec['paths']['/users/me']['delete']['requestBody']['content']['application/json']['schema']['required']==['password','confirmation','deletePersonalData']
print('Generated 1122jhg OpenAPI and SAMPLE collection')
