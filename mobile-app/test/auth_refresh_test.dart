import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valet_driver_app/api/api_client.dart';
import 'package:valet_driver_app/api/api_exception.dart';
import 'package:valet_driver_app/config/api_config.dart';
import 'package:valet_driver_app/models/auth_user.dart';
import 'package:valet_driver_app/api/token_store.dart';

/// A stateful fake token store: `save()` rotates the in-memory pair so the next
/// request (and the interceptor's retry) reads the refreshed access token.
class _FakeTokenStore implements TokenStore {
  _FakeTokenStore({String? access, String? refresh})
      : _access = access,
        _refresh = refresh;

  String? _access;
  String? _refresh;
  int saves = 0;
  int clears = 0;

  @override
  Future<String?> get accessToken async => _access;

  @override
  Future<String?> get refreshToken async => _refresh;

  @override
  Future<AuthUser?> readUser() async => null;

  @override
  Future<void> save(AuthSession session) async {
    saves++;
    _access = session.accessToken;
    _refresh = session.refreshToken;
  }

  @override
  Future<void> clear() async {
    clears++;
    _access = null;
    _refresh = null;
  }
}

/// Routes canned responses by request, recording how many times /auth/refresh
/// was hit (to prove single-flight).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Yield so concurrent in-flight requests all reach here before any of their
    // responses are processed — exercising the single-flight path realistically.
    await Future<void>.delayed(Duration.zero);
    return handler(options);
  }
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

Dio _dio(HttpClientAdapter adapter) => Dio(
      BaseOptions(
        baseUrl: 'http://test.local',
        validateStatus: (s) => s != null && s < 500,
        contentType: 'application/json',
      ),
    )..httpClientAdapter = adapter;

void main() {
  group('ApiClient 401 auto-refresh', () {
    test('a burst of concurrent 401s triggers exactly one refresh, then all '
        'requests succeed on the new token', () async {
      var refreshCalls = 0;

      final adapter = _FakeAdapter((options) {
        final auth = options.headers['Authorization'];
        if (options.path.contains(ApiConfig.refreshPath)) {
          refreshCalls++;
          return _json({
            'accessToken': 'new-access',
            'refreshToken': 'new-refresh',
            'id': 'u1',
            'email': 'op@valet.demo',
            'role': 'valet',
          }, 200);
        }
        // The protected core call: stale token → 401, fresh token → 200.
        if (auth == 'Bearer new-access') {
          return _json(<dynamic>[], 200);
        }
        return _json({'message': 'expired'}, 401);
      });

      final store = _FakeTokenStore(access: 'old-access', refresh: 'old-refresh');
      var bounced = 0;
      final client = ApiClient(
        store,
        authDio: _dio(adapter),
        coreDio: _dio(adapter),
      )..onUnauthorized = () => bounced++;

      // Fire several protected reads concurrently — each will 401 first.
      final results = await Future.wait([
        client.fetchTransactions(),
        client.fetchTransactions(),
        client.fetchTransactions(),
        client.fetchTransactions(),
      ]);

      expect(refreshCalls, 1, reason: 'single-flight: exactly one refresh');
      expect(store.saves, 1, reason: 'fresh session saved once');
      expect(bounced, 0, reason: 'a successful refresh must not bounce to login');
      for (final r in results) {
        expect(r, isEmpty); // all retried successfully on the new token
      }
    });

    test('a failed refresh (dead refresh token) bounces to login exactly once '
        'and surfaces an unauthorized error', () async {
      var refreshCalls = 0;
      final adapter = _FakeAdapter((options) {
        if (options.path.contains(ApiConfig.refreshPath)) {
          refreshCalls++;
          return _json({'message': 'invalid refresh token'}, 401);
        }
        return _json({'message': 'expired'}, 401);
      });

      final store = _FakeTokenStore(access: 'old-access', refresh: 'dead');
      var bounced = 0;
      final client = ApiClient(
        store,
        authDio: _dio(adapter),
        coreDio: _dio(adapter),
      )..onUnauthorized = () => bounced++;

      await expectLater(
        client.fetchTransactions(),
        throwsA(isA<ApiException>()
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );

      expect(refreshCalls, 1);
      expect(bounced, 1, reason: 'a dead refresh hard-clears / bounces');
    });

    test('no refresh token → no refresh attempt, straight to bounce', () async {
      var refreshCalls = 0;
      final adapter = _FakeAdapter((options) {
        if (options.path.contains(ApiConfig.refreshPath)) {
          refreshCalls++;
          return _json({}, 200);
        }
        return _json({'message': 'expired'}, 401);
      });

      final store = _FakeTokenStore(access: 'old-access', refresh: null);
      var bounced = 0;
      final client = ApiClient(
        store,
        authDio: _dio(adapter),
        coreDio: _dio(adapter),
      )..onUnauthorized = () => bounced++;

      await expectLater(
        client.fetchTransactions(),
        throwsA(isA<ApiException>()),
      );
      expect(refreshCalls, 0, reason: 'no refresh token → never calls /refresh');
      expect(bounced, 1);
    });
  });
}
