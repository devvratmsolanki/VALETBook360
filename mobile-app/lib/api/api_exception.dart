import 'package:dio/dio.dart';

/// A user-facing API failure. Parses RFC7807 problem+json envelopes returned by
/// the backends and the ported `{ code, userMessage, detail }` envelope
/// (doc §10.7), always surfacing a `userMessage`-equivalent to the UI.
class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.detail,
    this.isUnauthorized = false,
    this.isNetwork = false,
  });

  /// Toast-safe message shown to the user.
  final String message;
  final int? statusCode;
  final String? code;
  final String? detail;
  final bool isUnauthorized;
  final bool isNetwork;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';

  /// Build from a dio error, parsing problem+json / userMessage envelopes.
  factory ApiException.fromDio(DioException e) {
    final res = e.response;
    final status = res?.statusCode;

    // Transport-level failures (no response) → friendly offline message.
    if (res == null) {
      final isTimeout = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      return ApiException(
        message: isTimeout
            ? 'The server took too long to respond. Check your connection and try again.'
            : "Can't reach the server. Check your connection and try again.",
        isNetwork: true,
      );
    }

    if (status == 401) {
      return ApiException(
        message: _extractMessage(res.data) ??
            'Your email or password is incorrect.',
        statusCode: 401,
        code: _extractCode(res.data),
        isUnauthorized: true,
      );
    }

    return ApiException(
      message: _extractMessage(res.data) ??
          'Something went wrong (${status ?? '???'}). Please try again.',
      statusCode: status,
      code: _extractCode(res.data),
      detail: _extractDetail(res.data),
    );
  }

  factory ApiException.network() => ApiException(
        message: "Can't reach the server. Check your connection and try again.",
        isNetwork: true,
      );

  /// Public helper for callers that already hold a response body (not a
  /// DioException) and want the user-facing message out of the envelope.
  static String? fromDioData(Object? data) => _extractMessage(data);

  static String? _extractMessage(Object? data) {
    if (data is Map) {
      // ported envelope first, then RFC7807 fields.
      final m = data['userMessage'] ??
          data['title'] ??
          data['message'] ??
          data['error'];
      if (m is String && m.trim().isNotEmpty) return m.trim();
    }
    return null;
  }

  static String? _extractCode(Object? data) {
    if (data is Map) {
      final c = data['code'] ?? data['type'];
      if (c != null) return c.toString();
    }
    return null;
  }

  static String? _extractDetail(Object? data) {
    if (data is Map) {
      final d = data['detail'];
      if (d is String && d.trim().isNotEmpty) return d.trim();
    }
    return null;
  }
}
