/// BI26100509 (finance depth): the one place the app reads and writes Holdings' editable registries.
///
/// The stock finance engine moves to xkeel ledger (PL26100305), so every finance write the app makes goes
/// through this class and nowhere else; swapping the backend is then a change here only. Today it speaks to
/// hub's `/api/possessions*` routes, served by pulse's possessions registry.
///
/// Finance data is T3: nothing here logs a row, and nothing puts a value or a name in a URL (ids travel in
/// the POST body).
library;

import '../util/fmt.dart' as fmt;

typedef GetJson = Future<dynamic> Function(String path);
typedef PostJson = Future<dynamic> Function(String path, Map<String, dynamic> body);

/// One possession: Holdings' general asset registry (not money only).
class Possession {
  const Possession({
    required this.id,
    required this.item,
    this.category = '',
    this.value = 0,
    this.acquiredDate = '',
    this.location = '',
    this.condition = '',
    this.notes = '',
  });

  final String id;
  final String item;
  final String category;
  final double value;
  final String acquiredDate;
  final String location;
  final String condition;
  final String notes;

  /// From a registry row (TSV columns, '-' meaning empty).
  factory Possession.fromRow(Map<String, dynamic> r) => Possession(
        id: fmt.s(r['ID']),
        item: fmt.s(r['ITEM']),
        category: fmt.s(r['CATEGORY']),
        value: fmt.d(r['VALUE']),
        acquiredDate: fmt.s(r['ACQUIRED_DATE']),
        location: fmt.s(r['LOCATION']),
        condition: fmt.s(r['CONDITION']),
        notes: fmt.s(r['NOTES']),
      );

  /// The upsert body. An empty id means a new possession.
  Map<String, dynamic> toBody() => {
        if (id.isNotEmpty) 'id': id,
        'item': item,
        'category': category,
        'value': value,
        'acquiredDate': acquiredDate,
        'location': location,
        'condition': condition,
        'notes': notes,
      };
}

class FinanceRepository {
  FinanceRepository({required GetJson get, required PostJson post})
      : _get = get,
        _post = post;

  final GetJson _get;
  final PostJson _post;

  static const possessionsPath = '/api/possessions';

  /// Every possession, item order. Rows without an id are skipped (they cannot be edited or deleted).
  Future<List<Possession>> possessions() async {
    final res = await _get(possessionsPath);
    final rows = fmt.lm(fmt.m(res)['possessions'])
        .map(Possession.fromRow)
        .where((p) => p.id.isNotEmpty)
        .toList()
      ..sort((a, b) => a.item.toLowerCase().compareTo(b.item.toLowerCase()));
    return rows;
  }

  /// Creates or updates; returns the id the registry holds it under.
  Future<String> savePossession(Possession p) async {
    if (p.id.isEmpty && p.item.trim().isEmpty) {
      throw ArgumentError('A new possession needs a name.');
    }
    final res = fmt.m(await _post('$possessionsPath/upsert', p.toBody()));
    if (res['success'] != true) throw StateError(fmt.s(res['error']).isEmpty ? 'Not saved.' : fmt.s(res['error']));
    return fmt.s(res['id']);
  }

  Future<void> deletePossession(String id) async {
    final res = fmt.m(await _post('$possessionsPath/delete', {'id': id}));
    if (res['success'] != true) throw StateError(fmt.s(res['error']).isEmpty ? 'Not deleted.' : fmt.s(res['error']));
  }

  /// The registry's total value, for the masked headline.
  static double totalValue(List<Possession> items) => items.fold(0, (a, p) => a + p.value);
}
