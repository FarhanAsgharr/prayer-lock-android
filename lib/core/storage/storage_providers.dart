/// Storage and sync wiring.
///
/// The database is opened once during startup and injected, rather than
/// resolved lazily inside each repository. Opening a SQLCipher database
/// performs deliberately slow key derivation; doing it on first query would
/// stall whichever screen happened to read first.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tracking/data/repositories/tracking_repository.dart';
import '../config/api_config.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_queue.dart';
import 'app_database.dart';

/// Overridden in main() once the database is open.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'appDatabaseProvider must be overridden in main()',
  ),
);

final syncQueueProvider = Provider<SyncQueue>(
  (ref) => SyncQueue(ref.watch(appDatabaseProvider).raw),
);

final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => TrackingRepository(
    ref.watch(appDatabaseProvider).raw,
    ref.watch(syncQueueProvider),
  ),
);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    queue: ref.watch(syncQueueProvider),
    repository: ref.watch(trackingRepositoryProvider),
    client: ApiConfig.createClient(),
  );
  ref.onDispose(engine.stop);
  return engine;
});

/// Live sync status for the dashboard indicator.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.statusStream;
});
