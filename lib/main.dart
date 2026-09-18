import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Escribe cada linea de log a un archivo local y lo sincroniza con la
/// carpeta de Descargas del dispositivo (via MediaStore en Android 10+).
class LogService {
  LogService._();

  static const _channel = MethodChannel('metric_hours/log_writer');
  static const _fileName = 'metric_hours_log.txt';
  static final StringBuffer _buffer = StringBuffer();
  static File? _localFile;

  static Future<void> log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message';
    debugPrint(line);
    _buffer.writeln(line);

    try {
      _localFile ??= await _resolveLocalFile();
      await _localFile!.writeAsString(_buffer.toString(), flush: true);
    } catch (error) {
      debugPrint('LogService: fallo al escribir log local -> $error');
    }

    try {
      final savedAt = await _channel.invokeMethod<String>('writeLog', {
        'fileName': _fileName,
        'content': _buffer.toString(),
      });
      debugPrint('LogService: log sincronizado en $savedAt');
    } catch (error) {
      debugPrint('LogService: fallo al escribir en Descargas -> $error');
    }
  }

  static Future<File> _resolveLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(LogService.log('=== FlutterError ===\n'
        '${details.exceptionAsString()}\n'
        '${details.stack}'));
  };
  runZonedGuarded(
    () => runApp(const MetricHoursApp()),
    (error, stack) {
      unawaited(
        LogService.log('=== Uncaught zone error ===\n$error\n$stack'),
      );
    },
  );
}

class MetricHoursApp extends StatefulWidget {
  const MetricHoursApp({super.key});

  @override
  State<MetricHoursApp> createState() => _MetricHoursAppState();
}

