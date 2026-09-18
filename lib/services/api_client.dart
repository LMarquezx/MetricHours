import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../config/dev_session.dart';
import 'log_service.dart';

/// Error de una llamada al API de BackMetric.
///
/// `statusCode == 0` significa que la peticion nunca llego a obtener una
/// respuesta HTTP (sin conexion, tiempo de espera agotado, host
/// inalcanzable); en otro caso es el codigo que respondio el servidor y
/// [message] viene del campo "error" (o "detalles") que arma
/// `GlobalExceptionHandler` en el backend.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get esErrorDeConexion => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Envoltorio delgado sobre `package:http` que centraliza la base URL, los
/// headers, el manejo de errores y el logueo (via [LogService]) de todas las
/// llamadas al backend -- clave para diagnosticar, en un dispositivo fisico
/// sin debugger conectado, si algo no llego a guardarse porque el servidor
/// no respondio.
///
/// El header `X-Usuario-Id` es temporal (ver [DevSession]): lo exige
/// `HeaderCurrentUserProvider` mientras no hay login con Google.
class ApiClient {
  ApiClient({http.Client? httpClient, this.timeout = const Duration(seconds: 10)})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Duration timeout;

  Map<String, String> get _headers => const {
        'Content-Type': 'application/json',
        'X-Usuario-Id': DevSession.usuarioId,
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    if (!ApiConfig.hasBaseUrl) {
      throw ApiException(
        0,
        'El servidor aun no esta configurado. Usa el modo local o define API_BASE_URL.',
      );
    }
    return Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _request('GET', _uri(path, query));

  Future<dynamic> post(String path, {Object? body}) => _request('POST', _uri(path), body: body);

  Future<dynamic> put(String path, {Object? body}) => _request('PUT', _uri(path), body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _request('PATCH', _uri(path), body: body);

  Future<void> delete(String path) => _request('DELETE', _uri(path));

  Future<dynamic> _request(String method, Uri uri, {Object? body}) async {
    await LogService.log(
      'API -> $method $uri${body == null ? '' : '\n  body: ${jsonEncode(body)}'}',
    );

    final http.Response response;
    try {
      response = await _send(method, uri, body).timeout(timeout);
    } on TimeoutException {
      await LogService.log(
        'API !! TIMEOUT $method $uri (>${timeout.inSeconds}s). '
        'Revisa la conexion y que API_BASE_URL apunte al servidor correcto.',
      );
      throw ApiException(
        0,
        'No se pudo conectar con el servidor (tiempo de espera agotado). '
        'Revisa tu conexion WiFi.',
      );
    } on SocketException catch (error) {
      await LogService.log('API !! SIN CONEXION $method $uri -> $error');
      throw ApiException(0, 'No se pudo conectar con el servidor. Revisa tu conexion.');
    } on http.ClientException catch (error) {
      await LogService.log('API !! ERROR DE CLIENTE $method $uri -> $error');
      throw ApiException(0, 'No se pudo conectar con el servidor: ${error.message}');
    }

    await LogService.log('API <- ${response.statusCode} $method $uri');
    return _decode(response, method, uri);
  }

  Future<http.Response> _send(String method, Uri uri, Object? body) async {
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }
    final streamed = await _httpClient.send(request);
    return http.Response.fromStream(streamed);
  }

  dynamic _decode(http.Response response, String method, Uri uri) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;

    if (response.bodyBytes.isEmpty) {
      if (isSuccess) return null;
      unawaited(LogService.log('API !! ${response.statusCode} $method $uri -> (sin cuerpo)'));
      throw ApiException(response.statusCode, 'Error del servidor (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (isSuccess) return decoded;

    final mensaje = _mensajeDeError(decoded);
    unawaited(LogService.log('API !! ${response.statusCode} $method $uri -> $mensaje'));
    throw ApiException(response.statusCode, mensaje);
  }

  String _mensajeDeError(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return decoded.toString();

    final detalles = decoded['detalles'];
    if (detalles is Map && detalles.isNotEmpty) {
      return detalles.values.join('\n');
    }
    return decoded['error'] as String? ?? 'Error desconocido';
  }
}
