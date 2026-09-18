/// Rutas del API de BackMetric, en un solo lugar para no repetir strings
/// sueltos por los servicios y para que un cambio en el backend
/// (`@RequestMapping` en los controllers) se refleje aqui una sola vez.
class ApiRoutes {
  ApiRoutes._();

  // ProyectoController -> /api/proyectos
  static const String proyectos = '/api/proyectos';

  static String proyecto(String id) => '$proyectos/$id';

  static String cambiarEstadoProyecto(String id) => '${proyecto(id)}/estado';

  // RegistroHoraController -> /api/registros-horas
  static const String registrosHoras = '/api/registros-horas';

  static String registroHora(String id) => '$registrosHoras/$id';

  static const String registroHoraEnCurso = '$registrosHoras/en-curso';

  static const String iniciarTimer = '$registrosHoras/timer/iniciar';

  static String detenerTimer(String id) => '$registrosHoras/timer/$id/detener';

  static const String registroManual = '$registrosHoras/manual';
}
