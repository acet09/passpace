/* [동건] 학습 상담 위젯. 응답은 textContent로만 출력한다(XSS 방지).
 * [JWT] 서버 호출은 모두 PP.api(...) (static/js/auth.js) 로 한다.
 *   - Authorization: Bearer 토큰 헤더를 자동으로 붙인다 (예전: 세션 쿠키)
 *   - 서버 응답 {status, code, data} 에서 data 만 꺼내 준다. 실패면 err.message 에 한국어 문장, err.status 에 HTTP 코드
 */
(function () {
    const root = document.getElementById('pp-chat-root');
    if (!root || root.dataset.ready) return;
    root.dataset.ready = 'true';

    let conId = null;
    const panel = root.querySelector('#pp-chat-panel');
    const toggle = root.querySelector('#pp-chat-toggle');
    const close = root.querySelector('#pp-chat-close');
    const log = root.querySelector('#pp-chat-log');
    const form = root.querySelector('#pp-chat-form');
    const input = root.querySelector('#pp-chat-input');
    const send = root.querySelector('#pp-chat-send');
    if (!panel || !toggle || !close) return;

    function setOpen(open) {
        panel.hidden = !open;
        toggle.setAttribute('aria-expanded', String(open));
        toggle.setAttribute('aria-label', open ? '학습 상담 챗봇 닫기' : '학습 상담 챗봇 열기');
        if (open && input) input.focus();
        else if (!open) toggle.focus();
    }
    toggle.addEventListener('click', () => setOpen(panel.hidden));
    close.addEventListener('click', () => setOpen(false));
    if (!form || !input || !log || !send) return; // 비로그인: 창 열기·닫기만
    const multiGoalPlanner = initializeMultiGoalPlanner(root);

    input.addEventListener('keydown', function (event) {
        if (event.key !== 'Enter' || event.shiftKey || event.isComposing || event.keyCode === 229) return;
        event.preventDefault();
        form.requestSubmit();
    });
    form.addEventListener('submit', async function (event) {
        event.preventDefault();
        if (send.disabled) return;
        const message = input.value.trim();
        if (!message) return;
        if (message.length > 500) {
            addMessage('질문은 500자 이내로 입력해 주세요.', 'pp-chat-error');
            return;
        }
        addMessage(message, 'pp-chat-user');
        input.value = '';
        setBusy(true);
        const waiting = addMessage('답변 작성 중입니다. 잠시만 기다려 주세요…', 'pp-chat-waiting');
        let sessionExpired = false;   // 토큰 만료(401) 여부
        try {
            let data;
            try {
                data = await PP.api('/api/chat', {method: 'POST', body: {message, conId}});
            } catch (err) {
                if (err.status !== 401) throw err;
                // 토큰 없음·만료 → 다시 로그인 안내 (돌아올 주소로 지금 화면을 붙인다)
                sessionExpired = true;
                addMessage(err.message || '로그인이 만료됐습니다. 다시 로그인해 주세요.', 'pp-chat-error');
                input.disabled = true;
                send.disabled = true;
                const link = document.createElement('a');
                link.className = 'pp-chat-login-link';
                link.href = '/login?redirectURL=' + encodeURIComponent(location.pathname + location.search);
                link.textContent = '다시 로그인';
                log.appendChild(link);
                return;
            }
            if (!data || typeof data.answer !== 'string') throw new Error('잘못된 챗봇 응답입니다.');
            if (typeof data.conId === 'number') conId = data.conId;
            renderAnswer(data);
            if (data.notice === 'AUTO_PLAN_SETUP' && multiGoalPlanner) {
                await multiGoalPlanner.startChatPlan(message, addMessage,
                    () => conId);
            }
        } catch (error) {
            addMessage(error.message || '요청 중 오류가 발생했습니다.', 'pp-chat-error');
        } finally {
            waiting.remove();
            if (!sessionExpired) setBusy(false);
            else {
                input.disabled = true;
                send.disabled = true;
                send.textContent = '로그인 필요';
            }
        }
    });

    function renderAnswer(data) {
        const item = addMessage(data.answer, 'pp-chat-bot');
        const lines = [];
        if (data.statsAvailable) {
            lines.push(`합격 후기 표본 ${data.sampleSize}건`);
            if (data.statsCondition) lines.push(`비교 조건: ${data.statsCondition}`);
        } else if (data.statsCondition) {
            lines.push('통계 미사용');
            lines.push(`조회 조건: ${data.statsCondition}`);
        }
        if (data.notice && data.notice !== 'AUTO_PLAN_SETUP') lines.push(data.notice);
        if (lines.length || (Array.isArray(data.sources) && data.sources.length)) {
            const meta = document.createElement('div');
            meta.className = 'pp-chat-meta';
            meta.textContent = lines.join('\n');
            if (Array.isArray(data.sources) && data.sources.length) {
                const list = document.createElement('ul');
                list.className = 'pp-chat-source-list';
                data.sources.slice(0, 3).forEach(function (url, index) {
                    if (typeof url !== 'string' || !/^https?:\/\//i.test(url)) return;
                    const li = document.createElement('li');
                    const a = document.createElement('a');
                    a.href = url;
                    a.target = '_blank';
                    a.rel = 'noopener noreferrer';
                    a.textContent = `근거 출처 ${index + 1}`;
                    li.appendChild(a);
                    list.appendChild(li);
                });
                meta.appendChild(list);
            }
            item.appendChild(meta);
        }
        log.scrollTop = log.scrollHeight;
    }

    function addMessage(text, className) {
        const item = document.createElement('div');
        item.className = `pp-chat-message ${className}`;
        const name = document.createElement('span');
        name.className = 'pp-chat-message-label';
        name.textContent = className === 'pp-chat-user' ? '나' : 'PASS PACE';
        const bubble = document.createElement('div');
        bubble.className = 'pp-chat-bubble';
        bubble.textContent = text == null ? '' : String(text);
        item.appendChild(name);
        item.appendChild(bubble);
        log.appendChild(item);
        log.scrollTop = log.scrollHeight;
        return item;
    }

    function setBusy(busy) {
        input.disabled = busy;
        send.disabled = busy;
        send.textContent = busy ? '처리 중' : '전송';
        if (!busy) input.focus();
    }
})();


/** [동건] 다중 자격증 학습계획 위저드. 같은 로그인 사용자의 로컬 브라우저에 임시 상태 저장. */
function initializeMultiGoalPlanner(root) {
    const $ = id => root.querySelector('#' + id);
    const tabChat = $('pp-chat-tab-chat');
    const tabPlanner = $('pp-chat-tab-planner');
    const chatView = $('pp-chat-chat-section');
    const planView = $('pp-chat-planner');
    const choiceBox = $('pp-chat-cert-selector');
    const formBox = $('pp-chat-goal-forms');
    const status = $('pp-chat-catalog-status');
    const daily = $('pp-chat-daily-minutes');
    const button = $('pp-chat-plan-calc');
    const error = $('pp-chat-plan-error');
    const output = $('pp-chat-plan-results');
    const uid = $('pp-chat-auth-content')?.dataset.userId;
    const major = $('pp-chat-auth-content')?.dataset.major || 'UNKNOWN';
    if (!tabChat || !tabPlanner || !chatView || !planView || !uid) return;
    // 같은 테스트 사용자 ID로 전공/비전공 전환할 때 이전 학습계획이 섞이지 않도록 분리
    const storageKey = 'passpace-multigoal-v2-user-' + uid + '-major-' + major;
    let catalog = null;
    let loaded = false;
    let catalogTimeSourceNotice = '';
    let catalogMajorLabel = major;
    // 단독 데모의 150분은 실제 사용자가 지정한 값이 아니다. 초기에는 비워 둔다.
    // Java DayOfWeek 기준: 월=1, ... 일=7. 이전 버전 사용자는 '매일'이 기본값.
    const allWeekdays = [1, 2, 3, 4, 5, 6, 7];
    let state = {dailyMinutes: null, dailyMinutesUserOverride:false, studyWeekdays:[...allWeekdays],
        goals: {}, version: 0, previous: null};
    let hasBrowserDailyPreference = false;
    try {
        const stored = JSON.parse(localStorage.getItem(storageKey));
        if (stored && typeof stored === 'object' && stored.goals && typeof stored.goals === 'object') {
            state = {...state, ...stored};
            hasBrowserDailyPreference = stored.dailyMinutesUserOverride === true &&
                Number.isInteger(Number(stored.dailyMinutes)) &&
                Number(stored.dailyMinutes) >= 30 && Number(stored.dailyMinutes) <= 960;
        }
    } catch (_) { /* 개인 정보 설정으로 저장이 차단돼도 플래너 자체는 동작 */ }
    // 명시적 입력이 없던 이전 버전의 150분은 절대로 사용자 선택으로 간주하지 않는다.
    if (!hasBrowserDailyPreference) {
        state.dailyMinutes = null;
        state.dailyMinutesUserOverride = false;
    }
    if (!Array.isArray(state.studyWeekdays) ||
            state.studyWeekdays.some(d => !Number.isInteger(d) || d < 1 || d > 7)) {
        state.studyWeekdays = [...allWeekdays];
    }
    state.studyWeekdays = [...new Set(state.studyWeekdays)].sort((a,b)=>a-b);
    daily.value = hasBrowserDailyPreference ? String(state.dailyMinutes) : '';
    const weekdayGroups = new Set();
    const dailyMirrorInputs = new Set([daily]);
    const dailyChoiceGroups = new Set();
    const dailyChangeListeners = new Set();

    function validDailyInput(value) {
        const text = String(value == null ? '' : value).trim();
        const minutes = Number(text);
        return text !== '' && Number.isInteger(minutes) && minutes >= 30 && minutes <= 960;
    }
    function save() {
        state.dailyMinutes = hasBrowserDailyPreference && validDailyInput(daily.value)
            ? Number(daily.value) : null;
        state.dailyMinutesUserOverride = hasBrowserDailyPreference;
        try {localStorage.setItem(storageKey, JSON.stringify(state));} catch (_) { /* 저장 실패는 계산과 무관 */ }
    }
    // UI 선택값만 사용한다. 프로필 대역의 기본 150분을 자동 승인하지 않는다.
    function setDailyPreference(value) {
        const text = String(value == null ? '' : value).trim();
        daily.value = text;
        hasBrowserDailyPreference = validDailyInput(text);
        for (const mirror of dailyMirrorInputs) mirror.value = text;
        for (const group of dailyChoiceGroups) {
            for (const b of group.querySelectorAll('button[data-minutes]')) {
                b.setAttribute('aria-pressed', String(b.dataset.minutes === text));
            }
        }
        save();
        if (catalog) refreshCatalogTimeStatus();
        for (const listener of dailyChangeListeners) listener();
    }
    function refreshCatalogTimeStatus() {
        status.textContent = '기준 집단: ' + catalogMajorLabel + '. ' +
            (hasBrowserDailyPreference ? '직접 선택한 하루 공부시간 ' + daily.value + '분. ' :
                '하루 공부 가능시간을 먼저 선택해 주세요. ') + catalogTimeSourceNotice +
            ' 과목별 학습시간은 소수 후기 기반 추정치(집단별 검증 평균 아님)입니다.';
    }
    function addDailyChoices(container) {
        const group = node('div', 'pp-chat-time-options');
        group.setAttribute('role', 'group');
        group.setAttribute('aria-label', '하루 학습 가능시간 선택');
        for (const minutes of [60, 90, 120, 150, 180, 240]) {
            const label = minutes % 60 === 0 ? (minutes / 60) + '시간' :
                Math.floor(minutes / 60) + '시간 ' + minutes % 60 + '분';
            const option = node('button', 'pp-chat-time-option', label);
            option.type = 'button';
            option.dataset.minutes = String(minutes);
            option.setAttribute('aria-pressed', String(daily.value === String(minutes)));
            option.addEventListener('click', () => setDailyPreference(String(minutes)));
            group.appendChild(option);
        }
        container.appendChild(group);
        dailyChoiceGroups.add(group);
    }
    function setWeekdays(days) {
        state.studyWeekdays = [...new Set(days)].sort((a,b)=>a-b);
        for (const group of weekdayGroups) {
            for (const button of group.querySelectorAll('button[data-weekday]')) {
                button.setAttribute('aria-pressed', String(state.studyWeekdays.includes(Number(button.dataset.weekday))));
            }
            for (const button of group.querySelectorAll('button[data-weekday-preset]')) {
                const preset = button.dataset.weekdayPreset;
                const daysForPreset = preset === 'all' ? allWeekdays :
                    preset === 'weekday' ? [1,2,3,4,5] : [6,7];
                button.setAttribute('aria-pressed', String(state.studyWeekdays.length === daysForPreset.length &&
                    daysForPreset.every(day => state.studyWeekdays.includes(day))));
            }
        }
        save();
        for (const listener of dailyChangeListeners) listener();
    }
    function addWeekdayChoices(container) {
        const group = node('div', 'pp-chat-weekday-setting');
        group.appendChild(node('strong', null, '② 공부할 요일 선택 (기본: 매일)'));
        group.appendChild(node('p', 'pp-chat-quick-description',
            '선택한 요일에만 공부가 배정됩니다. 정처기·SQLD가 같은 학습 가능일을 공유합니다.'));
        const presets = node('div', 'pp-chat-weekday-presets');
        for (const [id, title, days] of [
            ['all','매일',allWeekdays], ['weekday','월~금',[1,2,3,4,5]], ['weekend','토·일',[6,7]]]) {
            const button = node('button','pp-chat-weekday-preset',title);
            button.type = 'button';
            button.dataset.weekdayPreset = id;
            button.addEventListener('click', () => setWeekdays(days));
            presets.appendChild(button);
        }
        group.appendChild(presets);
        const row = node('div', 'pp-chat-weekday-options');
        row.setAttribute('role','group');
        row.setAttribute('aria-label','학습 가능한 요일 선택');
        for (const [day, name] of ['월','화','수','목','금','토','일'].map((name,i)=>[i+1,name])) {
            const option = node('button','pp-chat-weekday-option',name);
            option.type = 'button';
            option.dataset.weekday = String(day);
            option.setAttribute('aria-label', name + '요일');
            option.addEventListener('click', () => setWeekdays(
                state.studyWeekdays.includes(day) ? state.studyWeekdays.filter(v=>v!==day) : [...state.studyWeekdays, day]));
            row.appendChild(option);
        }
        group.appendChild(row);
        container.appendChild(group);
        weekdayGroups.add(group);
        setWeekdays(state.studyWeekdays);
    }
    function node(tag, klass, text) {
        const e = document.createElement(tag);
        if (klass) e.className = klass;
        if (text != null) e.textContent = text;
        return e;
    }
    function field(label, value, change, {min, max, step = 1, type = 'number'} = {}) {
        const wrap = node('label');
        wrap.textContent = label;
        const input = node('input', 'pp-chat-field-input');
        input.type = type;
        if (min != null) input.min = min;
        if (max != null) input.max = max;
        if (step != null && type === 'number') input.step = step;
        input.value = value == null ? '' : String(value);
        input.addEventListener('input', () => {change(input.value); save();});
        input.addEventListener('change', () => {change(input.value); save();});
        wrap.appendChild(input);
        return wrap;
    }
    function showError(message) {
        error.hidden = !message;
        error.textContent = message || '';
    }
    function setTab(planner) {
        planView.hidden = !planner;
        chatView.hidden = planner;
        tabPlanner.classList.toggle('pp-chat-tab-active', planner);
        tabChat.classList.toggle('pp-chat-tab-active', !planner);
        tabPlanner.setAttribute('aria-pressed', String(planner));
        tabChat.setAttribute('aria-pressed', String(!planner));
        if (planner && !loaded) loadCatalog();
    }
    tabChat.addEventListener('click', () => setTab(false));
    tabPlanner.addEventListener('click', () => setTab(true));
    const tabDailyChoices = $('pp-chat-daily-options');
    if (tabDailyChoices) addDailyChoices(tabDailyChoices);
    const tabWeekdays = $('pp-chat-weekdays-options');
    if (tabWeekdays) addWeekdayChoices(tabWeekdays);
    daily.addEventListener('input', () => setDailyPreference(daily.value));

    async function loadCatalog() {
        loaded = true;
        status.textContent = '자격증·과목 목록 불러오는 중…';
        try {
            const data = await PP.api('/api/chat/planner/catalog');
            catalog = data.goals || [];
            catalogMajorLabel = data.loginMajorLabel || major;
            const sourceIsDemo = /데모|대역|고정/.test(data.dailyTimeSource || '');
            const sourceNotice = sourceIsDemo
                ? '개발용 프로필의 고정 150분은 실제 설정값이 아니므로 자동 사용하지 않습니다.'
                : Number.isInteger(data.profileDailyMinutes)
                    ? 'DB/프로필 참고값 ' + data.profileDailyMinutes + '분은 확인용이며 직접 선택해야 적용됩니다.'
                    : '저장된 하루 공부시간이 확인되지 않았습니다.';
            catalogTimeSourceNotice = sourceNotice;
            refreshCatalogTimeStatus();
            renderCatalog();
        } catch (e) {
            loaded = false;
            status.textContent = e.message || '카탈로그 요청 실패';
        }
    }
    function renderCatalog() {
        choiceBox.replaceChildren();
        for (const cert of catalog) {
            const label = node('label', 'pp-chat-cert-choice');
            const checked = node('input');
            checked.type = 'checkbox';
            checked.checked = !!state.goals[cert.key]?.selected;
            checked.addEventListener('change', () => {
                const g = state.goals[cert.key] || {startDate:localDate(), examDate:'', subjects:{}};
                if (!g.examDate && cert.suggestedExamDate) g.examDate = cert.suggestedExamDate;
                if (!g.startDate) g.startDate = localDate();
                g.selected = checked.checked;
                state.goals[cert.key] = g;
                save();
                renderForms();
            });
            label.append(checked, node('span', null, cert.certificationName + (cert.temporaryCatalog ? ' (임시 과목 목록)' : '')));
            choiceBox.appendChild(label);
        }
        renderForms();
    }
    function renderForms() {
        formBox.replaceChildren();
        for (const cert of catalog || []) {
            const goal = state.goals[cert.key];
            if (!goal?.selected) continue;
            if (!goal.subjects) goal.subjects = {};
            const section = node('section', 'pp-chat-goal-card');
            section.appendChild(node('h4', 'pp-chat-goal-title', cert.certificationName));
            if (cert.majorEvidence) {
                const grp = cert.majorEvidence;
                const detail = node('div', 'pp-chat-group-reference' + (grp.fallback ? ' pp-chat-group-fallback' : ''));
                detail.appendChild(node('div', 'pp-chat-group-title',
                    '기준 집단: ' + grp.userMajorLabel + ' · 같은 집단의 근거 작성자 ' + grp.groupAuthors + '명' +
                    (grp.fallback ? ' · 대체자료 사용 중' : ' · 같은 집단의 과거 기록 적용')));
                const counts = grp.groupCounts || {};
                detail.appendChild(node('div', 'pp-chat-group-counts',
                    '기록 분류 — 전공 ' + (counts.major || 0) + '명 / 유사전공 ' +
                    (counts.related || 0) + '명 / 비전공 ' + (counts.nonMajor || 0) +
                    '명 / 전공 확인 불가 ' + (counts.unclassified || 0) + '명'));
                detail.appendChild(node('div', 'pp-chat-evidence-warning', grp.warning));
                section.appendChild(detail);
            }
            if (!goal.examDate && cert.suggestedExamDate) goal.examDate = cert.suggestedExamDate;
            if (!goal.startDate) goal.startDate = localDate();
            section.appendChild(node('p', 'pp-chat-quick-description',
                '학습 시작일은 자격증마다 독립적으로 설정할 수 있습니다. 기본값은 오늘입니다.'));
            section.appendChild(field('학습 시작일 (기본 오늘)', goal.startDate, v => {
                goal.startDate = v;
            }, {type:'date'}));
            section.appendChild(field('목표 시험일 (변경 가능)', goal.examDate || '', v => {goal.examDate = v;}, {type:'date', min: localDate()}));
            if (cert.scheduleNotice)
                section.appendChild(node('p', 'pp-chat-schedule-warning', cert.scheduleNotice));
            if (cert.evidence) {
                const ev = cert.evidence;
                const info = node('details', 'pp-chat-evidence-details');
                info.appendChild(node('summary', null,
                    '과목별 기준시간 근거 · 공개 원문 ' + ev.observations.length + '건 (50명 실측 평균 아님)'));
                info.appendChild(node('p', 'pp-chat-evidence-text',
                    '계산에 사용한 작성자 ' + ev.baselineAuthors + '명 · 해당 출제기준 실제 기록자 ' +
                    ev.matchingSyllabusAuthors + '명 · 원문 사례 전체시간 ' +
                    Number(ev.referenceTotalHours).toFixed(2) + '시간'));
                info.appendChild(node('p', 'pp-chat-evidence-text', '임시 계산 방식: ' + ev.method));
                info.appendChild(node('p', 'pp-chat-evidence-warning', ev.warning));
                const sources = node('ol', 'pp-chat-evidence-sources');
                for (const observation of ev.observations) {
                    const li = node('li');
                    const a = node('a', null, observation.title + ' (' +
                        Number(observation.totalHours).toFixed(2) + '시간)');
                    if (typeof observation.url === 'string' && /^https:\/\//.test(observation.url)) {
                        a.href = observation.url;
                        a.target = '_blank';
                        a.rel = 'noopener noreferrer';
                    }
                    li.appendChild(a);
                    li.appendChild(node('span', 'pp-chat-evidence-observation',
                        ' — ' + observation.calculation +
                        (observation.usedForBaseline ? ' [기준값 산정 사용]' : ' [보조 근거, 산정 제외]')));
                    sources.appendChild(li);
                }
                info.appendChild(sources);
                section.appendChild(info);
            }
            for (const subject of cert.subjects) {
                const sub = goal.subjects[subject.name] ||= {
                    familiarity: null, progressPercent: 0, actualMinutes: 0
                };
                const item = node('div', 'pp-chat-subject-card');
                item.appendChild(node('div', 'pp-chat-subject-name', subject.name));
                const choices = node('div', 'pp-chat-level-options');
                for (const [level, title] of [[1, '낮음 ×1.3'], [2, '보통 ×1.0'], [3, '높음 ×0.7']]) {
                    const option = node('button', 'pp-chat-level-option', title);
                    option.type = 'button';
                    option.setAttribute('aria-pressed', String(sub.familiarity === level));
                    option.addEventListener('click', () => {
                        sub.familiarity = level;
                        for (const e of choices.children)
                            e.setAttribute('aria-pressed', String(e === option));
                        save();
                    });
                    choices.appendChild(option);
                }
                item.appendChild(choices);
                const fields = node('div', 'pp-chat-subject-fields');
                const baseline = Number(subject.baseHours);
                fields.appendChild(node('div', 'pp-chat-baseline',
                    '잠정 계획 기준: ' + (baseline > 0 ? baseline.toFixed(2) + '시간' : '자료 없음') +
                    ' · 이해도 가중치 적용 전 · 집단별 실측 평균 아님' +
                    (cert.majorEvidence?.fallback ? ' · 다른 집단/미분류 사례의 대체값' : ' · 같은 집단 1명 사례')));
                fields.appendChild(node('div', 'pp-chat-source-count',
                    '원본 사례의 과목별 부분 기록 ' + Number(subject.directlyRecordedHours).toFixed(2) +
                    '시간 · 전체 작성자 ' + subject.directAuthorCount +
                    '명 · 내 집단의 해당 과목 기록 ' + subject.majorGroupSubjectAuthors +
                    '명 · 내 집단의 현재 출제기준 기록 ' + subject.majorGroupSameSyllabusAuthors + '명'));
                const derivation = node('details', 'pp-chat-subject-evidence');
                derivation.appendChild(node('summary', null, '이 과목의 계산 방식 보기'));
                derivation.appendChild(node('p', null, subject.derivation || subject.referenceType));
                fields.appendChild(derivation);
                const advance = node('details', 'pp-chat-optional-progress');
                advance.appendChild(node('summary', null, '진도·학습시간 수정 (선택사항)'));
                advance.appendChild(field('현재 진도율 (%)', sub.progressPercent,
                    v => {sub.progressPercent = v;}, {min:0, max:100}));
                advance.appendChild(field('실제 누적 학습시간 (분)', sub.actualMinutes,
                    v => {sub.actualMinutes = v;}, {min:0, max:200000, step:10}));
                item.append(fields,advance);
                section.appendChild(item);
            }
            formBox.appendChild(section);
        }
    }
    function localDate() {
        const d = new Date();
        return [d.getFullYear(), String(d.getMonth()+1).padStart(2,'0'), String(d.getDate()).padStart(2,'0')].join('-');
    }
    function makeRequest() {
        const goals = [];
        for (const cert of catalog || []) {
            const g = state.goals[cert.key];
            if (!g?.selected) continue;
            if (!g.examDate) throw new Error(cert.certificationName + ': 목표 시험일을 선택해 주세요.');
            if (!g.startDate) g.startDate = localDate();
            if (g.startDate >= g.examDate)
                throw new Error(cert.certificationName + ': 학습 시작일은 시험일 이전이어야 합니다.');
            const subjects = cert.subjects.map(s => {
                const sub = g.subjects?.[s.name] || {};
                if (![1,2,3].includes(sub.familiarity))
                    throw new Error(cert.certificationName + ' / ' + s.name + ': 사전 이해도를 클릭해 주세요.');
                if (!(Number(s.baseHours) > 0))
                    throw new Error(s.name + ': 내부 기준 학습시간이 없습니다. 출처 자료 등록이 필요합니다.');
                return {name:s.name, baseHours:Number(s.baseHours), familiarity:sub.familiarity,
                    progressPercent:Number(sub.progressPercent || 0), actualMinutes:Number(sub.actualMinutes || 0)};
            });
            goals.push({key: cert.key, certificationName: cert.certificationName,
                startDate:g.startDate, examDate:g.examDate, subjects});
        }
        if (!goals.length) throw new Error('최소 한 개의 자격증을 선택해 주세요.');
        if (!hasBrowserDailyPreference || !validDailyInput(daily.value))
            throw new Error('하루 공부 가능시간을 먼저 선택하거나 30~960분으로 직접 입력해 주세요.');
        if (!state.studyWeekdays.length)
            throw new Error('공부할 요일을 월~일 중 최소 하나 선택해 주세요.');
        return {dailyMinutes:Number(daily.value), studyWeekdays:[...state.studyWeekdays], goals};
    }
    button.addEventListener('click', async () => {
        showError('');
        let payload;
        try {payload = makeRequest();} catch (e) {showError(e.message); return;}
        button.disabled = true;
        button.textContent = '계산 중…';
        try {
            const result = await PP.api('/api/chat/planner/preview', {method: 'POST', body: payload});
            const previous = state.previous;
            const previousDate = state.lastCalculatedOn;
            const previousTotal = state.lastTotalRemaining;
            const daysElapsed = previousDate ? Math.max(0, Math.round(
                (new Date(result.calculatedOn + 'T00:00:00') - new Date(previousDate + 'T00:00:00')) / 86400000)) : 0;
            const revised = previousTotal != null && (Math.abs(result.totalRemainingMinutes - previousTotal) >=
                Math.max(60, Math.round(previousTotal * 0.15)) || daysElapsed >= 2 || !result.feasible);
            state.previous = Object.fromEntries(result.goals.map(g => [g.key, g.remainingMinutes]));
            state.lastCalculatedOn = result.calculatedOn;
            state.lastTotalRemaining = result.totalRemainingMinutes;
            state.version = (Number(state.version) || 0) + 1;
            state.history ||= [];
            state.history.unshift({version:state.version, date:result.calculatedOn,
                totalRemainingMinutes:result.totalRemainingMinutes, feasible:result.feasible});
            state.history = state.history.slice(0, 8);
            save();
            renderResult(result, previous, state.version, revised, daysElapsed);
        } catch (e) {showError(e.message || '계산 실패');}
        finally {button.disabled = false; button.textContent = '통합 계획 계산 / 진도 반영 재계획';}
    });

    function renderResult(result, previous, version, revised, daysElapsed) {
        output.replaceChildren();
        const totalHours = (m) => (m/60).toFixed(1) + '시간';
        const header = node('section', 'pp-chat-result-card' + (!result.feasible ? ' pp-chat-result-warning' : ''));
        header.append(node('div', 'pp-chat-result-title', '통합 계획 ' + version + '차 · ' + (result.feasible ? '학습시간 충족 가능' : '일정 조정 필요')),
            node('div', 'pp-chat-result-line', '하루 전체 ' + result.dailyMinutes + '분 / 잔여 필요 ' + totalHours(result.totalRemainingMinutes)
                + ' · 학습 요일 ' + state.studyWeekdays.map(d => '월화수목금토일'[d-1]).join('·')
                + (result.totalShortfallMinutes ? ' / 부족 ' + totalHours(result.totalShortfallMinutes) : '')));
        if (result.additionalDailyMinutes > 0) header.appendChild(node('div', 'pp-chat-result-line',
            '모든 마감일을 만족하려면 최소 하루 ' + result.minimumDailyMinutes + '분이 필요합니다. 현재보다 '
            + result.additionalDailyMinutes + '분 더 확보하거나 시험일을 조정해야 합니다.'));
        if (revised) header.appendChild(node('div', 'pp-chat-result-line',
            '재계획 제안: 진도·예상 소요시간 차이가 크거나 계획 후 ' + daysElapsed
            + '일이 지났습니다. 남은 학습량과 두 자격증의 일정을 다시 배분했습니다.'));
        output.appendChild(header);
        for (const g of result.goals) {
            const card = node('section', 'pp-chat-result-card');
            card.appendChild(node('div','pp-chat-result-title', g.certificationName + ' · 시험 ' + g.examDate));
            const before = previous && typeof previous[g.key] === 'number'
                ? ' (이전 계산 ' + totalHours(previous[g.key]) + ' → 현재 ' + totalHours(g.remainingMinutes) + ')' : '';
            card.appendChild(node('div','pp-chat-result-line','남은 학습량 ' + totalHours(g.remainingMinutes) + before));
            card.appendChild(node('div','pp-chat-result-line','시험까지 ' + g.remainingDays + '일 / '
                + (g.shortfallMinutes > 0 ? '계획 미배정 ' + totalHours(g.shortfallMinutes) : '배정 완료 · 마지막 배정일 ' + (g.projectedCompletionDate || '-'))));
            for (const sub of g.subjects) {
                const label = sub.name + ' · 이해도 ' + ({1:'낮음',2:'보통',3:'높음'}[sub.familiarity])
                    + ' ×' + sub.weight + ' · 잔여 ' + totalHours(sub.remainingMinutes)
                    + (sub.observedSpeedFactor !== 1 ? ' · 학습속도 보정 ×' + sub.observedSpeedFactor : '');
                card.appendChild(node('div','pp-chat-result-line',label));
            }
            output.appendChild(card);
        }
        const schedule = node('section','pp-chat-result-card');
        schedule.appendChild(node('div','pp-chat-result-title','날짜별 공동 배정 (' + result.days.length + '일)'));
        const initial = node('div');
        for (const day of result.days.slice(0, 14)) addDay(initial, day);
        schedule.appendChild(initial);
        if (result.days.length > 14) {
            const expand = node('details');
            expand.appendChild(node('summary',null,'나머지 ' + (result.days.length - 14) + '일 모두 보기'));
            for (const day of result.days.slice(14)) addDay(expand, day);
            schedule.appendChild(expand);
        }
        output.appendChild(schedule);
        const notes = node('section', 'pp-chat-result-card');
        notes.appendChild(node('div','pp-chat-result-title','계산 근거 및 주의사항'));
        (result.notices || []).forEach(t => notes.appendChild(node('div', 'pp-chat-result-line', '• ' + t)));
        if ((result.deadlineChecks || []).some(d => d.shortageMinutes > 0))
            notes.appendChild(node('div','pp-chat-result-line','시험일별 시간 부족: ' + result.deadlineChecks
                .filter(d=>d.shortageMinutes>0).map(d=>d.deadline+' 기준 '+totalHours(d.shortageMinutes)).join(', ')));
        output.appendChild(notes);
    }
    function addDay(parent, day) {
        const line = node('div','pp-chat-result-day');
        const weekday = '일월화수목금토'[new Date(day.date + 'T12:00:00').getDay()];
        line.appendChild(node('div','pp-chat-result-line', day.date + ' (' + weekday + ') · ' + day.allocatedMinutes + '/' + day.availableMinutes + '분'));
        for (const a of day.allocations)
            line.appendChild(node('div','pp-chat-result-line','  - ' + a.certificationName + ' / ' + a.subjectName + ': ' + a.minutes + '분'));
        parent.appendChild(line);
    }

    /** 채팅 입력 -> 종목 자동 선택 -> 과목별 이해도 버튼 -> 같은 채팅창에서 계획 제안. */
    async function startChatPlan(message, addMessage, currentConversationId) {
        if (!catalog) await loadCatalog();
        if (!catalog) throw new Error('과목 목록을 불러오지 못했습니다. MariaDB 연결을 확인해 주세요.');
        const wantSqld = /SQLD|SQL\s*개발자/i.test(message);
        const wantIpe = /정처기|정보처리기사/.test(message);
        const wantsPractical = wantIpe && /실기/.test(message) && !/필기/.test(message);
        const active = catalog.filter(cert =>
            wantSqld && cert.certificationName === 'SQLD' ||
            wantIpe && (wantsPractical
                ? cert.certificationName === '정보처리기사 실기'
                : cert.certificationName.startsWith('정보처리기사 필기')));
        if (!active.length) throw new Error('현재 지원하는 정처기 필기·실기 또는 SQLD를 찾지 못했습니다.');
        for (const cert of catalog) {
            const goal = state.goals[cert.key] ||= {selected:false, startDate:localDate(), examDate:'', subjects:{}};
            goal.selected = active.some(c => c.key === cert.key);
            if (goal.selected && !goal.examDate && cert.suggestedExamDate)
                goal.examDate = cert.suggestedExamDate;
            if (!goal.startDate) goal.startDate = localDate();
            if (!goal.subjects) goal.subjects = {};
        }
        save();
        const messageItem = addMessage('', 'pp-chat-bot');
        const bubble = messageItem.querySelector('.pp-chat-bubble');
        bubble.replaceChildren();
        bubble.appendChild(node('strong',null,'자동 학습계획 — 시간·요일·이해도 선택'));
        bubble.appendChild(node('p','pp-chat-quick-description',
            '학습 시작일은 자격증별로 기본 오늘이며 변경할 수 있습니다. 시험일은 2026년 공고의 월/일을 2027년으로 옮긴 임시 목표일(공식 아님)입니다.'));
        // 하루 시간은 숨겨진 선택 설정이 아닌, 최초 1회 필수 입력이다.
        const timeSetup = node('section','pp-chat-quick-time');
        timeSetup.appendChild(node('strong',null,'① 하루 총 공부 가능시간을 선택해 주세요 (필수)'));
        timeSetup.appendChild(node('p','pp-chat-quick-description',
            '정처기와 SQLD가 하루 시간을 함께 사용합니다. 데모의 150분은 자동으로 적용하지 않아요.'));
        addDailyChoices(timeSetup);
        const customLabel = node('label','pp-chat-time-custom-label','그 외 시간은 분 단위로 직접 입력');
        const customDaily = node('input','pp-chat-field-input');
        customDaily.type='number';
        customDaily.min='30';
        customDaily.max='960';
        customDaily.step='10';
        customDaily.inputMode='numeric';
        customDaily.placeholder='예: 75 (분)';
        customDaily.value = daily.value;
        customDaily.addEventListener('input', () => setDailyPreference(customDaily.value));
        dailyMirrorInputs.add(customDaily);
        customLabel.appendChild(customDaily);
        timeSetup.appendChild(customLabel);
        bubble.appendChild(timeSetup);
        // 채팅 자동계획에서도 탭과 동일한 주간 학습 요일을 선택한다.
        addWeekdayChoices(bubble);
        const adjust = node('details','pp-chat-quick-adjust');
        adjust.appendChild(node('summary',null,'자격증별 공부 시작일·시험일 바꾸기 (선택)')); 
        for (const cert of active) {
            const g = state.goals[cert.key];
            adjust.appendChild(field(cert.certificationName + ' 공부 시작일',g.startDate, v => {
                g.startDate=v;
            }, {type:'date'}));
            adjust.appendChild(field(cert.certificationName + ' 목표 시험일',g.examDate, v => {
                g.examDate=v;
            }, {type:'date',min:localDate()}));
        }
        bubble.appendChild(adjust);
        const totalBudgetMatch = /총\s*(\d{1,4})\s*시간/.exec(message);
        if (totalBudgetMatch) {
            bubble.appendChild(node('p','pp-chat-quick-description',
                '총 '+totalBudgetMatch[1]+'시간은 전체 학습 예산이고, 하루 가능시간과 다릅니다. 현재는 필수 예상학습량부터 배정합니다. 남는 시간은 기출·복습에 활용할 수 있습니다.'));
        }
        const missing = [];
        for (const cert of active) {
            bubble.appendChild(node('h4','pp-chat-quick-cert', cert.certificationName + ' · 공부 시작 ' + state.goals[cert.key].startDate + ' · 목표일 ' + state.goals[cert.key].examDate));
            if (cert.majorEvidence?.fallback)
                bubble.appendChild(node('p','pp-chat-quick-description',
                    '전공별 표본 부족: 집단 평균이 아닌 임시 추정시간을 사용합니다.'));
            for (const sub of cert.subjects) {
                const target = state.goals[cert.key].subjects[sub.name] ||= {
                    familiarity:null,progressPercent:0,actualMinutes:0};
                const row = node('div','pp-chat-quick-subject');
                row.appendChild(node('div','pp-chat-quick-subject-label',sub.name));
                const buttons = node('div','pp-chat-level-options');
                for (const [level,label] of [[1,'낮음'],[2,'보통'],[3,'높음']]) {
                    const btn = node('button','pp-chat-level-option',label);
                    btn.type='button';
                    btn.setAttribute('aria-pressed',String(target.familiarity===level));
                    btn.addEventListener('click',()=>{
                        target.familiarity=level;
                        for (const b of buttons.children) b.setAttribute('aria-pressed',String(b===btn));
                        save();
                        updateReady();
                    });
                    buttons.appendChild(btn);
                }
                row.appendChild(buttons);
                bubble.appendChild(row);
                missing.push(target);
            }
        }
        const calculate = node('button','pp-chat-plan-calc','이해도 선택 후 자동 계획 생성');
        calculate.type='button';
        bubble.appendChild(calculate);
        const messageArea = node('div','pp-chat-quick-result');
        bubble.appendChild(messageArea);
        let hasCalculated = false;
        function updateReady() {
            const validTime = hasBrowserDailyPreference && validDailyInput(daily.value);
            const validWeekdays = state.studyWeekdays.length > 0;
            const validFamiliarity = missing.every(t => [1,2,3].includes(Number(t.familiarity)));
            calculate.disabled = !validTime || !validWeekdays || !validFamiliarity;
            calculate.textContent = !validTime ? '하루 공부 가능시간을 먼저 선택해 주세요'
                : !validWeekdays ? '공부할 요일을 하나 이상 선택해 주세요'
                : !validFamiliarity ? '과목별 이해도를 선택해 주세요'
                : hasCalculated ? '변경된 입력으로 다시 계산' : '학습계획 자동 생성';
        }
        for (const listener of dailyChangeListeners) {
            if (listener._element && !listener._element.isConnected) dailyChangeListeners.delete(listener);
        }
        updateReady._element = calculate;
        dailyChangeListeners.add(updateReady);
        updateReady();
        calculate.addEventListener('click', async()=>{
            if (calculate.disabled) return;
            calculate.disabled=true;
            calculate.textContent='계획 계산 중…';
            messageArea.replaceChildren();
            try {
                const request = makeRequest();
                const result = await PP.api('/api/chat/planner/preview-chat',
                    {method: 'POST', body: {plan: request, conId: currentConversationId()}});
                const plan = result.plan;
                messageArea.appendChild(node('p','pp-chat-quick-description',result.answer));
                messageArea.appendChild(node('p','pp-chat-quick-description',
                    '선택 학습 요일: ' + state.studyWeekdays.map(d => '월화수목금토일'[d-1]).join('·') +
                    ' · 선택하지 않은 요일에는 공부를 배정하지 않습니다.'));
                if (totalBudgetMatch) {
                    const budgetMinutes=Number(totalBudgetMatch[1])*60;
                    const difference=budgetMinutes-plan.totalRemainingMinutes;
                    messageArea.appendChild(node('p','pp-chat-quick-description',
                        difference>=0
                        ? '전체 '+totalBudgetMatch[1]+'시간 중 기본 학습 추정 '+(plan.totalRemainingMinutes/60).toFixed(1)+'시간을 배정했습니다. 남은 '+(difference/60).toFixed(1)+'시간은 복습 예산이며 아직 날짜별 계획에는 배정하지 않았습니다.'
                        : '전체 '+totalBudgetMatch[1]+'시간 예산보다 추정 학습량이 '+(-difference/60).toFixed(1)+'시간 많습니다. 시험일까지 추가 시간이 필요합니다.'));
                }
                for (const g of plan.goals) {
                    messageArea.appendChild(node('p','pp-chat-quick-goal',
                        g.certificationName + ': ' + g.startDate + '부터 ' + g.examDate + ' 전까지 ' +
                        (g.remainingMinutes/60).toFixed(1) + '시간')); 
                }
                const firstWeek = node('details','pp-chat-quick-adjust');
                firstWeek.open = true;
                firstWeek.appendChild(node('summary',null,'날짜별 계획 (' + plan.days.length + '일)'));
                for (const day of plan.days.slice(0,7)) addDay(firstWeek,day);
                if (plan.days.length>7) {
                    const rest = node('details');
                    rest.appendChild(node('summary',null,'나머지 일정 ' + (plan.days.length-7) + '일 펼치기'));
                    for (const day of plan.days.slice(7)) addDay(rest,day);
                    firstWeek.appendChild(rest);
                }
                messageArea.appendChild(firstWeek);
                if (plan.additionalDailyMinutes>0)
                    messageArea.appendChild(node('p','pp-chat-evidence-warning',
                        '현재 일정은 학습시간이 부족합니다. 최소 하루 '+plan.minimumDailyMinutes+'분이 필요합니다.'));
                messageArea.appendChild(node('p','pp-chat-evidence-warning',
                    '하루 공부 가능시간은 상한입니다. 선택한 요일에 45분 이상 블록으로 분산하며 마지막 잔여시간은 짧을 수 있습니다. ' +
                    '기출·복습 시간은 아직 추가 산정하지 않았습니다. 근거는 소수 후기 기반 임시 추정치이고 시험일은 가상 목표일입니다.')); 
                state.previous=Object.fromEntries(plan.goals.map(g=>[g.key,g.remainingMinutes]));
                state.lastCalculatedOn=plan.calculatedOn;
                state.lastTotalRemaining=plan.totalRemainingMinutes;
                state.version=(Number(state.version)||0)+1;
                hasCalculated = true;
                save();
            } catch(e) {
                messageArea.appendChild(node('p','pp-chat-plan-error',e.message||'계산 실패'));
            } finally {
                updateReady();
            }
        });
        // 이 함수 밖에 선언된 log 변수 대신 현재 위젯의 메시지 영역을 조회한다.
        const chatLog = root.querySelector('#pp-chat-log');
        if (chatLog) chatLog.scrollTop = chatLog.scrollHeight;
    }
    return {startChatPlan};
}
