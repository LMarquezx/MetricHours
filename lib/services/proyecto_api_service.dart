import '../config/api_routes.dart';
import '../models/proyecto_dto.dart';
import 'api_client.dart';

/// Llamadas al `ProyectoController` del backend.
class ProyectoApiService {
  ProyectoApiService(this._client);

  final ApiClient _client;

  Future<List<ProyectoDto>> listar({EstadoProyectoDto? estado}) async {
    final json = await _client.get(
      ApiRoutes.proyectos,
      query: estado == null ? null : {'estado': estado.valor},
    ) as List<dynamic>;
    return json
        .map((item) => ProyectoDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ProyectoDto> obtener(String id) async {
    final json = await _client.get(ApiRoutes.proyecto(id));
    return ProyectoDto.fromJson(json as Map<String, dynamic>);
  }

  Future<ProyectoDto> crear(ProyectoRequestDto request) async {
    final json = await _client.post(ApiRoutes.proyectos, body: request.toJson());
    return ProyectoDto.fromJson(json as Map<String, dynamic>);
  }

  Future<ProyectoDto> actualizar(String id, ProyectoRequestDto request) async {
    final json = await _client.put(ApiRoutes.proyecto(id), body: request.toJson());
    return ProyectoDto.fromJson(json as Map<String, dynamic>);
  }

  Future<ProyectoDto> cambiarEstado(String id, EstadoProyectoDto estado) async {
    final json = await _client.patch(
      ApiRoutes.cambiarEstadoProyecto(id),
      body: {'estado': estado.valor},
    );
    return ProyectoDto.fromJson(json as Map<String, dynamic>);
  }
}
