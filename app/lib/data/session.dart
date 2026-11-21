import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'models.dart';
import 'plan_draft.dart';

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
    if (turn != _generation) return;
    await _persist(host, token);
    if (turn != _generation) return;
    _token = token;
    user = profile;
    account = api;
  }

  Future<void> signIn(String id, String password) async {
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
    final current = _generation;
    final api = account!;
    final data = {'nickname': nickname, 'email': email, 'majorType': major};
    final token = await api.updateProfile(data);
    if (current != _generation) return;
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
    user = Profile.from({...data, 'loginId': user!.id});
    notifyListeners();
    await _persist(origin, token);
  }

  Future<void> changeOrigin(String raw) async {
    final host = validOrigin(raw);
    await _persist(host, null);
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
    await _persist(origin, null);
    ++_generation;
    _token = null;
    user = null;
    account = null;
    restoreError = null;
    restoring = false;
    notice = null;
    notifyListeners();
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
