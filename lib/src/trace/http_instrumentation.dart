// Licensed under the Apache License, Version 2.0
// Copyright 2025, Michael Bushe, All rights reserved.

import 'dart:async';
import 'dart:convert';

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:flutterrific_opentelemetry/flutterrific_opentelemetry.dart';
import 'package:http/http.dart' as http;

/// HTTP instrumentation that creates OpenTelemetry spans for HTTP requests.
///
/// This class wraps the standard `http` package's `Client` and automatically
/// creates child spans for HTTP requests. The spans follow OpenTelemetry HTTP
/// semantic conventions and are automatically attached to the currently active
/// span (e.g., a `fetch_data` span).
///
/// Example usage:
/// ```dart
/// final client = InstrumentedHttpClient();
/// final response = await client.get(Uri.parse('https://api.example.com/data'));
/// ```
///
/// The HTTP request will be instrumented as a child span of the active span
/// with proper semantic conventions:
/// - `http.method`: GET, POST, etc.
/// - `http.url`: Full URL
/// - `http.scheme`: http or https
/// - `http.host`: Host name
/// - `http.target`: Path and query string
/// - `http.status_code`: Response status code
class InstrumentedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final UITracer _tracer;

  /// Creates an instrumented HTTP client.
  ///
  /// [inner] is the underlying HTTP client to use. If not provided, a new
  /// [http.Client] will be created.
  InstrumentedHttpClient({http.Client? inner})
      : _inner = inner ?? http.Client(),
        _tracer = FlutterOTel.tracer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Create a child span for the HTTP request
    // The span will automatically be a child of the active span (e.g., fetch_data)
    // if one exists, otherwise it will be a root span
    // By not passing parentSpan, startSpan will use the current context
    final span = _tracer.startSpan(
      'HTTP ${request.method}',
      kind: SpanKind.client,
      // Don't pass parentSpan - let it inherit from current context
      // This ensures HTTP spans are children of active spans like fetch_data
      attributes: _buildRequestAttributes(request),
    );

    try {
      // Send the request
      final response = await _inner.send(request);

      // Update span with response attributes
      span.addAttributes(_buildResponseAttributes(response));

      // Set span status based on HTTP status code
      if (response.statusCode >= 400) {
        span.setStatus(
          SpanStatusCode.Error,
          'HTTP ${response.statusCode}',
        );
      } else {
        span.setStatus(SpanStatusCode.Ok);
      }

      // Wrap the response stream to ensure the span doesn't end until
      // the body is fully consumed. This ensures accurate timing.
      return _wrapStreamedResponse(response, span);
    } catch (e, stackTrace) {
      // Record exception in span
      span.recordException(e, stackTrace: stackTrace);
      span.setStatus(SpanStatusCode.Error, e.toString());
      span.end();
      rethrow;
    }
  }

  /// Wraps a StreamedResponse to ensure the span ends only after the body is consumed.
  http.StreamedResponse _wrapStreamedResponse(
    http.StreamedResponse response,
    Span span,
  ) {
    // Create a controller to wrap the original stream
    final controller = StreamController<List<int>>();
    bool spanEnded = false;
    StreamSubscription<List<int>>? subscription;

    // Listen to the original stream and forward data
    subscription = response.stream.listen(
      (data) {
        controller.add(data);
      },
      onError: (error, stackTrace) {
        if (!spanEnded) {
          span.recordException(error, stackTrace: stackTrace);
          span.setStatus(SpanStatusCode.Error, error.toString());
          spanEnded = true;
          span.end();
        }
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!spanEnded) {
          spanEnded = true;
          span.end();
        }
        if (!controller.isClosed) {
          controller.close();
        }
      },
      cancelOnError: false,
    );

    // Handle controller close to cancel subscription if needed
    controller.onCancel = () {
      subscription?.cancel();
      if (!spanEnded) {
        spanEnded = true;
        span.setStatus(SpanStatusCode.Error, 'Stream cancelled');
        span.end();
      }
    };

    // Return a new StreamedResponse with the wrapped stream
    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
    );
  }

  /// Builds OpenTelemetry attributes for an HTTP request.
  Attributes _buildRequestAttributes(http.BaseRequest request) {
    final uri = request.url;
    final attributes = <String, Object>{
      'http.method': request.method,
      'http.url': uri.toString(),
      'http.scheme': uri.scheme,
      'http.host': uri.host,
      if (uri.hasPort) 'http.port': uri.port,
      'http.target': uri.path + (uri.hasQuery ? '?${uri.query}' : ''),
    };

    // Add request headers if available
    if (request.headers.isNotEmpty) {
      // Add user-agent if present
      if (request.headers.containsKey('user-agent')) {
        attributes['http.user_agent'] = request.headers['user-agent']!;
      }
    }

    // Add request body size if available
    if (request is http.Request && request.body.isNotEmpty) {
      attributes['http.request.body.size'] = request.body.length;
    }

    return attributes.toAttributes();
  }

  /// Builds OpenTelemetry attributes for an HTTP response.
  Attributes _buildResponseAttributes(http.StreamedResponse response) {
    final attributes = <String, Object>{
      'http.status_code': response.statusCode,
      if (response.reasonPhrase != null)
        'http.status_text': response.reasonPhrase!,
    };

    // Add response headers if available
    if (response.headers.isNotEmpty) {
      // Add content-length if present
      if (response.headers.containsKey('content-length')) {
        final contentLength =
            int.tryParse(response.headers['content-length'] ?? '');
        if (contentLength != null) {
          attributes['http.response.body.size'] = contentLength;
        }
      }
    }

    return attributes.toAttributes();
  }

  @override
  void close() {
    _inner.close();
  }
}

