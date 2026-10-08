import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config_service.dart';

/// API response wrapper for consistent handling
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final int? statusCode;
  final int? responseTimeMs;

  ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.statusCode,
    this.responseTimeMs,
  });

  @override
  String toString() =>
      'ApiResponse(success: $success, statusCode: $statusCode, responseTime: ${responseTimeMs}ms)';
}

/// Base API service with standardized error handling, retry logic, and logging
abstract class ApiService {
  final String baseUrl = ConfigService().backendUrl;
  String? _accessToken;
  String? _refreshToken;
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(milliseconds: 500);
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Get current access token
  String? get accessToken => _accessToken;

  /// Initialize service with existing tokens (called on app startup)
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString('access_token');
      _refreshToken = prefs.getString('refresh_token');
      debugPrint(
          '🔐 ApiService initialized with token: ${_accessToken != null ? 'present' : 'missing'}');
    } catch (e) {
      debugPrint('⚠️ ApiService initialization error: $e');
    }
  }

  /// Set tokens (called after login)
  Future<void> setTokens(String accessToken, {String? refreshToken}) async {
    try {
      _accessToken = accessToken;
      if (refreshToken != null) _refreshToken = refreshToken;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', accessToken);
      if (refreshToken != null) {
        await prefs.setString('refresh_token', refreshToken);
      }
      debugPrint('🔐 Tokens saved successfully');
    } catch (e) {
      debugPrint('❌ Error saving tokens: $e');
    }
  }

  /// Clear tokens (called on logout)
  Future<void> clearTokens() async {
    try {
      _accessToken = null;
      _refreshToken = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      debugPrint('🔐 Tokens cleared on logout');
    } catch (e) {
      debugPrint('❌ Error clearing tokens: $e');
    }
  }

  /// Build headers with auth token
  Map<String, String> _buildHeaders({bool json = true}) {
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  /// Extract error message from various response formats
  String _extractErrorMessage(dynamic data, String defaultMsg) {
    if (data == null) return defaultMsg;
    if (data is String) return data;
    if (data is Map) {
      // Try 'detail' first (FastAPI standard)
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final firstError = detail.first;
        if (firstError is Map && firstError['msg'] != null) {
          return firstError['msg'].toString();
        }
        return firstError.toString();
      }
      // Try other common fields
      if (data['message'] is String) return data['message'];
      if (data['error'] is String) return data['error'];
    }
    return defaultMsg;
  }

  /// Make GET request with retry logic
  Future<ApiResponse<T>> getRequest<T>(
    String endpoint, {
    required T Function(dynamic) parser,
    Map<String, String>? queryParams,
  }) async {
    return _makeRequestWithRetry(
      method: 'GET',
      endpoint: endpoint,
      parser: parser,
      queryParams: queryParams,
    );
  }

  /// Make POST request with retry logic
  Future<ApiResponse<T>> postRequest<T>(
    String endpoint, {
    required T Function(dynamic) parser,
    Map<String, dynamic>? body,
  }) async {
    return _makeRequestWithRetry(
      method: 'POST',
      endpoint: endpoint,
      parser: parser,
      body: body,
    );
  }

  /// Make PATCH request
  Future<ApiResponse<T>> patchRequest<T>(
    String endpoint, {
    required T Function(dynamic) parser,
    Map<String, dynamic>? body,
  }) async {
    return _makeRequestWithRetry(
      method: 'PATCH',
      endpoint: endpoint,
      parser: parser,
      body: body,
    );
  }

  /// Make DELETE request
  Future<ApiResponse<T>> deleteRequest<T>(
    String endpoint, {
    required T Function(dynamic) parser,
  }) async {
    return _makeRequestWithRetry(
      method: 'DELETE',
      endpoint: endpoint,
      parser: parser,
    );
  }

  /// Internal method with retry logic
  Future<ApiResponse<T>> _makeRequestWithRetry<T>({
    required String method,
    required String endpoint,
    required T Function(dynamic) parser,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    int retryCount = 0,
  }) async {
    try {
      final uri =
          Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);
      final headers = _buildHeaders();

      debugPrint('📤 [$method] $endpoint (retry: $retryCount)');
      final startTime = DateTime.now();

      http.Response response;

      switch (method) {
        case 'GET':
          response =
              await http.get(uri, headers: headers).timeout(requestTimeout);
        case 'POST':
          response = await http
              .post(
                uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(requestTimeout);
        case 'PATCH':
          response = await http
              .patch(
                uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(requestTimeout);
        case 'DELETE':
          response =
              await http.delete(uri, headers: headers).timeout(requestTimeout);
        default:
          throw Exception('Unsupported method: $method');
      }

      final responseTimeMs =
          DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
          '📥 [$method] $endpoint → ${response.statusCode} (${responseTimeMs}ms)');

      // Handle 401 - try token refresh
      if (response.statusCode == 401 && retryCount < 1) {
        debugPrint('⚠️ Token expired, attempting refresh...');
        // Token refresh would happen in auth service, for now just fail
        return ApiResponse(
          success: false,
          error: 'Authentication failed. Please login again.',
          statusCode: 401,
          responseTimeMs: responseTimeMs,
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        dynamic data;
        try {
          data = response.body.isEmpty ? null : jsonDecode(response.body);
        } catch (e) {
          data = response.body;
        }

        return ApiResponse(
          success: true,
          data: parser(data),
          statusCode: response.statusCode,
          responseTimeMs: responseTimeMs,
        );
      } else {
        dynamic errorData;
        try {
          errorData = response.body.isEmpty ? null : jsonDecode(response.body);
        } catch (e) {
          errorData = response.body;
        }

        final errorMsg = _extractErrorMessage(
          errorData,
          'Request failed with status ${response.statusCode}',
        );

        return ApiResponse(
          success: false,
          error: errorMsg,
          statusCode: response.statusCode,
          responseTimeMs: responseTimeMs,
        );
      }
    } on TimeoutException {
      debugPrint('⏱️ Request timeout after $requestTimeout');

      if (retryCount < maxRetries) {
        await Future.delayed(retryDelay * (retryCount + 1));
        return _makeRequestWithRetry(
          method: method,
          endpoint: endpoint,
          parser: parser,
          body: body,
          queryParams: queryParams,
          retryCount: retryCount + 1,
        );
      }

      return ApiResponse(
        success: false,
        error: 'Request timeout. Please check your connection.',
      );
    } catch (e) {
      debugPrint('❌ Request error: $e');

      if (retryCount < maxRetries) {
        await Future.delayed(retryDelay * (retryCount + 1));
        return _makeRequestWithRetry(
          method: method,
          endpoint: endpoint,
          parser: parser,
          body: body,
          queryParams: queryParams,
          retryCount: retryCount + 1,
        );
      }

      return ApiResponse(
        success: false,
        error: 'Network error: ${e.toString()}',
      );
    }
  }
}
