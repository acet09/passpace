/*
 * [동건] 마이페이지 "학습 계획" 칸 — 챗봇에서 "마이페이지에 넣기"로 저장한 계획을 일별·주별·월별로 보여 준다.
 * 임시 최소 구현이다. 학습 계획·통계 담당 화면이 들어오면 이 파일과 mypage.html 의 #saved-plan-section 만 빼면 된다.
 * 데이터: GET /api/chat/planner/review-based/saved  (STUDY_PLANS · STUDY_PLAN_DETAILS 의 챗봇 계획)
 */
(function () {
    'use strict';
    const box = document.getElementById('saved-plan-body');
    const tabs = document.getElementById('saved-plan-tabs');
    if (!box || !tabs || !window.PP || !PP.getToken || !PP.getToken()) return;

    let tasks = [];
    let mode = 'day';

    function el(tag, text, style) {
        const e = document.createElement(tag);
        if (text != null) e.textContent = text;
        if (style) e.style.cssText = style;
        return e;
    }
    function hours(minutes) {
        return (minutes / 60).toFixed(1) + '시간';
    }
    function parse(text) {
        const [y, m, d] = text.split('-').map(Number);
        return new Date(y, m - 1, d);
    }
    function iso(date) {
        return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, '0'),
            String(date.getDate()).padStart(2, '0')].join('-');
    }
    /** 그 날짜가 속한 주의 월요일 */
    function monday(text) {
        const d = parse(text);
        d.setDate(d.getDate() - (d.getDay() + 6) % 7);
        return d;
    }
    /** 일별·주별·월별 묶음의 이름 */
    function groupKey(task) {
        if (mode === 'month') return task.date.slice(0, 7);
        if (mode === 'week') return iso(monday(task.date));
        return task.date;
    }
    function groupTitle(key) {
        if (mode === 'month') return key.replace('-', '년 ') + '월';
        if (mode === 'week') {
            const end = parse(key);
            end.setDate(end.getDate() + 6);
            return key + ' ~ ' + iso(end) + ' 주';
        }
        return key + ' (' + '일월화수목금토'[parse(key).getDay()] + ')';
    }

    function render() {
        box.replaceChildren();
        for (const b of tabs.children) {
            const on = b.dataset.mode === mode;
            b.setAttribute('aria-pressed', String(on));
            b.style.cssText = 'padding:6px 16px;border-radius:8px;cursor:pointer;font-size:13px;border:1px solid '
                + (on ? '#2f6bff;background:#2f6bff;color:#fff' : '#d5dce8;background:#fff;color:#4a5568');
        }
        if (!tasks.length) {
            box.appendChild(el('p', '아직 넣은 계획이 없습니다. 챗봇에서 학습계획을 만든 뒤 "마이페이지에 넣기"를 눌러 주세요.',
                'color:#8490a2;font-size:13px'));
            return;
        }
        // 자격증마다 공부 기간이 다를 수 있으므로 자격증별 첫 공부일~마지막 공부일을 따로 보여 준다
        const periods = new Map();
        for (const t of tasks) {
            const p = periods.get(t.certificationName) || {first: t.date, last: t.date, minutes: 0};
            if (t.date < p.first) p.first = t.date;
            if (t.date > p.last) p.last = t.date;
            p.minutes += t.minutes;
            periods.set(t.certificationName, p);
        }
        const summary = el('ul', null, 'margin:0 0 6px;padding-left:18px;font-size:13px;color:#4a5568');
        for (const [name, p] of periods)
            summary.appendChild(el('li', name + ': ' + p.first + ' ~ ' + p.last + ' · 총 ' + hours(p.minutes)));
        box.appendChild(summary);
        const groups = new Map();
        for (const t of tasks) {
            const key = groupKey(t);
            if (!groups.has(key)) groups.set(key, []);
            groups.get(key).push(t);
        }
        for (const [key, list] of groups) {
            const total = list.reduce((sum, t) => sum + t.minutes, 0);
            const card = el('div', null, 'padding:12px 0;border-bottom:1px solid #edf1f6');
            card.appendChild(el('strong', groupTitle(key) + ' · ' + hours(total), 'font-size:14px'));
            // 일별은 그날 할 일 그대로, 주별·월별은 과목별 합계
            const sums = new Map();
            for (const t of list) {
                const name = t.certificationName + ' · ' + t.subjectName;
                sums.set(name, (sums.get(name) || 0) + t.minutes);
            }
            const ul = el('ul', null, 'margin:6px 0 0;padding-left:18px;font-size:13px;color:#4a5568');
            for (const [name, minutes] of sums)
                ul.appendChild(el('li', name + ' — ' + (mode === 'day' ? minutes + '분' : hours(minutes))));
            card.appendChild(ul);
            box.appendChild(card);
        }
    }

    tabs.addEventListener('click', function (e) {
        const button = e.target.closest('button[data-mode]');
        if (!button) return;
        mode = button.dataset.mode;
        render();
    });

    PP.api('/api/chat/planner/review-based/saved').then(function (data) {
        const plan = data && data.plan;
        tasks = plan ? plan.tasks : [];
        const title = document.getElementById('saved-plan-name');
        if (plan && title) title.textContent = plan.planName + ' · 전체 ' + plan.startDate + ' ~ ' + plan.endDate;
        render();
    }).catch(function (err) {
        box.replaceChildren(el('p', '계획을 불러오지 못했습니다: ' + (err.message || '오류'), 'color:#c0392b;font-size:13px'));
    });
})();
