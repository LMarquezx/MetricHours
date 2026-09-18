/// Sesion temporal mientras no existe login con Google.
///
/// El backend identifica al usuario con el header `X-Usuario-Id`
/// (ver `HeaderCurrentUserProvider` en BackMetric) y espera un ObjectId de
/// Mongo valido que exista en la coleccion `usuarios`. Este id corresponde
/// al usuario de desarrollo creado a mano para pruebas locales.
///
/// Cuando se implemente el login con Google, esta constante se reemplaza por
/// el id que devuelva el backend tras autenticar, guardado en la sesion real.
class DevSession {
  DevSession._();

  static const String usuarioId = '000000000000000000000001';
}
