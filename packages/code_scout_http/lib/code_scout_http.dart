import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:code_scout/code_scout.dart';
import 'package:http/http.dart' as http;

export 'package:code_scout/code_scout.dart' show NetworkManager;

/// The id each request was given, kept against the request object itself.
///
/// [http.BaseRequest] has no field to put it in, and a header would be sent to
/// the server.
final Expando<String> _requestIds = Expando<String>('codeScoutRequestId');

/// An [http.BaseClient] wrapper that automatically captures network requests,
/// responses, and errors for CodeScout.
///
/// ```dart
/// final client = CodeScoutHttpClient(client: http.Client());
/// final response = await client.get(Uri.parse('https://api.example.com/data'));
/// ```
class CodeScoutHttpClient extends http.BaseClient {
  final http.Client _innerClient;

  /// Says it is here as soon as it is built, so an app that never wrapped its
  /// client is told that rather than shown an empty Network tab.
  CodeScoutHttpClient({http.Client? client}) : _innerClient = client ?? http.Client() {
    NetworkManager.i.registerIntegration('http');
  }

  /// Closes the wrapped client, releasing its connection pool.
  ///
  /// `BaseClient.close()` does nothing, so without this a caller following
  /// package:http's own advice — build a client for a unit of work, close it in
  /// a finally — kept every socket the inner client had pooled, for the life of
  /// the process. Wrapping a client silently changed what closing it meant.
  ///
  /// It closes the inner client whether or not the caller supplied it, which is
  /// what RetryClient and the other wrappers in the ecosystem do: a wrapper
  /// owns its inner for lifecycle purposes, and the alternative leaks by
  /// default in the commoner case.
  @override
  void close() {
    _innerClient.close();
    super.close();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final reqID = NetworkRequestData.newRequestID();
    _requestIds[request] = reqID;

    // Capture must never fail the request it observes.
    try {
      NetworkManager.i.processNetworkRequest(_createRequestData(request, reqID));
    } catch (_) {}

    final http.StreamedResponse response;
    try {
      response = await _innerClient.send(request);
    } catch (e, stackTrace) {
      try {
        _processError(e, stackTrace, reqID);
      } catch (_) {}
      rethrow;
    }

    // The body stream is single-subscription: reading it here would hand the
    // caller an already-drained stream. Buffer it, log from the buffer, and
    // return an equivalent response backed by the buffered bytes.
    // ponytail: buffers whole bodies in memory; add a size cap + capture
    // opt-out if large downloads become a real use case.
    final bytes = await response.stream.toBytes();

    try {
      _processResponse(response, bytes, reqID);
    } catch (_) {}

    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      response.statusCode,
      contentLength: bytes.length,
      // The request this client was handed, which is what the id is kept
      // against. The inner client's can be null, as from MockClient, or a copy,
      // as from RetryClient.
      request: request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  NetworkRequestData _createRequestData(
    http.BaseRequest request,
    String reqID,
  ) {
    return NetworkRequestData(
      method: request.method,
      url: request.url,
      headers: request.headers,
      body: _readRequestBody(request),
      requestID: reqID,
    );
  }

  String _readRequestBody(http.BaseRequest request) {
    if (request is http.Request) {
      return request.body;
    }
    if (request is http.MultipartRequest) {
      return '[multipart]';
    }
    return '[streamed-body]';
  }

  void _processResponse(
    http.StreamedResponse response,
    Uint8List bytes,
    String reqID,
  ) {
    NetworkManager.i.processNetworkResponse(
      NetworkResponseData(
        statusCode: response.statusCode,
        headers: response.headers,
        body: utf8.decode(bytes, allowMalformed: true),
        // Measured here, where the whole response is in hand. Anywhere later is
        // after redaction and truncation have rewritten it.
        byteLength: bytes.length,
      ),
      reqID,
    );
  }

  void _processError(
    dynamic error,
    StackTrace stackTrace,
    String reqID,
  ) {
    NetworkManager.i.processNetworkError(
      NetworkErrorData(
        type: error.runtimeType.toString(),
        // Never the error's own text, which is not redacted: dart:io quotes a
        // header value it rejects, and a body that outruns its content length.
        // A socket failure's words carry nothing of the request but its host,
        // and they are all this client has to say why a connection failed.
        message: error is SocketException ? error.message : '',
        stackTrace: stackTrace,
        response: null,
      ),
      reqID,
    );
  }
}

/// Reads the id [CodeScoutHttpClient] gave a request.
extension CodeScoutRequestIdOnBaseRequest on http.BaseRequest {
  /// The id of the call this request made, or null when it was not sent
  /// through a [CodeScoutHttpClient].
  ///
  /// Set before the request goes out, so a request you built yourself can be
  /// named from a `catch` even when no response ever came back.
  String? get codeScoutRequestId => _requestIds[this];
}

/// Reads the id of the call a response answered.
extension CodeScoutRequestIdOnBaseResponse on http.BaseResponse {
  /// The id of the call this response answered, or null when it did not come
  /// through a [CodeScoutHttpClient].
  ///
  /// Pass it as `requestId` when you log something about the call, and the log
  /// is shown with the call: in the in-app panel, and on the dashboard under
  /// `request:<id>`.
  ///
  /// ```dart
  /// final response = await client.get(Uri.parse('https://api.example.com/v2/cart'));
  /// try {
  ///   return Cart.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  /// } catch (e, st) {
  ///   CodeScout.instance.e(
  ///     'Could not read GET /v2/cart',
  ///     error: e is FormatException ? 'FormatException: ${e.message}' : e,
  ///     stackTrace: st,
  ///     requestId: response.codeScoutRequestId,
  ///   );
  ///   rethrow;
  /// }
  /// ```
  ///
  /// The error you log is stored as its text, and redaction never reads it. A
  /// `FormatException` from `jsonDecode` quotes the part of the body where
  /// parsing stopped, so the example logs only its message.
  String? get codeScoutRequestId {
    final request = this.request;
    return request == null ? null : _requestIds[request];
  }
}
