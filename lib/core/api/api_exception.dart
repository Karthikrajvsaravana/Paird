/// Error raised for any failed API call, carrying a user-presentable message.
class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.code = 'error',
    this.fields = const {},
  });

  final String message;
  final int? statusCode;
  final String code;
  final Map<String, dynamic> fields;

  bool get isNetwork => code == 'network_error' || code == 'timeout';
  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;

  /// First error message for a given form field, if the server reported one.
  String? fieldError(String field) {
    final value = fields[field];
    if (value is List && value.isNotEmpty) return value.first.toString();
    if (value is String) return value;
    if (value is Map && value.isNotEmpty) return value.values.first.toString();
    return null;
  }

  factory ApiException.fromResponse(int statusCode, dynamic body) {
    if (body is Map && body['error'] is Map) {
      final error = body['error'] as Map;
      return ApiException(
        statusCode: statusCode,
        code: (error['code'] ?? 'error').toString(),
        message: (error['message'] ?? 'Something went wrong.').toString(),
        fields: error['fields'] is Map ? Map<String, dynamic>.from(error['fields'] as Map) : const {},
      );
    }
    return ApiException(
      statusCode: statusCode,
      message: statusCode >= 500 ? 'The server had a problem. Please try again.' : 'Request failed ($statusCode).',
    );
  }

  @override
  String toString() => message;
}
