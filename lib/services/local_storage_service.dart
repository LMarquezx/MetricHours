import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Almacenamiento privado de Metric Hours en el dispositivo.
///
/// No realiza llamadas de red: la base de datos SQLite solo se crea dentro
/// del directorio de documentos que Android asigna a esta aplicacion.
class LocalStorageService {
  static const _dbName = 'metric_hours.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) {
      return existing;
    }
    final directory = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      p.join(directory.path, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color INTEGER NOT NULL,
            isActive INTEGER NOT NULL,
            createdAt TEXT NOT NULL,
            descripcion TEXT,
            presupuestoHoras INTEGER,
            archivedAt TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE activities (
            id TEXT PRIMARY KEY,
            projectId TEXT NOT NULL,
            description TEXT NOT NULL,
            startAt TEXT NOT NULL,
            endAt TEXT,
            pausedSeconds INTEGER NOT NULL DEFAULT 0,
            pausedAt TEXT
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  Future<List<Map<String, Object?>>> readProjects() async {
    final db = await _database();
    return db.query('projects', orderBy: 'createdAt ASC');
  }

  Future<List<Map<String, Object?>>> readActivities() async {
    final db = await _database();
    return db.query('activities', orderBy: 'startAt ASC');
  }

  Future<void> upsertProject(Map<String, Object?> row) async {
    final db = await _database();
    await db.insert(
      'projects',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertActivity(Map<String, Object?> row) async {
    final db = await _database();
    await db.insert(
      'activities',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