/// Extension methods for convenient HTTP request instrumentation.
///
/// These methods wrap the standard `http` package methods and automatically
/// create child spans for HTTP requests.
extension InstrumentedHttpClientExtension on http.Client {
  /// Creates an instrumented HTTP client that wraps this client.
  InstrumentedHttpClient instrumented() {
    return InstrumentedHttpClient(inner: this);
  }
}

/// Convenience methods for making instrumented HTTP requests.
///
/// These are drop-in replacements for the standard `http` package methods
/// that automatically create OpenTelemetry spans.
class InstrumentedHttp {
  static final InstrumentedHttpClient _client = InstrumentedHttpClient();

  /// Sends an HTTP GET request and creates an OpenTelemetry span.
  ///
  /// This is a drop-in replacement for `http.get()` that automatically
  /// instruments the request as a child span of the active span.
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final request = http.Request('GET', url);
    if (headers != null) {
      request.headers.addAll(headers);
    }
    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }

  /// Sends an HTTP POST request and creates an OpenTelemetry span.
  ///
  /// This is a drop-in replacement for `http.post()` that automatically
  /// instruments the request as a child span of the active span.
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final request = http.Request('POST', url);
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List<int>) {
        request.bodyBytes = body;
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      }
    }
    if (encoding != null) {
      request.encoding = encoding;
    }
    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }

  /// Sends an HTTP PUT request and creates an OpenTelemetry span.
  ///
  /// This is a drop-in replacement for `http.put()` that automatically
  /// instruments the request as a child span of the active span.
  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final request = http.Request('PUT', url);
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List<int>) {
        request.bodyBytes = body;
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      }
    }
    if (encoding != null) {
      request.encoding = encoding;
    }
    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }

  /// Sends an HTTP PATCH request and creates an OpenTelemetry span.
  ///
  /// This is a drop-in replacement for `http.patch()` that automatically
  /// instruments the request as a child span of the active span.
  static Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final request = http.Request('PATCH', url);
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List<int>) {
        request.bodyBytes = body;
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      }
    }
    if (encoding != null) {
      request.encoding = encoding;
    }
    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }

  /// Sends an HTTP DELETE request and creates an OpenTelemetry span.
  ///
  /// This is a drop-in replacement for `http.delete()` that automatically
  /// instruments the request as a child span of the active span.
  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final request = http.Request('DELETE', url);
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List<int>) {
        request.bodyBytes = body;
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      }
    }
    if (encoding != null) {
      request.encoding = encoding;
    }
    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }

  /// Sends an HTTP HEAD request and creates an OpenTelemetry span.
  ///
  /// This is a drop-in replacement for `http.head()` that automatically
  /// instruments the request as a child span of the active span.
  static Future<http.Response> head(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final request = http.Request('HEAD', url);
    if (headers != null) {
      request.headers.addAll(headers);
    }
    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }
}
