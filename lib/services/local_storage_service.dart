import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Almacenamiento privado de Metric Hours en el dispositivo.
///
/// No realiza llamadas de red: el archivo solo se crea dentro del directorio
/// de documentos que Android asigna a esta aplicacion.
class LocalStorageService {
  static const _fileName = 'metric_hours_data.json';

  Future<Map<String, dynamic>> read() async {
    final file = await _file();
    if (!await file.exists()) {
      return const {};
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'El archivo local no tiene un formato valido.',
      );
    }
    return decoded;
  }

  Future<void> write({
    required List<Map<String, dynamic>> projects,
    required List<Map<String, dynamic>> activities,
  }) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode({'projects': projects, 'activities': activities}),
      flush: true,
    );
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}
