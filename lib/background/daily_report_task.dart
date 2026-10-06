import 'package:workmanager/workmanager.dart';

import '../main.dart'
    show ActivityEntry, ExportService, Project, dateKey, dayOnly, formatDate;
import '../services/email_service.dart';
import '../services/email_settings_service.dart';
import '../services/holidays_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/working_days_service.dart';

/// Nombre unico de la tarea de WorkManager que genera y envia el reporte de
/// "hoy" por correo.
const dailyReportTaskName = 'metric_hours_daily_report';

/// Punto de entrada que Android invoca en un isolate sin UI cuando la tarea
/// programada se dispara. Debe quedar como funcion de nivel superior (no un
/// metodo de clase) para que el `@pragma('vm:entry-point')` la mantenga
/// accesible tras el tree-shaking de release.
@pragma('vm:entry-point')
void dailyReportCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final localStorage = LocalStorageService();
    final notifications = NotificationService();

    try {
      final settings = await EmailSettingsService(localStorage).load();
      if (settings.enabled && settings.isConfigured) {
        final today = dayOnly(DateTime.now());
        final todayKey = dateKey(today);

        final storedProjects = await localStorage.readProjects();
        final projects = storedProjects.map(Project.fromDbRow).toList();

        final storedActivities = await localStorage.readActivities();
        final todaysActivities = storedActivities
            .map(ActivityEntry.fromDbRow)
            .where((activity) => dateKey(activity.startAt) == todayKey)
            .toList();

        final inactiveDays = await HolidaysService(localStorage).load();
        final workingWeekdays = await WorkingDaysService(localStorage).load();

        final file = await ExportService().writeXlsx(
          entries: todaysActivities,
          projects: {for (final project in projects) project.id: project},
          start: today,
          end: today,
          inactiveDays: inactiveDays,
          workingWeekdays: workingWeekdays,
        );

        await EmailService().sendReport(
          settings: settings,
          attachment: file,
          subject: 'Metric Hours - Reporte ${formatDate(today)}',
          body:
              'Adjunto el reporte de actividades de hoy (${formatDate(today)}).',
        );
      }
    } catch (error) {
      await notifications.initialize();
      await notifications.showError(
        title: 'No se pudo enviar el reporte diario',
        body: '$error',
      );
    } finally {
      // Se reprograma siempre, incluso si fallo: asi un error puntual (por
      // ejemplo sin internet esa noche) no corta los envios de los dias
      // siguientes.
      await scheduleNextDailyReport();
    }

    return true;
  });
}

/// Registra (o cancela) la proxima ejecucion segun la configuracion guardada.
///
/// Se llama tanto al final de cada ejecucion (para encadenar el dia
/// siguiente) como al guardar Ajustes y al abrir la app, para que la
/// programacion se recupere sola si la cadena se llegara a romper (por
/// ejemplo si Android mata la tarea antes de que corra ni una vez).
Future<void> scheduleNextDailyReport() async {
  final settings = await EmailSettingsService(LocalStorageService()).load();

  if (!settings.enabled) {
    await Workmanager().cancelByUniqueName(dailyReportTaskName);
    return;
  }

  await Workmanager().registerOneOffTask(
    dailyReportTaskName,
    dailyReportTaskName,
    initialDelay: _delayUntilNext(settings.hour, settings.minute),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

Duration _delayUntilNext(int hour, int minute) {
  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }
  return next.difference(now);
}
