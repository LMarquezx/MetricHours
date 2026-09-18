import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'models/proyecto_dto.dart';
import 'models/registro_hora_dto.dart';
import 'services/log_service.dart';
import 'services/local_storage_service.dart';

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(
      LogService.log(
        '=== FlutterError ===\n'
        '${details.exceptionAsString()}\n'
        '${details.stack}',
      ),
    );
  };
  runZonedGuarded(() => runApp(const MetricHoursApp()), (error, stack) {
    unawaited(LogService.log('=== Uncaught zone error ===\n$error\n$stack'));
  });
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
    controller = AppController(LocalStorageService(), ExportService());
    // La carga del almacenamiento del dispositivo arranca cuando el usuario
    // elige "Usar en local" en WelcomeScreen.
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
        home: const WelcomeScreen(),
      ),
    );
  }
}

/// Pantalla inicial: elegir entre usar los datos guardados en este dispositivo
/// o iniciar sesion con Google. El login todavia no esta implementado.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icon/Logo_app.png',
                  width: 260,
                  height: 96,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                Text(
                  'Metric Hours',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Elige como quieres continuar',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Usar en local'),
                    onPressed: () {
                      final app = AppScope.of(context);
                      if (!app.isLoaded) {
                        unawaited(app.load());
                      }
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const AppShell()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Iniciar sesion con Google'),
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
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

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  Future<void> _openNewActivitySheet(
    BuildContext context,
    AppController app,
  ) async {
    if (app.activeProjects.isEmpty) {
      _showMessage(context, 'Da de alta un proyecto activo primero.');
      return;
    }

    final started = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _NewActivitySheet(app: app),
    );

    if (started == true &&
        context.mounted &&
        !isSameDay(app.selectedDay, DateTime.now())) {
      app.selectDay(DateTime.now());
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final activities = app.activitiesForDay(app.selectedDay);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            DaySelector(value: app.selectedDay, onChanged: app.selectDay),
            const SizedBox(height: 12),
            if (app.runningActivity != null)
              ActiveActivityPanel(activity: app.runningActivity!)
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar actividad'),
                  onPressed: () => _openNewActivitySheet(context, app),
                ),
              ),
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
    final elapsed = activity.effectiveDuration;
    // Anillo calibrado a 1 hora = 100%; se satura si la actividad dura mas.
    final progress = (elapsed.inSeconds / 3600).clamp(0.0, 1.0);
    final projectColor = Color(project.color);

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      valueColor: AlwaysStoppedAnimation(projectColor),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        humanDurationLabel(elapsed),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tiempo total',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: ProjectName(project: project)),
                Text(
                  durationLabel(elapsed),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              activity.description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
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

class _NewActivitySheet extends StatefulWidget {
  const _NewActivitySheet({required this.app});

  final AppController app;

  @override
  State<_NewActivitySheet> createState() => _NewActivitySheetState();
}

class _NewActivitySheetState extends State<_NewActivitySheet> {
  final descriptionController = TextEditingController();
  final speech = SpeechToText();
  late String? selectedProjectId;
  bool speechReady = false;
  bool speechBusy = false;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    selectedProjectId = widget.app.activeProjects.firstOrNull?.id;
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

  Future<void> _submit() async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      _showMessage(context, 'Selecciona un proyecto.');
      return;
    }

    setState(() => submitting = true);
    try {
      await widget.app.startActivity(
        projectId: projectId,
        description: descriptionController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on AppException catch (error) {
      if (mounted) {
        setState(() => submitting = false);
        _showMessage(context, error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeProjects = widget.app.activeProjects;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nueva actividad',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: descriptionController,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Actividad',
              hintText: 'Describe lo que estas haciendo',
              prefixIcon: const Icon(Icons.edit_note),
              suffixIcon: IconButton(
                tooltip: speechBusy ? 'Detener voz' : 'Dictar voz',
                icon: Icon(speechBusy ? Icons.mic : Icons.mic_none_outlined),
                onPressed: _toggleSpeech,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Proyecto', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final project in activeProjects) ...[
            _ProjectBadgeOption(
              project: project,
              selected: project.id == selectedProjectId,
              onTap: () => setState(() => selectedProjectId = project.id),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Guardar'),
                  onPressed: submitting ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectBadgeOption extends StatelessWidget {
  const _ProjectBadgeOption({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final Project project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            ColorDot(color: Color(project.color)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                project.name,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: scheme.primary),
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
    final result = await showDialog<({String name, int color})>(
      context: context,
      builder: (context) {
        return _ProjectNameDialog(
          initialName: project?.name ?? '',
          isRename: project != null,
          initialColor:
              project?.color ??
              projectColors[app.projects.length % projectColors.length],
        );
      },
    );
    await LogService.log(
      '_showProjectDialog: resultado del dialogo = "$result"',
    );

    if (result == null) {
      await LogService.log('_showProjectDialog: cancelado por el usuario');
      return;
    }

    try {
      if (project == null) {
        await LogService.log(
          '_showProjectDialog: llamando addProject("${result.name}")',
        );
        await app.addProject(result.name, color: result.color);
        await LogService.log('_showProjectDialog: addProject OK');
      } else {
        await LogService.log(
          '_showProjectDialog: llamando renameProject(${project.id}, "${result.name}")',
        );
        await app.renameProject(project.id, result.name, color: result.color);
        await LogService.log('_showProjectDialog: renameProject OK');
      }
    } on AppException catch (error) {
      await LogService.log(
        '_showProjectDialog: AppException -> ${error.message}',
      );
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
  const _ProjectNameDialog({
    required this.initialName,
    required this.isRename,
    required this.initialColor,
  });

  final String initialName;
  final bool isRename;
  final int initialColor;

  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  late final TextEditingController _controller;
  late int _selectedColor;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pop(String name) {
    Navigator.of(context).pop((name: name, color: _selectedColor));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isRename ? 'Renombrar' : 'Alta de proyecto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: _pop,
            ),
            const SizedBox(height: 16),
            Text('Color', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in projectColors)
                  _ColorSwatch(
                    color: Color(color),
                    selected: color == _selectedColor,
                    onTap: () => setState(() => _selectedColor = color),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => _pop(_controller.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
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
        final dailyTotals = dailyDurations(
          activities,
          app.reportStart,
          app.reportEnd,
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
            if (activities.isEmpty)
              const EmptyState(
                icon: Icons.query_stats_outlined,
                title: 'Sin datos',
                subtitle: 'El rango seleccionado no tiene actividades.',
              )
            else ...[
              Text(
                'Horas por dia',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              DailyHoursChart(dailyTotals: dailyTotals),
              const SizedBox(height: 20),
              Text(
                'Por proyecto',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ProjectBreakdownChart(totals: totals),
            ],
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

class DailyHoursChart extends StatelessWidget {
  const DailyHoursChart({required this.dailyTotals, super.key});

  final List<MapEntry<DateTime, Duration>> dailyTotals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHours = dailyTotals.fold<double>(
      0,
      (value, entry) => value > entry.value.inSeconds / 3600
          ? value
          : entry.value.inSeconds / 3600,
    );
    final chartMax = maxHours <= 0 ? 1.0 : maxHours * 1.25;
    final interval = chartMax / 4;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 20, 8),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: chartMax,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: scheme.outlineVariant, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: interval == 0 ? 1 : interval,
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= dailyTotals.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          dayShortLabel(dailyTotals[index].key),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < dailyTotals.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: dailyTotals[i].value.inSeconds / 3600,
                        color: isSameDay(dailyTotals[i].key, DateTime.now())
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.5),
                        width: 18,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProjectBreakdownChart extends StatelessWidget {
  const ProjectBreakdownChart({required this.totals, super.key});

  final Map<Project, ProjectTotal> totals;

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.duration.compareTo(a.value.duration));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 34,
                  sectionsSpace: 2,
                  sections: [
                    for (final entry in entries)
                      PieChartSectionData(
                        value: entry.value.duration.inSeconds.toDouble(),
                        color: Color(entry.key.color),
                        radius: 24,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          ColorDot(color: Color(entry.key.color)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.key.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            compactDurationLabel(entry.value.duration),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
  AppController(this.localStorage, this.exportService);

  final LocalStorageService localStorage;
  final ExportService exportService;
  final List<Project> projects = [];
  final List<ActivityEntry> activities = [];
  DateTime selectedDay = dayOnly(DateTime.now());
  DateTime reportStart = dayOnly(DateTime.now());
  DateTime reportEnd = dayOnly(DateTime.now());
  bool isLoaded = false;
  Timer? _ticker;
  Timer? _midnightTimer;

  List<Project> get activeProjects =>
      projects.where((project) => project.isActive).toList();

  ActivityEntry? get runningActivity =>
      activities.where((activity) => activity.isRunning).firstOrNull;

  /// Carga los datos que se guardaron previamente en este dispositivo.
  Future<void> load() async {
    try {
      final data = await localStorage.read();
      final storedProjects = (data['projects'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Project.fromLocalJson);
      projects
        ..clear()
        ..addAll(storedProjects);

      final storedActivities =
          (data['activities'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ActivityEntry.fromLocalJson);
      activities
        ..clear()
        ..addAll(storedActivities);

      if (projects.isEmpty) {
        await addProject('Personal');
      }

      selectedDay = dayOnly(DateTime.now());
      reportStart = selectedDay;
      reportEnd = selectedDay;
    } catch (error) {
      await LogService.log(
        'AppController.load: fallo cargando datos locales -> $error',
      );
    }

    _startTicker();
    _scheduleMidnightRollover();
    isLoaded = true;
    notifyListeners();
  }

  Future<void> selectDay(DateTime value) async {
    selectedDay = dayOnly(value);
    notifyListeners();
  }

  Future<void> setReportRange(DateTime start, DateTime end) async {
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

  Future<void> addProject(String rawName, {int? color}) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw const AppException('Escribe un nombre de proyecto.');
    }
    final chosenColor =
        color ?? projectColors[projects.length % projectColors.length];
    projects.add(
      Project(
        id: _newId(),
        name: name,
        color: chosenColor,
        isActive: true,
        createdAt: DateTime.now(),
      ),
    );
    await _save();
    notifyListeners();
  }

  Future<void> renameProject(String id, String rawName, {int? color}) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw const AppException('Escribe un nombre de proyecto.');
    }
    final current = projectById(id);
    final index = projects.indexWhere((project) => project.id == id);
    if (index != -1) {
      projects[index] = current.copyWith(
        name: name,
        color: color ?? current.color,
      );
    }
    await _save();
    notifyListeners();
  }

  Future<void> setProjectActive(String id, bool isActive) async {
    if (!isActive &&
        activeProjects.length == 1 &&
        activeProjects.first.id == id) {
      throw const AppException('Debe quedar al menos un proyecto activo.');
    }

    final index = projects.indexWhere((project) => project.id == id);
    if (index != -1) {
      projects[index] = projects[index].copyWith(
        isActive: isActive,
        archivedAt: isActive ? null : DateTime.now(),
        clearArchivedAt: isActive,
      );
    }
    await _save();
    notifyListeners();
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

    _upsertActivity(
      ActivityEntry(
        id: _newId(),
        projectId: projectId,
        description: cleanDescription,
        startAt: DateTime.now(),
      ),
    );
    selectedDay = dayOnly(DateTime.now());
    await _save();
    notifyListeners();
  }

  Future<void> stopActivity(String id) async {
    final index = activities.indexWhere((activity) => activity.id == id);
    if (index == -1) {
      return;
    }
    if (!activities[index].isRunning) {
      return;
    }
    activities[index] = activities[index].copyWith(endAt: DateTime.now());
    await _save();
    notifyListeners();
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

  void _upsertActivity(ActivityEntry entry) {
    final index = activities.indexWhere((activity) => activity.id == entry.id);
    if (index == -1) {
      activities.add(entry);
    } else {
      activities[index] = entry;
    }
  }

  Future<void> _save() => localStorage.write(
    projects: projects.map((project) => project.toLocalJson()).toList(),
    activities: activities.map((activity) => activity.toLocalJson()).toList(),
  );

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (runningActivity != null) {
        notifyListeners();
      }
    });
  }

  /// Al cruzar la medianoche, el Registro vuelve a apuntar a "hoy".
  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = dayOnly(now).add(const Duration(days: 1));
    final delay =
        nextMidnight.difference(now) + const Duration(milliseconds: 300);
    _midnightTimer = Timer(delay, () {
      unawaited(selectDay(DateTime.now()));
      _scheduleMidnightRollover();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _midnightTimer?.cancel();
    super.dispose();
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

    // El BOM UTF-8 hace que Excel detecte la codificacion correcta en vez
    // de asumir la codificacion ANSI del sistema, que rompe acentos y enies.
    const utf8Bom = '﻿';
    await file.writeAsString('$utf8Bom${buffer.toString()}', encoding: utf8);
    return file;
  }
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.color,
    required this.isActive,
    required this.createdAt,
    this.descripcion,
    this.presupuestoHoras,
    this.archivedAt,
  });

  final String id;
  final String name;
  final int color;
  final bool isActive;
  final DateTime createdAt;
  final String? descripcion;
  final int? presupuestoHoras;
  final DateTime? archivedAt;

  factory Project.fromDto(ProyectoDto dto) {
    final isActive = dto.estado == EstadoProyectoDto.activo;
    return Project(
      id: dto.id,
      name: dto.nombre,
      color: colorFromHex(dto.color),
      isActive: isActive,
      createdAt: dto.fechaCreacion.toLocal(),
      descripcion: dto.descripcion,
      presupuestoHoras: dto.presupuestoHoras,
      archivedAt: isActive ? null : dto.fechaActualizacion.toLocal(),
    );
  }

  factory Project.fromLocalJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as int,
      isActive: json['isActive'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      descripcion: json['descripcion'] as String?,
      presupuestoHoras: json['presupuestoHoras'] as int?,
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
      descripcion: descripcion,
      presupuestoHoras: presupuestoHoras,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
    );
  }

  Map<String, dynamic> toLocalJson() => {
    'id': id,
    'name': name,
    'color': color,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
    'descripcion': descripcion,
    'presupuestoHoras': presupuestoHoras,
    'archivedAt': archivedAt?.toIso8601String(),
  };
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

  /// El backend distingue TIMER (con `horaInicio`/`horaFin` reales) de
  /// MANUAL (solo `fecha` + `horas`, sin marcas de tiempo). Para un MANUAL
  /// se ancla al inicio del dia y se deriva un `endAt` a partir de `horas`,
  /// asi el resto del modelo (duracion, orden, filtrado por dia) no necesita
  /// distinguir entre origenes.
  factory ActivityEntry.fromDto(RegistroHoraDto dto) {
    if (dto.origen == OrigenRegistroDto.timer) {
      return ActivityEntry(
        id: dto.id,
        projectId: dto.proyectoId,
        description: dto.descripcion,
        startAt: (dto.horaInicio ?? dto.fecha).toLocal(),
        endAt: dto.horaFin?.toLocal(),
      );
    }

    final dayStart = DateTime(dto.fecha.year, dto.fecha.month, dto.fecha.day);
    final duration = Duration(seconds: (dto.horas.toDouble() * 3600).round());
    return ActivityEntry(
      id: dto.id,
      projectId: dto.proyectoId,
      description: dto.descripcion,
      startAt: dayStart,
      endAt: dayStart.add(duration),
    );
  }

  factory ActivityEntry.fromLocalJson(Map<String, dynamic> json) {
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

  ActivityEntry copyWith({DateTime? endAt}) => ActivityEntry(
    id: id,
    projectId: projectId,
    description: description,
    startAt: startAt,
    endAt: endAt ?? this.endAt,
  );

  Map<String, dynamic> toLocalJson() => {
    'id': id,
    'projectId': projectId,
    'description': description,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt?.toIso8601String(),
  };
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

/// El backend guarda el color como string libre; se usa `#RRGGBB` (siempre
/// opaco, como los colores de [projectColors]) para poder ir y venir sin
/// perder informacion.
String colorToHex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

int colorFromHex(String? hex) {
  if (hex == null) return projectColors.first;
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (value == null) return projectColors.first;
  return 0xFF000000 | value;
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

List<MapEntry<DateTime, Duration>> dailyDurations(
  List<ActivityEntry> activities,
  DateTime start,
  DateTime end,
) {
  final byDay = <String, Duration>{};
  for (final activity in activities) {
    final key = dateKey(activity.startAt);
    byDay[key] = (byDay[key] ?? Duration.zero) + activity.effectiveDuration;
  }

  final days = <DateTime>[];
  var cursor = dayOnly(start);
  final last = dayOnly(end);
  while (!cursor.isAfter(last)) {
    days.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }

  return [
    for (final day in days) MapEntry(day, byDay[dateKey(day)] ?? Duration.zero),
  ];
}

const _weekdayShortNames = [
  '',
  'lun',
  'mar',
  'mie',
  'jue',
  'vie',
  'sab',
  'dom',
];

String dayShortLabel(DateTime day) {
  final now = DateTime.now();
  if (isSameDay(day, now)) {
    return 'Hoy';
  }
  if (isSameDay(day, now.subtract(const Duration(days: 1)))) {
    return 'Ayer';
  }
  return _weekdayShortNames[day.weekday];
}

String humanDurationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final parts = <String>[];
  if (hours > 0) {
    parts.add('${hours}h');
  }
  if (hours > 0 || minutes > 0) {
    parts.add('${minutes}m');
  }
  parts.add('${seconds}s');
  return parts.join(' ');
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
