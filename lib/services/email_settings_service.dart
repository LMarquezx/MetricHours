import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_storage_service.dart';

/// Configuracion del envio automatico diario del reporte por correo.
///
/// Los campos no sensibles (hora, destino, host, usuario, remitente) viven en
/// la tabla `settings` de SQLite; la contrasena/API key del SMTP se guarda
/// aparte en el almacenamiento seguro del dispositivo.
class EmailSettings {
  const EmailSettings({
    this.enabled = false,
    this.hour = 23,
    this.minute = 0,
    this.toEmail = '',
    this.fromEmail = '',
    this.smtpHost = '',
    this.smtpPort = 587,
    this.smtpUsername = '',
    this.smtpPassword = '',
  });

  final bool enabled;
  final int hour;
  final int minute;
  final String toEmail;
  final String fromEmail;
  final String smtpHost;
  final int smtpPort;
  final String smtpUsername;
  final String smtpPassword;

  /// Hay lo minimo necesario para poder enviar un correo.
  bool get isConfigured =>
      toEmail.isNotEmpty &&
      fromEmail.isNotEmpty &&
      smtpHost.isNotEmpty &&
      smtpUsername.isNotEmpty &&
      smtpPassword.isNotEmpty;

  EmailSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    String? toEmail,
    String? fromEmail,
    String? smtpHost,
    int? smtpPort,
    String? smtpUsername,
    String? smtpPassword,
  }) {
    return EmailSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      toEmail: toEmail ?? this.toEmail,
      fromEmail: fromEmail ?? this.fromEmail,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpUsername: smtpUsername ?? this.smtpUsername,
      smtpPassword: smtpPassword ?? this.smtpPassword,
    );
  }
}

class EmailSettingsService {
  EmailSettingsService(this.localStorage);

  final LocalStorageService localStorage;
  final _secureStorage = const FlutterSecureStorage();

  static const _enabledKey = 'daily_email_enabled';
  static const _hourKey = 'daily_email_hour';
  static const _minuteKey = 'daily_email_minute';
  static const _toEmailKey = 'daily_email_to';
  static const _fromEmailKey = 'daily_email_from';
  static const _hostKey = 'daily_email_smtp_host';
  static const _portKey = 'daily_email_smtp_port';
  static const _usernameKey = 'daily_email_smtp_username';
  static const _passwordSecureKey = 'daily_email_smtp_password';

  Future<EmailSettings> load() async {
    final enabled = await localStorage.readSetting(_enabledKey);
    final hour = await localStorage.readSetting(_hourKey);
    final minute = await localStorage.readSetting(_minuteKey);
    final toEmail = await localStorage.readSetting(_toEmailKey);
    final fromEmail = await localStorage.readSetting(_fromEmailKey);
    final host = await localStorage.readSetting(_hostKey);
    final port = await localStorage.readSetting(_portKey);
    final username = await localStorage.readSetting(_usernameKey);
    final password = await _secureStorage.read(key: _passwordSecureKey);

    const defaults = EmailSettings();
    return EmailSettings(
      enabled: enabled == 'true',
      hour: int.tryParse(hour ?? '') ?? defaults.hour,
      minute: int.tryParse(minute ?? '') ?? defaults.minute,
      toEmail: toEmail ?? defaults.toEmail,
      fromEmail: fromEmail ?? defaults.fromEmail,
      smtpHost: host ?? defaults.smtpHost,
      smtpPort: int.tryParse(port ?? '') ?? defaults.smtpPort,
      smtpUsername: username ?? defaults.smtpUsername,
      smtpPassword: password ?? defaults.smtpPassword,
    );
  }

  Future<void> save(EmailSettings settings) async {
    await localStorage.writeSetting(_enabledKey, settings.enabled.toString());
    await localStorage.writeSetting(_hourKey, settings.hour.toString());
    await localStorage.writeSetting(_minuteKey, settings.minute.toString());
    await localStorage.writeSetting(_toEmailKey, settings.toEmail);
    await localStorage.writeSetting(_fromEmailKey, settings.fromEmail);
    await localStorage.writeSetting(_hostKey, settings.smtpHost);
    await localStorage.writeSetting(_portKey, settings.smtpPort.toString());
    await localStorage.writeSetting(_usernameKey, settings.smtpUsername);
    await _secureStorage.write(
      key: _passwordSecureKey,
      value: settings.smtpPassword,
    );
  }
}
