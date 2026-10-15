import '../api/client.dart';

/// PI26093009: the Data October progress, as hub serves it at `/api/october/progress`.
/// Counts and sizes only. "Day n of 28" is the feed's own `day_n`, never the clock here.
class OctoberProgress {
  const OctoberProgress({
    this.available = false,
    this.totalGb = 0,
    this.working = 0,
    this.vault = 0,
    this.archiveCold = 0,
    this.duplicatesGb = 0,
    this.foldersDecided = 0,
    this.foldersTotal = 0,
    this.chunksDone = 0,
    this.dayN = 0,
    this.daysTotal = 28,
    this.nextChunkGb = 0,
    this.nextChunkMinutes = 0,
    this.lastChunkAt,
  });

  final bool available;
  final double totalGb;
  final double working;
  final double vault;
  final double archiveCold;
  final double duplicatesGb;
  final int foldersDecided;
  final int foldersTotal;
  final int chunksDone;
  final int dayN;
  final int daysTotal;
  final double nextChunkGb;
  final int nextChunkMinutes;
  final DateTime? lastChunkAt;

  double get movedGb => working + vault + archiveCold;

  /// The share of the data that is decided and moved, 0 to 1.
  double get share => totalGb <= 0 ? 0 : (movedGb / totalGb).clamp(0.0, 1.0);

  /// Past the last day, the ring becomes a before-and-after summary.
  bool get ended => dayN > daysTotal;

  /// During the month, a chunk not run for two days earns a nudge.
  bool needsChunk(DateTime now) {
    if (ended || nextChunkGb <= 0) return false;
    final last = lastChunkAt;
    return last == null || now.difference(last).inHours >= 48;
  }

  static double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  static int _i(Object? v) => _d(v).toInt();

  factory OctoberProgress.parse(Object? json) {
    final m = json is Map ? json : const {};
    if (m['available'] == false || m['available'] == null && m['total_gb'] == null) return const OctoberProgress();
    final mig = m['migrated_gb'] is Map ? m['migrated_gb'] as Map : const {};
    final next = m['next_chunk'] is Map ? m['next_chunk'] as Map : const {};
    final last = DateTime.tryParse('${m['last_chunk_at'] ?? ''}');
    return OctoberProgress(
      available: true,
      totalGb: _d(m['total_gb']),
      working: _d(mig['working']),
      vault: _d(mig['vault']),
      archiveCold: _d(mig['archive_cold']),
      duplicatesGb: _d(m['duplicates_removed_gb']),
      foldersDecided: _i(m['folders_decided']),
      foldersTotal: _i(m['folders_total']),
      chunksDone: _i(m['chunks_done']),
      dayN: _i(m['day_n']),
      daysTotal: _i(m['days_total']) == 0 ? 28 : _i(m['days_total']),
      nextChunkGb: _d(next['gb']),
      nextChunkMinutes: _i(next['minutes_estimate']),
      lastChunkAt: last,
    );
  }

  static String gb(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

  /// "48 GB moved · 6 GB of duplicates gone · 31 of 57 folders decided."
  String get line => '${gb(movedGb)} GB moved · ${gb(duplicatesGb)} GB of duplicates gone · $foldersDecided of $foldersTotal folders decided';
}

abstract class OctoberApi {
  Future<OctoberProgress> progress();
}

class HubOctoberApi implements OctoberApi {
  HubOctoberApi(this.api);
  final ApiClient api;

  @override
  Future<OctoberProgress> progress() async => OctoberProgress.parse(await api.getJson('/api/october/progress'));
}
