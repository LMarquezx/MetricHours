import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificacion persistente en la barra de Android que refleja la actividad
/// que esta corriendo (o en pausa), para poder verla sin abrir la app.
///
/// No usa un foreground service: mientras el proceso de la app siga vivo la
/// notificacion se mantiene actualizada, pero si Android mata el proceso por
/// completo (por ejemplo tras deslizarla fuera de "Recientes" en algunos
/// fabricantes) la notificacion puede desaparecer junto con el.
class NotificationService {
  static const _channelId = 'metric_hours_running';
  static const _channelName = 'Actividad en curso';
  static const _channelDescription =
      'Muestra la actividad que esta corriendo o en pausa.';
  static const _notificationId = 1001;

  static const _errorChannelId = 'metric_hours_errors';
  static const _errorChannelName = 'Avisos de Metric Hours';
  static const _errorChannelDescription =
      'Avisa cuando algo automatico (como el envio diario por correo) falla.';
  static const _errorNotificationId = 1002;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.low,
        showBadge: false,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _errorChannelId,
        _errorChannelName,
        description: _errorChannelDescription,
        importance: Importance.defaultImportance,
      ),
    );

    _initialized = true;
  }

  /// Muestra la notificacion con un cronometro nativo que sigue corriendo
  /// solo (Android lo calcula a partir de [effectiveStart], sin que la app
  /// tenga que reenviar la notificacion cada segundo).
  Future<void> showRunning({
    required String title,
    required String body,
    required DateTime effectiveStart,
  }) async {
    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          usesChronometer: true,
          when: effectiveStart.millisecondsSinceEpoch,
          category: AndroidNotificationCategory.stopwatch,
        ),
      ),
    );
  }

  /// Muestra la notificacion con texto estatico (usado cuando la actividad
  /// esta en pausa, donde no queremos un cronometro corriendo).
  Future<void> showStatic({required String title, required String body}) async {
    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          category: AndroidNotificationCategory.stopwatch,
        ),
      ),
    );
  }

  Future<void> cancel() => _plugin.cancel(id: _notificationId);

  /// Avisa que algo automatico (el envio diario por correo) fallo. No es
  /// "ongoing": el usuario puede descartarla con un swipe normal.
  Future<void> showError({required String title, required String body}) async {
    await _plugin.show(
      id: _errorNotificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _errorChannelId,
          _errorChannelName,
          channelDescription: _errorChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }
}