class _MetricHoursAppState extends State<MetricHoursApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController(LocalRepository(), ExportService());
    unawaited(controller.load());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF006A60),
      brightness: Brightness.light,
    );

    return AppScope(
      controller: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Metric Hours',
        theme: ThemeData(
          colorScheme: scheme,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF7F8F4),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
        home: const AppShell(),
      ),
    );
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    required AppController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope no encontrado en el arbol de widgets.');
    return scope!.notifier!;
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pages = <Widget>[
      const RegisterPage(),
      const ProjectsPage(),
      const ReportsPage(),
    ];
    final titles = ['Registro', 'Proyectos', 'Informes'];

    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        if (!app.isLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(titles[selectedIndex]),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: RunningBadge(activity: app.runningActivity),
                ),
              ),
            ],
          ),
          body: SafeArea(child: pages[selectedIndex]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              setState(() => selectedIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.timer_outlined),
                selectedIcon: Icon(Icons.timer),
                label: 'Registro',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: 'Proyectos',
              ),
              NavigationDestination(
                icon: Icon(Icons.table_chart_outlined),
                selectedIcon: Icon(Icons.table_chart),
                label: 'Informes',
              ),
            ],
          ),
        );
      },
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final descriptionController = TextEditingController();
  final speech = SpeechToText();
  String? selectedProjectId;
  bool speechReady = false;
  bool speechBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      selectedProjectId = app.activeProjects.firstOrNull?.id;
      setState(() {});
    });
  }

  @override
  void dispose() {
    descriptionController.dispose();
    unawaited(speech.cancel());
    super.dispose();
  }

  Future<void> _toggleSpeech() async {
    if (speech.isListening) {
      await speech.stop();
      setState(() => speechBusy = false);
      return;
    }

    if (!speechReady) {
      speechReady = await speech.initialize(
        onStatus: (status) {
          if (mounted && status == 'done') {
            setState(() => speechBusy = false);
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => speechBusy = false);
            _showMessage(context, 'No se pudo usar el microfono.');
          }
        },
      );
    }

    if (!speechReady) {
      if (mounted) {
        _showMessage(context, 'Reconocimiento de voz no disponible.');
      }
      return;
    }

    setState(() => speechBusy = true);
    await speech.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(localeId: 'es_MX'),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    descriptionController.text = result.recognizedWords;
    descriptionController.selection = TextSelection.fromPosition(
      TextPosition(offset: descriptionController.text.length),
    );
  }

  Future<void> _startActivity(AppController app) async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      _showMessage(context, 'Da de alta un proyecto activo primero.');
      return;
    }

    try {
      await app.startActivity(
        projectId: projectId,
        description: descriptionController.text,
      );
      descriptionController.clear();
      if (!isSameDay(app.selectedDay, DateTime.now())) {
        app.selectDay(DateTime.now());
      }
    } on AppException catch (error) {
      if (mounted) {
        _showMessage(context, error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final activities = app.activitiesForDay(app.selectedDay);
        final activeProjects = app.activeProjects;
        final selectedStillActive = activeProjects.any(
          (project) => project.id == selectedProjectId,
        );
        if (!selectedStillActive) {
          selectedProjectId = activeProjects.firstOrNull?.id;
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            DaySelector(value: app.selectedDay, onChanged: app.selectDay),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedProjectId,
                      items: [
                        for (final project in activeProjects)
                          DropdownMenuItem(
                            value: project.id,
                            child: ProjectName(project: project),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => selectedProjectId = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Proyecto',
                        prefixIcon: Icon(Icons.work_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Actividad',
                        hintText: 'Describe lo que estas haciendo',
                        prefixIcon: const Icon(Icons.edit_note),
                        suffixIcon: IconButton(
                          tooltip: speechBusy ? 'Detener voz' : 'Dictar voz',
                          icon: Icon(
                            speechBusy ? Icons.mic : Icons.mic_none_outlined,
                          ),
                          onPressed: _toggleSpeech,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Iniciar'),
                      onPressed: app.runningActivity == null
                          ? () => _startActivity(app)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            if (app.runningActivity != null) ...[
              const SizedBox(height: 12),
              ActiveActivityPanel(activity: app.runningActivity!),
            ],
            const SizedBox(height: 20),
            Text(
              'Actividades ${formatDate(app.selectedDay)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (activities.isEmpty)
              const EmptyState(
                icon: Icons.event_available_outlined,
                title: 'Sin actividades',
                subtitle: 'El dia seleccionado no tiene registros.',
              )
            else
              for (final activity in activities)
                ActivityTile(
                  activity: activity,
                  project: app.projectById(activity.projectId),
                ),
          ],
        );
      },
    );
  }
}

class ActiveActivityPanel extends StatelessWidget {
  const ActiveActivityPanel({required this.activity, super.key});

  final ActivityEntry activity;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final project = app.projectById(activity.projectId);

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: ProjectName(project: project)),
                Text(durationLabel(activity.effectiveDuration)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              activity.description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.stop),
                label: const Text('Detener'),
                onPressed: () async {
                  await app.stopActivity(activity.id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool showActive = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final projects = app.projects
            .where((project) => project.isActive == showActive)
            .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.check_circle_outline),
                          label: Text('Activos'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.archive_outlined),
                          label: Text('Baja'),
                        ),
                      ],
                      selected: {showActive},
                      onSelectionChanged: (values) {
                        setState(() => showActive = values.first);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Alta de proyecto',
                    icon: const Icon(Icons.add),
                    onPressed: () => _showProjectDialog(context, app),
                  ),
                ],
              ),
            ),
            Expanded(
              child: projects.isEmpty
                  ? const EmptyState(
                      icon: Icons.folder_off_outlined,
                      title: 'Sin proyectos',
                      subtitle:
                          'Agrega un proyecto para registrar actividades.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        final count = app.activityCountForProject(project.id);
                        return Card(
                          child: ListTile(
                            leading: ColorDot(color: Color(project.color)),
                            title: Text(project.name),
                            subtitle: Text('$count actividades registradas'),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                if (project.isActive)
                                  IconButton(
                                    tooltip: 'Dar de baja',
                                    icon: const Icon(Icons.archive_outlined),
                                    onPressed: () async {
                                      try {
                                        await app.setProjectActive(
                                          project.id,
                                          false,
                                        );
                                      } on AppException catch (error) {
                                        if (context.mounted) {
                                          _showMessage(context, error.message);
                                        }
                                      }
                                    },
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Reactivar',
                                    icon: const Icon(Icons.unarchive_outlined),
                                    onPressed: () async {
                                      await app.setProjectActive(
                                        project.id,
                                        true,
                                      );
                                    },
                                  ),
                                IconButton(
                                  tooltip: 'Renombrar',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showProjectDialog(
                                    context,
                                    app,
                                    project: project,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemCount: projects.length,
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showProjectDialog(
    BuildContext context,
    AppController app, {
    Project? project,
  }) async {
    unawaited(
      LogService.log(
        '_showProjectDialog: abriendo (project=${project?.id ?? "nuevo"})',
      ),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return _ProjectNameDialog(
          initialName: project?.name ?? '',
          isRename: project != null,
        );
      },
    );
    await LogService.log('_showProjectDialog: resultado del dialogo = "$result"');

    if (result == null) {
      await LogService.log('_showProjectDialog: cancelado por el usuario');
      return;
    }

    try {
      if (project == null) {
        await LogService.log('_showProjectDialog: llamando addProject("$result")');
        await app.addProject(result);
        await LogService.log('_showProjectDialog: addProject OK');
      } else {
        await LogService.log(
          '_showProjectDialog: llamando renameProject(${project.id}, "$result")',
        );
        await app.renameProject(project.id, result);
        await LogService.log('_showProjectDialog: renameProject OK');
      }
    } on AppException catch (error) {
      await LogService.log('_showProjectDialog: AppException -> ${error.message}');
      if (context.mounted) {
        _showMessage(context, error.message);
      }
    } catch (error, stackTrace) {
      await LogService.log(
        '_showProjectDialog: ERROR no manejado -> $error\n$stackTrace',
      );
      rethrow;
    }
  }
}

class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({required this.initialName, required this.isRename});

  final String initialName;
  final bool isRename;

  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isRename ? 'Renombrar' : 'Alta de proyecto'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          prefixIcon: Icon(Icons.folder_outlined),
        ),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final activities = app.activitiesInRange(
          app.reportStart,
          app.reportEnd,
        );
        final totals = app.projectTotalsFor(activities);
        final totalDuration = activities.fold<Duration>(
          Duration.zero,
          (value, activity) => value + activity.effectiveDuration,
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DateButton(
                            label: 'Desde',
                            value: app.reportStart,
                            onSelected: (date) =>
                                app.setReportRange(date, app.reportEnd),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DateButton(
                            label: 'Hasta',
                            value: app.reportEnd,
                            onSelected: (date) =>
                                app.setReportRange(app.reportStart, date),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SummaryMetric(
                            label: 'Actividades',
                            value: '${activities.length}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SummaryMetric(
                            label: 'Tiempo',
                            value: compactDurationLabel(totalDuration),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Exportar CSV'),
                        onPressed: activities.isEmpty
                            ? null
                            : () async {
                                final file = await app.exportCsv();
                                if (!context.mounted) {
                                  return;
                                }
                                _showMessage(
                                  context,
                                  'Archivo generado: ${file.path}',
                                );
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Resumen por proyecto',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (totals.isEmpty)
              const EmptyState(
                icon: Icons.query_stats_outlined,
                title: 'Sin datos',
                subtitle: 'El rango seleccionado no tiene actividades.',
              )
            else
              for (final item in totals.entries)
                Card(
                  child: ListTile(
                    leading: ColorDot(color: Color(item.key.color)),
                    title: Text(item.key.name),
                    subtitle: Text('${item.value.count} actividades'),
                    trailing: Text(compactDurationLabel(item.value.duration)),
                  ),
                ),
            const SizedBox(height: 20),
            Text('Detalle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final activity in activities)
              ActivityTile(
                activity: activity,
                project: app.projectById(activity.projectId),
              ),
          ],
        );
      },
    );
  }
}

class DaySelector extends StatelessWidget {
  const DaySelector({required this.value, required this.onChanged, super.key});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          tooltip: 'Dia anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(value.subtract(const Duration(days: 1))),
        ),
        Expanded(
          child: DateButton(label: 'Dia', value: value, onSelected: onChanged),
        ),
        IconButton.outlined(
          tooltip: 'Dia siguiente',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(value.add(const Duration(days: 1))),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Hoy',
          icon: const Icon(Icons.today),
          onPressed: () => onChanged(DateTime.now()),
        ),
      ],
    );
  }
}

