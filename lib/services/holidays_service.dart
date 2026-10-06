import 'local_storage_service.dart';

/// Dias marcados como inhabiles (feriados, descanso, etc.) en Ajustes.
///
/// Cualquier hora registrada en uno de estos dias se contabiliza integra
/// como hora adicional en el resumen, sin aplicar el umbral normal de horas
/// por dia. Se guarda como una lista de fechas (`yyyy-MM-dd`) separadas por
/// coma en la misma tabla `settings` de SQLite que usa el resto de la
/// configuracion.
class HolidaysService {
  HolidaysService(this.localStorage);

  final LocalStorageService localStorage;

  static const _key = 'inactive_days';

  Future<Set<DateTime>> load() async {
    final raw = await localStorage.readSetting(_key);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    return raw
        .split(',')
        .where((chunk) => chunk.isNotEmpty)
        .map(_parseDateKey)
        .toSet();
  }

  Future<void> save(Set<DateTime> days) async {
    final raw = days.map(_toDateKey).join(',');
    await localStorage.writeSetting(_key, raw);
  }

  DateTime _parseDateKey(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  String _toDateKey(DateTime date) {
    return [
      date.year.toString().padLeft(4, '0'),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
    ].join('-');
  }
}
