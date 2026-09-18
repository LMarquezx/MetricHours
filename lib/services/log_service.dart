import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Escribe cada linea de log a un archivo local y lo sincroniza con la
/// carpeta de Descargas del dispositivo (via MediaStore en Android 10+).
///
/// Se usa tanto para errores no capturados (`main.dart`) como para el
/// trafico del cliente HTTP (`ApiClient`), asi se puede diagnosticar un
/// problema de conexion en un dispositivo fisico sin un debugger conectado:
/// basta con revisar Descargas/metric_hours_log.txt en el celular.
class LogService {
  LogService._();

  static const _channel = MethodChannel('metric_hours/log_writer');
  static const _fileName = 'metric_hours_log.txt';
  static final StringBuffer _buffer = StringBuffer();
  static File? _localFile;

  static Future<void> log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message';
    debugPrint(line);
    _buffer.writeln(line);

    try {
      _localFile ??= await _resolveLocalFile();
      await _localFile!.writeAsString(_buffer.toString(), flush: true);
    } catch (error) {
      debugPrint('LogService: fallo al escribir log local -> $error');
    }

    try {
      final savedAt = await _channel.invokeMethod<String>('writeLog', {
        'fileName': _fileName,
        'content': _buffer.toString(),
      });
      debugPrint('LogService: log sincronizado en $savedAt');
    } catch (error) {
      debugPrint('LogService: fallo al escribir en Descargas -> $error');
    }
  }

  static Future<File> _resolveLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}
