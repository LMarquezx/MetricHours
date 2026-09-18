/// Espejo de `EstadoProyecto` en el backend.
enum EstadoProyectoDto {
  activo('ACTIVO'),
  pausado('PAUSADO'),
  finalizado('FINALIZADO');

  const EstadoProyectoDto(this.valor);

  final String valor;

  static EstadoProyectoDto fromJson(String valor) =>
      values.firstWhere((estado) => estado.valor == valor);
}

/// Espejo de `ProyectoResponse` (backend).
class ProyectoDto {
  const ProyectoDto({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.estado,
    required this.color,
    required this.presupuestoHoras,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final String id;
  final String nombre;
  final String? descripcion;
  final EstadoProyectoDto estado;
  final String? color;
  final int? presupuestoHoras;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  factory ProyectoDto.fromJson(Map<String, dynamic> json) {
    return ProyectoDto(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      estado: EstadoProyectoDto.fromJson(json['estado'] as String),
      color: json['color'] as String?,
      presupuestoHoras: json['presupuestoHoras'] as int?,
      fechaCreacion: DateTime.parse(json['fechaCreacion'] as String),
      fechaActualizacion: DateTime.parse(json['fechaActualizacion'] as String),
    );
  }
}

/// Espejo de `ProyectoRequest` (backend): lo que se manda al crear/editar.
class ProyectoRequestDto {
  const ProyectoRequestDto({
    required this.nombre,
    this.descripcion,
    this.color,
    this.presupuestoHoras,
  });

  final String nombre;
  final String? descripcion;
  final String? color;
  final int? presupuestoHoras;

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'descripcion': descripcion,
        'color': color,
        'presupuestoHoras': presupuestoHoras,
      };
}
