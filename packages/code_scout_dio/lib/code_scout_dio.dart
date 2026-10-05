import 'package:code_scout/code_scout.dart';
import 'package:dio/dio.dart';

export 'package:code_scout/code_scout.dart' show NetworkManager;

/// The key in [RequestOptions.extra] under which [CodeScoutDioInterceptor]
/// keeps the id it gave a call.
///
/// Read the id with `codeScoutRequestId` on a [Response], a [DioException] or
/// a [RequestOptions] rather than from the map.
const String codeScoutRequestIdKey = 'codescout_request_id';

/// A Dio [Interceptor] that automatically captures network requests, responses,
/// and errors for CodeScout.
///
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(CodeScoutDioInterceptor());
/// ```
class CodeScoutDioInterceptor extends Interceptor {
  /// Says it is here as soon as it is built, before any call has been made.
  ///
  /// The core cannot detect a package that was never constructed, so an app
  /// that forgot the interceptor shows an empty Network tab that looks exactly
  /// like an app making no calls. Registering at construction is what lets the
  /// overlay tell those two apart.
  CodeScoutDioInterceptor() {
    NetworkManager.i.registerIntegration('dio');
  }

  // Capture must never fail the request it observes: every hook does its
  // CodeScout work inside a try/catch and always forwards via handler.next.

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final reqID = NetworkRequestData.newRequestID();
      options.extra[codeScoutRequestIdKey] = reqID;

      NetworkManager.i.processNetworkRequest(NetworkRequestData(
        method: options.method,
        url: options.uri,
        headers: options.headers,
        body: options.data,
        requestID: reqID,
      ));
    } catch (_) {}
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final reqID = response.requestOptions.codeScoutRequestId;
      final statusCode = response.statusCode;
      if (reqID != null && statusCode != null) {
        NetworkManager.i.processNetworkResponse(
          NetworkResponseData(
            statusCode: statusCode,
            headers: response.headers.map,
            body: response.data,
          ),
          reqID,
        );
      }
    } catch (_) {}
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      final reqID = err.requestOptions.codeScoutRequestId;
      if (reqID != null) {
        NetworkManager.i.processNetworkError(
          NetworkErrorData(
            type: err.type.name,
            message: err.message ?? _describe(err.error),
            response: err.response?.data,
            // dio's default validateStatus rejects 4xx and 5xx, so those land
            // here rather than in onResponse. Dropping the code left a dio app
            // unable to tell a 401 from a 504 anywhere.
            statusCode: err.response?.statusCode,
            stackTrace: err.stackTrace,
          ),
          reqID,
        );
      }
    } catch (_) {}
    handler.next(err);
  }

  /// Names an error dio wrapped without a message of its own, such as the
  /// FormatException its JSON transformer throws on a body that is not JSON.
  ///
  /// By its type alone. The error's text is not redacted, and it can quote the
  /// request: dart:io puts a header value it rejects into a FormatException's
  /// message, and a body that outruns its content length into an
  /// HttpException's.
  static String _describe(Object? error) =>
      error == null ? '' : '${error.runtimeType}';
}

/// Reads the id [CodeScoutDioInterceptor] gave a call.
extension CodeScoutRequestIdOnRequestOptions on RequestOptions {
  /// The id the interceptor gave this call, or null when it never saw it.
  String? get codeScoutRequestId {
    // Any interceptor can write to extra, and this is read from an app's own
    // error handling, where a getter that throws would hide the real error.
    final id = extra[codeScoutRequestIdKey];
    return id is String ? id : null;
  }
}

/// Reads the id of the call a [Response] answered.
extension CodeScoutRequestIdOnResponse on Response<dynamic> {
  /// The id of the call this response answered, or null when
  /// [CodeScoutDioInterceptor] never saw it.
  ///
  /// Pass it as `requestId` when you log something about the call, and the log
  /// is shown with the call: in the in-app panel, and on the dashboard under
  /// `request:<id>`.
  ///
  /// ```dart
  /// final response = await dio.get<Map<String, dynamic>>('/v2/cart');
  /// try {
  ///   return Cart.fromJson(response.data!);
  /// } catch (e, st) {
  ///   CodeScout.instance.e('Could not read GET /v2/cart',
  ///       error: e, stackTrace: st, requestId: response.codeScoutRequestId);
  ///   rethrow;
  /// }
  /// ```
  String? get codeScoutRequestId => requestOptions.codeScoutRequestId;
}

/// Reads the id of the call a [DioException] is about.
extension CodeScoutRequestIdOnDioException on DioException {
  /// The id of the call that failed, or null when [CodeScoutDioInterceptor]
  /// never saw it.
  ///
  /// A body that does not fit the type the call asked for, such as a list from
  /// `dio.get<Map<String, dynamic>>`, arrives as one of these too. Dio casts
  /// the body after every interceptor has run, so the call's response was
  /// captured as usual and this id still names it.
  String? get codeScoutRequestId => requestOptions.codeScoutRequestId;
}
