import '../config/api_routes.dart';
import '../models/registro_hora_dto.dart';
import '../utils/date_format.dart';
import 'api_client.dart';

/// Llamadas al `RegistroHoraController` del backend.
class RegistroHoraApiService {
  RegistroHoraApiService(this._client);

  final ApiClient _client;

  Future<List<RegistroHoraDto>> listar({
    required DateTime desde,
    required DateTime hasta,
    String? proyectoId,
  }) async {
    final json = await _client.get(
      ApiRoutes.registrosHoras,
      query: {
        'desde': toIsoDate(desde),
        'hasta': toIsoDate(hasta),
        'proyectoId': ?proyectoId,
      },
    ) as List<dynamic>;
    return json
        .map((item) => RegistroHoraDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// `null` si no hay ninguna actividad en curso (el backend responde 204).
  Future<RegistroHoraDto?> obtenerEnCurso() async {
    final json = await _client.get(ApiRoutes.registroHoraEnCurso);
    if (json == null) return null;
    return RegistroHoraDto.fromJson(json as Map<String, dynamic>);
  }

  Future<RegistroHoraDto> iniciarTimer(IniciarTimerRequestDto request) async {
    final json = await _client.post(ApiRoutes.iniciarTimer, body: request.toJson());
    return RegistroHoraDto.fromJson(json as Map<String, dynamic>);
  }

  Future<RegistroHoraDto> detenerTimer(String id) async {
    final json = await _client.post(ApiRoutes.detenerTimer(id));
    return RegistroHoraDto.fromJson(json as Map<String, dynamic>);
  }

  Future<RegistroHoraDto> crearManual(RegistroManualRequestDto request) async {
    final json = await _client.post(ApiRoutes.registroManual, body: request.toJson());
    return RegistroHoraDto.fromJson(json as Map<String, dynamic>);
  }

  Future<RegistroHoraDto> actualizar(String id, ActualizarRegistroRequestDto request) async {
    final json = await _client.put(ApiRoutes.registroHora(id), body: request.toJson());
    return RegistroHoraDto.fromJson(json as Map<String, dynamic>);
  }

  Future<void> eliminar(String id) async {
    await _client.delete(ApiRoutes.registroHora(id));
  }
}
