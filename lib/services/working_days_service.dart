import 'local_storage_service.dart';

/// Patron semanal de dias laborales (lunes=1 ... domingo=7, igual que
/// `DateTime.weekday`).
///
/// Cualquier hora registrada en un dia de la semana que no este marcado como
/// laboral (por ejemplo un sabado, si no se selecciona) se contabiliza como
/// hora adicional en el resumen, igual que un dia inhabil especifico
/// ([HolidaysService]).
class WorkingDaysService {
  WorkingDaysService(this.localStorage);

  final LocalStorageService localStorage;

  static const _key = 'working_weekdays';
  static const defaultWorkingWeekdays = {1, 2, 3, 4, 5};

  Future<Set<int>> load() async {
    final raw = await localStorage.readSetting(_key);
    if (raw == null || raw.isEmpty) {
      return {...defaultWorkingWeekdays};
    }
    final parsed = raw
        .split(',')
        .where((chunk) => chunk.isNotEmpty)
        .map(int.parse)
        .where((weekday) => weekday >= 1 && weekday <= 7)
        .toSet();
    return parsed.isEmpty ? {...defaultWorkingWeekdays} : parsed;
  }

  Future<void> save(Set<int> weekdays) async {
    await localStorage.writeSetting(_key, weekdays.join(','));
  }
}
