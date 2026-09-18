import '../utils/date_format.dart';

/// Espejo de `CategoriaRegistro` en el backend.
enum CategoriaRegistroDto {
  desarrollo('DESARROLLO'),
  reunion('REUNION'),
  soporte('SOPORTE'),
  documentacion('DOCUMENTACION'),
  otro('OTRO');

  const CategoriaRegistroDto(this.valor);

  final String valor;

  static CategoriaRegistroDto? fromJson(String? valor) =>
      valor == null ? null : values.firstWhere((c) => c.valor == valor);
}

/// Espejo de `OrigenRegistro` en el backend.
enum OrigenRegistroDto {
  manual('MANUAL'),
  timer('TIMER');

  const OrigenRegistroDto(this.valor);

  final String valor;

  static OrigenRegistroDto fromJson(String valor) =>
      values.firstWhere((o) => o.valor == valor);
}

/// Espejo de `RegistroHoraResponse` (backend).
class RegistroHoraDto {
  const RegistroHoraDto({
    required this.id,
    required this.proyectoId,
    required this.proyectoNombre,
    required this.fecha,
    required this.horas,
    required this.descripcion,
    required this.categoria,
    required this.origen,
    required this.horaInicio,
    required this.horaFin,
    required this.enCurso,
  });

  final String id;
  final String proyectoId;
  final String? proyectoNombre;
  final DateTime fecha;
  final num horas;
  final String descripcion;
  final CategoriaRegistroDto? categoria;
  final OrigenRegistroDto origen;
  final DateTime? horaInicio;
  final DateTime? horaFin;
  final bool enCurso;

  factory RegistroHoraDto.fromJson(Map<String, dynamic> json) {
    return RegistroHoraDto(
      id: json['id'] as String,
      proyectoId: json['proyectoId'] as String,
      proyectoNombre: json['proyectoNombre'] as String?,
      fecha: DateTime.parse(json['fecha'] as String),
      horas: json['horas'] as num,
      descripcion: json['descripcion'] as String,
      categoria: CategoriaRegistroDto.fromJson(json['categoria'] as String?),
      origen: OrigenRegistroDto.fromJson(json['origen'] as String),
      horaInicio: json['horaInicio'] == null
          ? null
          : DateTime.parse(json['horaInicio'] as String),
      horaFin: json['horaFin'] == null
          ? null
          : DateTime.parse(json['horaFin'] as String),
      enCurso: json['enCurso'] as bool,
    );
  }
}

/// Espejo de `IniciarTimerRequest` (backend).
class IniciarTimerRequestDto {
  const IniciarTimerRequestDto({required this.proyectoId, required this.descripcion});

  final String proyectoId;
  final String descripcion;

  Map<String, dynamic> toJson() => {
        'proyectoId': proyectoId,
        'descripcion': descripcion,
      };
}

/// Espejo de `RegistroManualRequest` (backend). `fecha` va como `yyyy-MM-dd`.
class RegistroManualRequestDto {
  const RegistroManualRequestDto({
    required this.proyectoId,
    required this.fecha,
    required this.horas,
    required this.descripcion,
    this.categoria,
  });

  final String proyectoId;
  final DateTime fecha;
  final num horas;
  final String descripcion;
  final CategoriaRegistroDto? categoria;

  Map<String, dynamic> toJson() => {
        'proyectoId': proyectoId,
        'fecha': toIsoDate(fecha),
        'horas': horas,
        'descripcion': descripcion,
        'categoria': categoria?.valor,
      };
}

/// Espejo de `ActualizarRegistroRequest` (backend).
class ActualizarRegistroRequestDto {
  const ActualizarRegistroRequestDto({
    required this.descripcion,
    this.categoria,
    this.horas,
  });

  final String descripcion;
  final CategoriaRegistroDto? categoria;
  final num? horas;

  Map<String, dynamic> toJson() => {
        'descripcion': descripcion,
        'categoria': categoria?.valor,
        'horas': horas,
      };
}
