# Metric Hours

Aplicacion Flutter para Android enfocada en registrar actividades por proyecto, medir duraciones y exportar historiales por rango de fechas.

## Funciones incluidas

- Captura de actividad por texto manual.
- Captura por voz a texto con `speech_to_text`.
- Inicio, fin y duracion total por actividad.
- Catalogo de proyectos con alta, baja y reactivacion.
- Filtro diario en la pantalla de registro.
- Reinicio de vista diario a medianoche; las actividades anteriores quedan disponibles en historial local.
- Exportacion CSV por rango de fechas, compartible desde Android.

## Ejecucion

Instala Flutter y ejecuta:

```bash
flutter pub get
flutter run
```

Si Flutter solicita archivos nativos generados, ejecuta:

```bash
flutter create . --platforms android
flutter pub get
flutter run
```

El SDK Flutter no estaba disponible en el entorno donde se creo este proyecto, por lo que la compilacion local queda pendiente.
