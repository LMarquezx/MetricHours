/// Formatea a `yyyy-MM-dd`, el formato que esperan los parametros/campos
/// `LocalDate` del backend (BackMetric).
String toIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