class DateButton extends StatelessWidget {
  const DateButton({
    required this.label,
    required this.value,
    required this.onSelected,
    super.key,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(formatDate(value)),
        ],
      ),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          onSelected(picked);
        }
      },
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({
    required this.activity,
    required this.project,
    super.key,
  });

  final ActivityEntry activity;
  final Project project;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ProjectName(project: project)),
                Text(
                  compactDurationLabel(activity.effectiveDuration),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              activity.description,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                IconLabel(
                  icon: Icons.login,
                  text:
                      '${formatDate(activity.startAt)} ${formatTime(activity.startAt)}',
                ),
                IconLabel(
                  icon: activity.isRunning ? Icons.pending : Icons.logout,
                  text: activity.endAt == null
                      ? 'En curso'
                      : formatTime(activity.endAt!),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RunningBadge extends StatelessWidget {
  const RunningBadge({required this.activity, super.key});

  final ActivityEntry? activity;

  @override
  Widget build(BuildContext context) {
    if (activity == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 10),
          const SizedBox(width: 6),
          Text(compactDurationLabel(activity!.effectiveDuration)),
        ],
      ),
    );
  }
}

class SummaryMetric extends StatelessWidget {
  const SummaryMetric({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class ProjectName extends StatelessWidget {
  const ProjectName({required this.project, super.key});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorDot(color: Color(project.color)),
        const SizedBox(width: 8),
        Flexible(child: Text(project.name, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class ColorDot extends StatelessWidget {
  const ColorDot({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class IconLabel extends StatelessWidget {
  const IconLabel({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class AppController extends ChangeNotifier {
  AppController(this.repository, this.exportService);

  final LocalRepository repository;
  final ExportService exportService;
  final List<Project> projects = [];
  final List<ActivityEntry> activities = [];
  DateTime selectedDay = dayOnly(DateTime.now());
  DateTime reportStart = dayOnly(DateTime.now());
  DateTime reportEnd = dayOnly(DateTime.now());
  String lastOpenedDayKey = dateKey(DateTime.now());
  bool isLoaded = false;
  Timer? _ticker;
  Timer? _midnightTimer;

  List<Project> get activeProjects =>
      projects.where((project) => project.isActive).toList();

  ActivityEntry? get runningActivity =>
      activities.where((activity) => activity.isRunning).firstOrNull;

  Future<void> load() async {
    final snapshot = await repository.load();
    projects
      ..clear()
      ..addAll(snapshot.projects);
    activities
      ..clear()
      ..addAll(snapshot.activities);
    lastOpenedDayKey = snapshot.lastOpenedDayKey ?? dateKey(DateTime.now());

    if (projects.isEmpty) {
      projects.add(Project.create('Personal', color: projectColors.first));
    }

    _applyDailyRollover(DateTime.now());
    _startTicker();
    _scheduleMidnightRollover();
    isLoaded = true;
    notifyListeners();
    await _save();
  }

  void selectDay(DateTime value) {
    selectedDay = dayOnly(value);
    notifyListeners();
  }

  void setReportRange(DateTime start, DateTime end) {
    var normalizedStart = dayOnly(start);
    var normalizedEnd = dayOnly(end);
    if (normalizedEnd.isBefore(normalizedStart)) {
      final swap = normalizedStart;
      normalizedStart = normalizedEnd;
      normalizedEnd = swap;
    }
    reportStart = normalizedStart;
    reportEnd = normalizedEnd;
    notifyListeners();
  }

  List<ActivityEntry> activitiesForDay(DateTime day) {
    final key = dateKey(day);
    final result =
        activities
            .where((activity) => dateKey(activity.startAt) == key)
            .toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return result;
  }

  List<ActivityEntry> activitiesInRange(DateTime start, DateTime end) {
    final from = dayOnly(start);
    final toExclusive = dayOnly(end).add(const Duration(days: 1));
    final result =
        activities
            .where(
              (activity) =>
                  !activity.startAt.isBefore(from) &&
                  activity.startAt.isBefore(toExclusive),
            )
            .toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return result;
  }

  Project projectById(String id) {
    return projects.firstWhere(
      (project) => project.id == id,
      orElse: () => Project(
        id: id,
        name: 'Proyecto eliminado',
        color: 0xFF777777,
        isActive: false,
        createdAt: DateTime.now(),
      ),
    );
  }

  int activityCountForProject(String projectId) {
    return activities
        .where((activity) => activity.projectId == projectId)
        .length;
  }

  Map<Project, ProjectTotal> projectTotalsFor(List<ActivityEntry> entries) {
    final totals = <String, ProjectTotal>{};
    for (final activity in entries) {
      final current = totals[activity.projectId] ?? ProjectTotal.empty();
      totals[activity.projectId] = ProjectTotal(
        count: current.count + 1,
        duration: current.duration + activity.effectiveDuration,
      );
    }

    final mapped = <Project, ProjectTotal>{};
    for (final entry in totals.entries) {
      mapped[projectById(entry.key)] = entry.value;
    }
    return mapped;
  }

  Future<void> addProject(String rawName) async {
    await LogService.log('AppController.addProject: rawName="$rawName"');
    final name = rawName.trim();
    if (name.isEmpty) {
      throw const AppException('Escribe un nombre de proyecto.');
    }
    final exists = projects.any(
      (project) => project.name.toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      throw const AppException('Ya existe un proyecto con ese nombre.');
    }
    final newProject = Project.create(
      name,
      color: projectColors[projects.length % projectColors.length],
    );
    await LogService.log(
      'AppController.addProject: creado id=${newProject.id} color=${newProject.color}',
    );
    projects.add(newProject);
    notifyListeners();
    await LogService.log('AppController.addProject: notifyListeners() emitido');
    await _save();
    await LogService.log('AppController.addProject: _save() completado');
  }

  Future<void> renameProject(String id, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw const AppException('Escribe un nombre de proyecto.');
    }
    final exists = projects.any(
      (project) =>
          project.id != id && project.name.toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      throw const AppException('Ya existe un proyecto con ese nombre.');
    }
    final index = projects.indexWhere((project) => project.id == id);
    if (index == -1) {
      return;
    }
    projects[index] = projects[index].copyWith(name: name);
    notifyListeners();
    await _save();
  }

  Future<void> setProjectActive(String id, bool isActive) async {
    if (!isActive &&
        activeProjects.length == 1 &&
        activeProjects.first.id == id) {
      throw const AppException('Debe quedar al menos un proyecto activo.');
    }

    final index = projects.indexWhere((project) => project.id == id);
    if (index == -1) {
      return;
    }
    projects[index] = projects[index].copyWith(
      isActive: isActive,
      archivedAt: isActive ? null : DateTime.now(),
      clearArchivedAt: isActive,
    );
    notifyListeners();
    await _save();
  }

  Future<void> startActivity({
    required String projectId,
    required String description,
  }) async {
    final cleanDescription = description.trim();
    if (cleanDescription.isEmpty) {
      throw const AppException('Describe la actividad.');
    }
    final project = projectById(projectId);
    if (!project.isActive) {
      throw const AppException('El proyecto seleccionado no esta activo.');
    }
    if (runningActivity != null) {
      throw const AppException(
        'Deten la actividad actual antes de iniciar otra.',
      );
    }

    activities.add(
      ActivityEntry.create(
        projectId: projectId,
        description: cleanDescription,
        startAt: DateTime.now(),
      ),
    );
    selectedDay = dayOnly(DateTime.now());
    notifyListeners();
    await _save();
  }

  Future<void> stopActivity(String id) async {
    final index = activities.indexWhere((activity) => activity.id == id);
    if (index == -1) {
      return;
    }
    final activity = activities[index];
    if (!activity.isRunning) {
      return;
    }
    activities[index] = activity.copyWith(endAt: DateTime.now());
    notifyListeners();
    await _save();
  }

  Future<File> exportCsv() async {
    final entries = activitiesInRange(reportStart, reportEnd);
    final file = await exportService.writeCsv(
      entries: entries,
      projects: {for (final project in projects) project.id: project},
      start: reportStart,
      end: reportEnd,
    );
    await SharePlus.instance.share(
      ShareParams(
        title: 'Metric Hours CSV',
        text:
            'Historial de actividades ${formatDate(reportStart)} - ${formatDate(reportEnd)}',
        files: [XFile(file.path, mimeType: 'text/csv')],
      ),
    );
    return file;
  }

  void _applyDailyRollover(DateTime now) {
    final todayKey = dateKey(now);
    if (lastOpenedDayKey == todayKey) {
      return;
    }

    final todayMidnight = dayOnly(now);
    for (var index = 0; index < activities.length; index += 1) {
      final activity = activities[index];
      if (activity.isRunning && activity.startAt.isBefore(todayMidnight)) {
        final activityNextMidnight = dayOnly(
          activity.startAt,
        ).add(const Duration(days: 1));
        activities[index] = activity.copyWith(endAt: activityNextMidnight);
      }
    }
    lastOpenedDayKey = todayKey;
    selectedDay = todayMidnight;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (runningActivity != null) {
        notifyListeners();
      }
    });
  }

  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = dayOnly(now).add(const Duration(days: 1));
    final delay =
        nextMidnight.difference(now) + const Duration(milliseconds: 300);
    _midnightTimer = Timer(delay, () {
      _applyDailyRollover(DateTime.now());
      notifyListeners();
      unawaited(_save());
      _scheduleMidnightRollover();
    });
  }

  Future<void> _save() async {
    await repository.save(
      DataSnapshot(
        projects: projects,
        activities: activities,
        lastOpenedDayKey: lastOpenedDayKey,
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _midnightTimer?.cancel();
    super.dispose();
  }
}

class LocalRepository {
  Future<DataSnapshot> load() async {
    final file = await _dataFile();
    if (!await file.exists()) {
      return const DataSnapshot(projects: [], activities: []);
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return const DataSnapshot(projects: [], activities: []);
    }

    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    return DataSnapshot.fromJson(jsonMap);
  }

  Future<void> save(DataSnapshot snapshot) async {
    final file = await _dataFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(snapshot.toJson()));
  }

  Future<File> _dataFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/metric_hours_data.json');
  }
}

class ExportService {
  Future<File> writeCsv({
    required List<ActivityEntry> entries,
    required Map<String, Project> projects,
    required DateTime start,
    required DateTime end,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/metric_hours_${dateKey(start)}_${dateKey(end)}.csv',
    );
    final buffer = StringBuffer()
      ..writeln(
        [
          'Proyecto',
          'Actividad',
          'Fecha inicio',
          'Hora inicio',
          'Fecha fin',
          'Hora fin',
          'Duracion',
          'Minutos',
        ].map(csvCell).join(','),
      );

    for (final entry in entries) {
      final project = projects[entry.projectId];
      final duration = entry.effectiveDuration;
      buffer.writeln(
        [
          project?.name ?? 'Proyecto eliminado',
          entry.description,
          formatDate(entry.startAt),
          formatTime(entry.startAt),
          entry.endAt == null ? '' : formatDate(entry.endAt!),
          entry.endAt == null ? '' : formatTime(entry.endAt!),
          durationLabel(duration),
          (duration.inSeconds / 60).toStringAsFixed(2),
        ].map(csvCell).join(','),
      );
    }

    await file.writeAsString(buffer.toString(), encoding: utf8);
    return file;
  }
}

class DataSnapshot {
  const DataSnapshot({
    required this.projects,
    required this.activities,
    this.lastOpenedDayKey,
  });

  final List<Project> projects;
  final List<ActivityEntry> activities;
  final String? lastOpenedDayKey;

  factory DataSnapshot.fromJson(Map<String, dynamic> json) {
    return DataSnapshot(
      projects: (json['projects'] as List<dynamic>? ?? [])
          .map((value) => Project.fromJson(value as Map<String, dynamic>))
          .toList(),
      activities: (json['activities'] as List<dynamic>? ?? [])
          .map((value) => ActivityEntry.fromJson(value as Map<String, dynamic>))
          .toList(),
      lastOpenedDayKey: json['lastOpenedDayKey'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projects': projects.map((project) => project.toJson()).toList(),
      'activities': activities.map((activity) => activity.toJson()).toList(),
      'lastOpenedDayKey': lastOpenedDayKey,
    };
  }
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.color,
    required this.isActive,
    required this.createdAt,
    this.archivedAt,
  });

  final String id;
  final String name;
  final int color;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? archivedAt;

  factory Project.create(String name, {required int color}) {
    return Project(
      id: createId('project'),
      name: name,
      color: color,
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as int,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      archivedAt: json['archivedAt'] == null
          ? null
          : DateTime.parse(json['archivedAt'] as String),
    );
  }

  Project copyWith({
    String? name,
    int? color,
    bool? isActive,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'archivedAt': archivedAt?.toIso8601String(),
    };
  }
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.projectId,
    required this.description,
    required this.startAt,
    this.endAt,
  });

  final String id;
  final String projectId;
  final String description;
  final DateTime startAt;
  final DateTime? endAt;

  bool get isRunning => endAt == null;

  Duration get effectiveDuration {
    final finish = endAt ?? DateTime.now();
    if (finish.isBefore(startAt)) {
      return Duration.zero;
    }
    return finish.difference(startAt);
  }

  factory ActivityEntry.create({
    required String projectId,
    required String description,
    required DateTime startAt,
  }) {
    return ActivityEntry(
      id: createId('activity'),
      projectId: projectId,
      description: description,
      startAt: startAt,
    );
  }

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      description: json['description'] as String,
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: json['endAt'] == null
          ? null
          : DateTime.parse(json['endAt'] as String),
    );
  }

  ActivityEntry copyWith({DateTime? endAt}) {
    return ActivityEntry(
      id: id,
      projectId: projectId,
      description: description,
      startAt: startAt,
      endAt: endAt ?? this.endAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'description': description,
      'startAt': startAt.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
    };
  }
}

class ProjectTotal {
  const ProjectTotal({required this.count, required this.duration});

  final int count;
  final Duration duration;

  factory ProjectTotal.empty() {
    return const ProjectTotal(count: 0, duration: Duration.zero);
  }
}

class AppException implements Exception {
  const AppException(this.message);

  final String message;
}

const projectColors = [
  0xFF006A60,
  0xFFB95032,
  0xFF415DA8,
  0xFF7C4D1F,
  0xFF7B4EA3,
  0xFF386A20,
  0xFF9B3D55,
  0xFF52606D,
];

String createId(String prefix) {
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
}

DateTime dayOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String dateKey(DateTime value) {
  return [
    value.year.toString().padLeft(4, '0'),
    value.month.toString().padLeft(2, '0'),
    value.day.toString().padLeft(2, '0'),
  ].join('-');
}

String formatDate(DateTime value) {
  return [
    value.day.toString().padLeft(2, '0'),
    value.month.toString().padLeft(2, '0'),
    value.year.toString().padLeft(4, '0'),
  ].join('/');
}

String formatTime(DateTime value) {
  return [
    value.hour.toString().padLeft(2, '0'),
    value.minute.toString().padLeft(2, '0'),
  ].join(':');
}

String durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return [
    hours.toString().padLeft(2, '0'),
    minutes.toString().padLeft(2, '0'),
    seconds.toString().padLeft(2, '0'),
  ].join(':');
}

String compactDurationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) {
    return '${minutes}m';
  }
  return '${hours}h ${minutes}m';
}

String csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  if (escaped.contains(',') ||
      escaped.contains('\n') ||
      escaped.contains('"')) {
    return '"$escaped"';
  }
  return escaped;
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
