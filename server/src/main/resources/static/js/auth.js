/*
 * [JWT] 모든 화면이 같이 쓰는 로그인 도구 (fragments/layout.html 의 head 에서 불러온다)
 *
 * 세션이 없어졌으므로 "로그인 상태" = 브라우저에 저장된 토큰이다.
 *   - 로그인    : POST /auth/login → 받은 accessToken 을 localStorage 에 저장
 *   - API 호출  : PP.api(...) 가 Authorization: Bearer 토큰 헤더를 자동으로 붙인다
 *   - 로그아웃  : 저장한 토큰을 지운다 (서버에 할 일이 없음)
 *
 * 서버 응답은 항상 {status, code, data} 모양이다 (강의안 ResponseDto).
 *   성공 → PP.api 가 data 만 돌려준다
 *   실패 → PP.ApiError 를 던진다 (error.code = "FAILURE_LOGIN" 같은 ErrorCode 이름, error.message = 한국어 문장)
 *
 * 나중에 Flutter 앱을 만들면 이 파일이 하는 일(토큰 저장·헤더 붙이기·401 처리)을 앱에서 똑같이 하면 된다.
 */
(function () {
    'use strict';

    const TOKEN_KEY = 'pp.accessToken';

    /** localStorage 는 브라우저 설정(사생활 보호 모드 등)에 따라 막힐 수 있어 try 로 감싼다 */
    function getToken() {
        try { return localStorage.getItem(TOKEN_KEY); } catch (e) { return null; }
    }
    function setToken(token) {
        try { localStorage.setItem(TOKEN_KEY, token); } catch (e) { /* 저장 실패 시 이번 화면에서만 로그인 */ }
    }
    function clearToken() {
        try { localStorage.removeItem(TOKEN_KEY); } catch (e) { /* 무시 */ }
    }

    /**
     * 토큰 가운데 부분(내용)을 읽는다. 서명 확인은 서버가 하므로 여기서는 "화면 표시용"으로만 쓴다.
     * 예) { userId: 2, loginId: "kim_01", nickname: "김패스", majorType: "MAJOR", role: "USER", exp: 1794478767 }
     */
    function readTokenPayload(token) {
        try {
            const base64 = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
            const json = decodeURIComponent(atob(base64).split('')
                .map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)).join(''));
            return JSON.parse(json);
        } catch (e) {
            return null;
        }
    }

    /** 지금 로그인한 사람 (토큰이 없거나 만료됐으면 null) */
    function currentUser() {
        const token = getToken();
        if (!token) return null;
        const payload = readTokenPayload(token);
        if (!payload || (payload.exp && payload.exp * 1000 < Date.now())) {
            clearToken();   // 만료된 토큰은 지운다 → 로그아웃 상태로 보이게
            return null;
        }
        return payload;
    }

    /** 서버 오류 응답을 담는 객체 */
    class ApiError extends Error {
        constructor(status, body) {
            const data = (body && body.data) || {};
            // detail 이 있으면 더 구체적인 이유 (예: "password: 비밀번호는 8~50자여야 합니다.")
            super(data.detail ? cleanDetail(data.detail) : (data.ko || ('요청 실패 (' + status + ')')));
            this.status = status;
            this.code = data.code || null;
            this.field = data.detail && data.detail.includes(':') ? data.detail.split(':')[0].trim() : null;
        }
    }

    /** "필드명: 문장" 모양이면 문장만 보여 준다 */
    function cleanDetail(detail) {
        const i = detail.indexOf(': ');
        return i > 0 && /^[\w.\[\]]+$/.test(detail.slice(0, i)) ? detail.slice(i + 2) : detail;
    }

    /**
     * API 호출. 토큰 헤더를 붙이고, 성공이면 data 를, 실패면 ApiError 를 던진다.
     * @param url   예: '/auth/user-info'
     * @param opts  { method: 'POST', body: {...} }  ← body 는 객체를 넘기면 JSON 으로 바꿔 보낸다
     *              { form: {...} }                   ← 관리자 API 처럼 @RequestParam 을 받는 곳
     */
    async function api(url, opts = {}) {
        const headers = Object.assign({}, opts.headers || {});
        const token = getToken();
        if (token) headers['Authorization'] = 'Bearer ' + token;

        let body = opts.body;
        if (opts.form) {
            body = new URLSearchParams(opts.form);
        } else if (body !== undefined && typeof body !== 'string') {
            headers['Content-Type'] = 'application/json';
            body = JSON.stringify(body);
        }

        const res = await fetch(url, { method: opts.method || 'GET', headers, body });
        let json = null;
        try { json = await res.json(); } catch (e) { /* JSON 이 아닌 응답 */ }

        if (res.status === 401) {
            // 토큰 없음·만료·변조 → 저장된 토큰을 지운다 (화면은 로그인 안내를 보여 주면 된다)
            clearToken();
            renderHeader();
        }
        if (!res.ok || !json || json.status !== 'SUCCESS') {
            throw new ApiError(res.status, json);
        }
        return json.data;
    }

    /** 로그인: 성공하면 토큰을 저장하고 로그인 정보(토큰 내용)를 돌려준다 */
    async function login(loginId, password) {
        const data = await api('/auth/login', { method: 'POST', body: { loginId, password } });
        setToken(data.accessToken);
        return currentUser();
    }

    /** 로그아웃: 토큰만 지우면 끝 */
    function logout(redirectTo) {
        clearToken();
        location.href = redirectTo || '/';
    }

    /** 로그인이 필요한 화면에서 부른다. 로그인 안 했으면 로그인 화면으로 보낸다 (돌아올 주소를 붙여서) */
    function requireLogin() {
        const user = currentUser();
        if (!user) {
            location.replace('/login?redirectURL=' + encodeURIComponent(location.pathname + location.search));
            return null;
        }
        return user;
    }

    /** 로그인 후 돌아갈 주소. 우리 사이트 안쪽 주소만 허용한다 (예전 AuthController.safeRedirectURL 과 같은 규칙) */
    function safeRedirect(url) {
        if (!url || !url.startsWith('/') || url.startsWith('//') || url.includes('\\')) return '/';
        if (url.startsWith('/login') || url.startsWith('/signup')) return '/';
        return url;
    }

    /**
     * 공통 헤더의 "로그인 / 닉네임 님" 바꾸기.
     * 예전에는 서버가 ${loginUser} 로 그렸지만, 이제 서버는 누가 보는지 모르므로 JS 가 토큰을 보고 바꾼다.
     */
    function renderHeader() {
        const user = currentUser();
        document.querySelectorAll('[data-pp-when="guest"]').forEach(el => el.hidden = !!user);
        document.querySelectorAll('[data-pp-when="member"]').forEach(el => el.hidden = !user);
        document.querySelectorAll('[data-pp-when="admin"]').forEach(el => el.hidden = !(user && user.role === 'ADMIN'));
        document.querySelectorAll('[data-pp-nickname]').forEach(el => {
            el.textContent = user ? (user.nickname || user.loginId) + ' 님' : '';
        });
    }

    document.addEventListener('DOMContentLoaded', function () {
        renderHeader();
        document.querySelectorAll('[data-pp-logout]').forEach(btn =>
            btn.addEventListener('click', () => logout('/')));
    });

    // 다른 스크립트(chatbot.js, 각 화면)가 쓰도록 PP 이름으로 내보낸다
    window.PP = {
        api, login, logout, currentUser, requireLogin, safeRedirect, renderHeader,
        setToken, getToken, ApiError
    };
})();
