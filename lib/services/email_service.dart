import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'email_settings_service.dart';

/// Envia el reporte exportado por correo via SMTP, usando las credenciales
/// guardadas en [EmailSettings]. Sirve tanto para la tarea automatica
/// nocturna como para el correo de prueba desde Ajustes.
class EmailService {
  Future<void> sendReport({
    required EmailSettings settings,
    required File attachment,
    required String subject,
    required String body,
  }) async {
    final smtpServer = SmtpServer(
      settings.smtpHost,
      port: settings.smtpPort,
      username: settings.smtpUsername,
      password: settings.smtpPassword,
    );

    final message = Message()
      ..from = Address(settings.fromEmail, 'Metric Hours')
      ..recipients.add(settings.toEmail)
      ..subject = subject
      ..text = body
      ..attachments = [FileAttachment(attachment)];

    await send(message, smtpServer);
  }
}
