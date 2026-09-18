/// Configuracion de conexion al backend BackMetric.
///
/// La app local no necesita servidor. Cuando se reactive la sincronizacion
/// con login de Google, define la URL con:
///
/// `flutter run --dart-define=API_BASE_URL=https://tu-servidor`
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get hasBaseUrl => baseUrl.trim().isNotEmpty;
}
