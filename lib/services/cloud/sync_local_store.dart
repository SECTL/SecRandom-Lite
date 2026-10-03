import '../data_service.dart';
import 'sync_state.dart';

/// 同步状态/outbox 的本地存储抽象（测试注入内存实现）
abstract class SyncLocalStore {
  Future<LocalSyncState> loadState();
  Future<void> saveState(LocalSyncState state);
  Future<SyncOutbox> loadOutbox();
  Future<void> saveOutbox(SyncOutbox outbox);
}

class DataServiceSyncLocalStore implements SyncLocalStore {
  DataServiceSyncLocalStore(this._dataService);

  final DataService _dataService;

  @override
  Future<LocalSyncState> loadState() async =>
      LocalSyncState.fromJson(await _dataService.loadSyncState());

  @override
  Future<void> saveState(LocalSyncState state) =>
      _dataService.saveSyncState(state.toJson());

  @override
  Future<SyncOutbox> loadOutbox() async =>
      SyncOutbox.fromJson(await _dataService.loadSyncOutbox());

  @override
  Future<void> saveOutbox(SyncOutbox outbox) =>
      _dataService.saveSyncOutbox(outbox.toJson());
}
