import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'models.dart';
import 'plan_draft.dart';
import 'subject_colors.dart';

abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
}

class AndroidStore implements SessionStore {
  final _storage = const FlutterSecureStorage();
  static const _key = 'passpace.account.v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

class Session extends ChangeNotifier {
  final SessionStore store;
  final http.Client client;
  final PlanDraftStorage drafts;
  String origin = configuredOrigin;
  String? _token;
  Profile? user;
  PassApi? account;
  bool restoring = true;
  String? restoreError, notice;
  bool withdrawing = false;
  _WithdrawalCleanup? _withdrawalCleanup;
  bool get withdrawalCleanupRequired => _withdrawalCleanup != null;
  bool get accountActionsBlocked => withdrawing || withdrawalCleanupRequired;
  int _generation = 0;
  Future<void> _writes = Future.value();
  Session(this.store, this.client, {PlanDraftStorage? drafts})
    : drafts = drafts ?? SecurePlanDraftStorage();
  PlanDraftRepository get planDraft =>
      PlanDraftRepository(drafts, origin, user!.id);
  PassApi get publicApi => PassApi(client, origin);
  Future<void> _persist(String base, String? token) {
    final value = jsonEncode({'origin': base, 'token': token});
    final write = _writes.then((_) => store.write(value));
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> restore() async {
    _ensureNoWithdrawal();
    final turn = ++_generation;
    restoring = true;
    restoreError = null;
    notifyListeners();
    try {
      final value = await store.read();
      if (turn != _generation) return;
      if (value != null) {
        final saved = object(jsonDecode(value));
        final host = validOrigin(saved['origin'] as String);
        origin = host;
        _token = saved['token'] as String?;
      }
      final token = _token;
      if (token != null) await _open(origin, token, turn);
    } catch (e) {
      if (turn == _generation) restoreError = friendly(e);
    } finally {
      if (turn == _generation) {
        restoring = false;
        notifyListeners();
      }
    }
  }

  Future<void> _open(String host, String token, int turn) async {
    final api = PassApi(
      client,
      host,
      token: token,
      onExpired: () {
        if (turn == _generation) unawaited(_expire());
      },
    );
    final profile = await api.profile();
    if (turn != _generation || accountActionsBlocked) return;
    await _persist(host, token);
    if (turn != _generation || accountActionsBlocked) return;
    _token = token;
    user = profile;
    account = api;
  }

  Future<void> signIn(String id, String password) async {
    _ensureNoWithdrawal();
    final turn = ++_generation;
    final host = origin;
    final token = await publicApi.login(id, password);
    if (turn != _generation) return;
    await _open(host, token, turn);
    if (turn == _generation) {
      notice = null;
      notifyListeners();
    }
  }

  Future<void> updateProfile(
    String nickname,
    String email,
    String major,
  ) async {
    _ensureNoWithdrawal();
    final current = _generation;
    final api = account!;
    final data = {'nickname': nickname, 'email': email, 'majorType': major};
    final token = await api.updateProfile(data);
    if (current != _generation || accountActionsBlocked) return;
    final turn = ++_generation;
    _token = token;
    account = PassApi(
      client,
      origin,
      token: token,
      onExpired: () {
        if (turn == _generation) unawaited(_expire());
      },
    );
    user = Profile.from({...data, 'loginId': user!.id, 'userId': user!.userId});
    notifyListeners();
    await _persist(origin, token);
  }

  Future<void> changeOrigin(String raw) async {
    _ensureNoWithdrawal();
    final host = validOrigin(raw);
    await _persist(host, null);
    if (accountActionsBlocked) return;
    ++_generation;
    origin = host;
    _token = null;
    account = null;
    user = null;
    restoring = false;
    restoreError = null;
    notice = null;
    notifyListeners();
  }

  Future<void> logout() async {
    _ensureNoWithdrawal();
    await _persist(origin, null);
    if (accountActionsBlocked) return;
    ++_generation;
    _token = null;
    user = null;
    account = null;
    restoreError = null;
    restoring = false;
    notice = null;
    notifyListeners();
  }

  void _ensureNoWithdrawal() {
    if (accountActionsBlocked) {
      throw const ApiError('회원탈퇴 처리와 기기 정보 정리를 먼저 마쳐 주세요.');
    }
  }

  Future<void> withdrawAccount(
    String password,
    String confirmation, {
    Future<bool> Function()? prepare,
  }) async {
    _ensureNoWithdrawal();
    final api = account, profile = user;
    final generation = _generation, host = origin;
    if (api == null || profile == null) {
      throw const ApiError('다시 로그인해 주세요.', 401);
    }
    if (password.isEmpty || confirmation != '${profile.id}회원탈퇴') {
      throw const ApiError('비밀번호와 아이디 확인 문구를 확인해 주세요.', 400);
    }
    bool current() =>
        generation == _generation &&
        identical(api, account) &&
        user?.id == profile.id &&
        user?.userId == profile.userId &&
        origin == host;
    withdrawing = true;
    notifyListeners();
    try {
      if (prepare != null && !await prepare()) {
        throw const ApiError(
          '진행 중인 기록 저장이나 확인을 먼저 마쳐 주세요. '
          '타이머 상태를 저장하고 측정 알림을 멈춘 뒤 회원탈퇴를 진행할 수 있어요.',
        );
      }
      if (!current()) throw const ApiError('계정이 바뀌었어요. 현재 로그인 정보를 확인해 주세요.');
      await api.withdrawAccount(password, confirmation);
      // A late result from a previous account must not clear a new session.
      // Revoked-token polling can expire this account before DELETE returns;
      // with no replacement account, its confirmed cleanup is still required.
      if (!current() && !(account == null && user == null && origin == host)) {
        return;
      }
      _withdrawalCleanup = _WithdrawalCleanup(host, profile.id, profile.userId);
      ++_generation;
      _token = null;
      user = null;
      account = null;
      restoring = false;
      restoreError = null;
      notice = '회원탈퇴가 완료되었어요. 이 기기의 로그인 정보와 초안·타이머를 정리하고 있어요.';
      notifyListeners();
      await _finishWithdrawalCleanup();
    } finally {
      withdrawing = false;
      notifyListeners();
    }
  }

  Future<void> retryWithdrawalCleanup() async {
    if (withdrawing) throw const ApiError('기기 정보를 정리하고 있어요. 잠시 기다려 주세요.');
    if (_withdrawalCleanup == null) return;
    withdrawing = true;
    notifyListeners();
    try {
      await _finishWithdrawalCleanup();
    } finally {
      withdrawing = false;
      notifyListeners();
    }
  }

  Future<void> _finishWithdrawalCleanup() async {
    final pending = _withdrawalCleanup!;
    var failed = false;
    // Try every item even if one storage operation fails. No server retry.
    try {
      await _persist(pending.origin, null);
    } catch (_) {
      failed = true;
    }
    final identities = {
      pending.loginId,
      if (pending.userId case final id?) id.toString(),
    };
    for (final identity in identities) {
      for (final kind in [
        'plan-draft',
        'study-timer',
        SubjectColorPreferences.storageKind,
      ]) {
        try {
          await drafts.write(
            accountStorageKey(kind, pending.origin, identity),
            null,
          );
        } catch (_) {
          failed = true;
        }
      }
    }
    if (!failed) _withdrawalCleanup = null;
    notice = failed
        ? '회원탈퇴가 완료되었어요. 이 기기의 로그인 정보 또는 초안·타이머를 '
              '정리하지 못했어요. 기기 정보 정리를 다시 시도해 주세요.'
        : '회원탈퇴가 완료되었어요. 이 기기의 로그인 정보와 초안·타이머를 정리했어요.';
  }

  Future<void> _expire() async {
    ++_generation;
    _token = null;
    user = null;
    account = null;
    restoring = false;
    restoreError = null;
    notice = '로그인이 만료되었어요. 다시 로그인해 주세요.';
    notifyListeners();
    try {
      await _persist(origin, null);
    } catch (_) {
      /* The expired token cannot open an account. */
    }
  }
}

class _WithdrawalCleanup {
  final String origin;
  final String loginId;
  final int? userId;
  const _WithdrawalCleanup(this.origin, this.loginId, this.userId);
}
