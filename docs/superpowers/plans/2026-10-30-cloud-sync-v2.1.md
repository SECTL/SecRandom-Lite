# 云同步 v2.1 + 账号工作区隔离 实施计划

状态：已完成（2026-10-30）。全量 `flutter test`：191 通过，12 跳过。

设计文档：`docs/superpowers/specs/2026-10-30-cloud-sync-v2.1-design.md`

## 约束

- 当前分支 `main`，最新提交 `0f7244e`。
- 不修改未提交的 `analysis_options.yaml`。
- 不改服务端，继续用 SECTL 云 KV API。
- 每个任务先写失败测试，再写实现，最后跑该测试文件；全部完成后跑 `flutter test`。
- 测试数据目录用 `test/helpers/isolated_data_dir.dart`；新增工作区测试时必须重置 `DataService` 工作区。

## 任务 0：基线

1. `flutter test --reporter compact` 记录基线：151 通过，12 跳过。
2. 确认 `git status` 只有 `analysis_options.yaml` 和 `docs/superpowers/`。

## 任务 1：DataService 工作区路径与默认名单移除

### 测试 `test/data_service_workspace_test.dart`

1. `workspaceKeyForUser('user-1')` 稳定且等于 `acct_` + 24 位十六进制；不同用户不同。
2. guest 写入 `students.json` 后，账号工作区读不到；账号 A 写入后账号 B 读不到。
3. `ensureWorkspace` 创建目录和 `workspace.json`；`workspaceExists` 为 true；未创建的 key 为 false；guest 永远 true。
4. 旧目录没有 marker 但有 `students.json` 时 `workspaceExists` 为 true。
5. 新装 `loadStudents()` 返回空列表，不生成 40 人。
6. 旧版 40 人文件仍能原样读出。
7. 旧学生没有 uid 时读出后派生 `legacy:` uid 并写回文件。
8. Web key 纯函数：guest 为 `students.json`，账号为 `<key>:students.json`。

### 实现

`lib/services/data_service.dart`：

```dart
static const String guestWorkspace = 'guest';
static const String _workspaceMarkerFileName = 'workspace.json';
static String _currentWorkspace = guestWorkspace;
static String get currentWorkspace => _currentWorkspace;

static String workspaceKeyForUser(String userId);
static void setWorkspace(String key);
static void resetWorkspaceToGuest();
static Future<bool> workspaceExists(String key);
static Future<void> ensureWorkspace(String key);
static Future<String?> _baseDataDirPath();
static String _webStorageKeyFor(String fileName, String workspace);
```

- `workspaceKeyForUser` 用 `sha256(userId).substring(0, 24)`；空 userId 返回 guest。
- key 只允许 `[A-Za-z0-9_]+`。
- guest 使用旧版根目录/无前缀 key；账号使用 `<data>/accounts/<key>/` 和 `<key>:` 前缀。
- `workspaceExists` 先看 marker，再回退到已知文件。
- 所有公开读写方法在入口捕获 `final ws = _currentWorkspace;`，路径/key 用该快照。
- `_getStudentsFile`、`_getHistoryFile`、`_getPrizeFile`、`_getLotteryRecordsFile` 接受可选 workspace。
- `_withConfigFileLock` 用当前工作区目录。
- `loadAllPrizePools` 只扫当前工作区。
- `loadStudents` 删除 `_getInitialStudents()` 生成逻辑；缺失/空/解析失败返回 `[]`。
- 解析后对空 uid 的学生调用 `deriveLegacyStudentUid` 并 `saveStudents` 写回。

`lib/models/student.dart`：

```dart
final String uid;
final int rev;
final String revBy;
Student copyWith({...});
```

`lib/services/cloud/sync_identity.dart`：

```dart
String deriveLegacyStudentUid(Student student) =>
    _legacyUid('${student.className}|${student.id}|${student.name}');
```

### 验证

```bash
flutter test test/data_service_workspace_test.dart
```

## 任务 2：AppProvider 认证切换与工作区加载

### 测试 `test/workspace_isolation_test.dart`

用 `_FakeCloudSyncService extends CloudSyncService` 控制 `cloudHasAnyData`、`pullFullSnapshot`、`pushAll`，记录调用。

1. guest 有历史/学生；登录新账号且云端有数据 → 账号历史/学生 = 云端；guest 的 `students.json`/`history.json` 内容不变。
2. 新账号云端为空 → 账号为空；`pushAllCalls == 0`；guest 文件不变。
3. 已有账号工作区再次登录 → 加载本地新增记录，不重复克隆。
4. A→B→A → 两边数据与主题配置互不影响。
5. 退出登录 → 回到 guest，账号目录保留。
6. 首次登录离线（`cloudHasAnyData` 抛错或 `pullFullSnapshot` 返回 null）→ `baselineInitialized == false`，`pushToCloud()` 返回 false，云端无写入。
7. `provider.ready` 在构造后可用；不再依赖 `totalCount > 0`。
8. `DataService.currentWorkspace` 在退出后为 guest。

### 实现

`lib/providers/app_provider.dart`：

```dart
Future<void> get ready;
Future<void> setAuthState(bool loggedIn, {String? userId});
```

- `_loadFuture` + `Completer<void>`；`_loadData` 结束完成 `ready`。
- `_workspaceKey`、`_authUserId`、`_workspaceEpoch`、`_workspaceReady`、`_authChange`。
- 登录且 `userId != null`：切到 `workspaceKeyForUser(userId)`；不存在则 `ensureWorkspace` 后标记 `newWorkspace`。
- 退出：切回 guest。
- 登录但 `userId == null`：保留当前工作区（测试/旧调用兼容）。
- 切换前：取消 debounce/retry，`await waitForPendingConfigSave()`，`await ready`。
- 切换后：`DataService.setWorkspace` → `_cloudSyncService.resetWorkspaceState()` → `_loadData()`。
- 新工作区：`_cloneCloudWorkspace()`；成功前 `_workspaceReady=false`，push/pull 返回 false。
- 克隆：云端无数据 → 空基线、`baselineInitialized=true`、`legacyUploaded=true`、不 push；云端有数据 → `pullFullSnapshot` 严格覆盖，包含学生/墓碑/历史/抽奖/统计/清空。
- 克隆失败：`baselineInitialized=false`，不 push，下次登录/`syncNow` 重试。
- `pushToCloud`/`pullFromCloud`/`syncNow` 检查 `_workspaceReady`。

`lib/services/cloud/cloud_sync_service.dart`：

```dart
void resetWorkspaceState() {
  _state = null;
  _localStoreInstance = null;
  _discoveredRemoteDevices = null;
  _discoveredRemoteDevicesAt = null;
  _status = SyncStatus.idle;
  _lastError = null;
  _retryCount = 0;
  _retryTimer?.cancel();
  _retryTimer = null;
}
```

`lib/main.dart`：

```dart
_authListener = () {
  final user = _authProvider.userInfo;
  _appProvider.setAuthState(_authProvider.isLoggedIn, userId: user?.userId);
};
```

`test/helpers/isolated_data_dir.dart`：`setUp` 里 `DataService.resetWorkspaceToGuest()`。

### 验证

```bash
flutter test test/workspace_isolation_test.dart
```

## 任务 3：sync_state 新字段

### 测试 `test/sync_state_test.dart`

往返序列化：

- `studentClock`、`studentSeq`、`studentsDirty`
- `studentTombstones: Map<String, StudentTombstone>`
- `clearsDirty`
- `clearedClasses: Map<String, Map<String, DateTime>>`
- `clearedPools: Map<String, DateTime>`

### 实现 `lib/services/cloud/sync_state.dart`

```dart
class StudentTombstone {
  final int rev;
  final String by;
  final DateTime at;
  Map<String, dynamic> toJson();
  factory StudentTombstone.fromJson(Map<String, dynamic> json);
}

class LocalSyncState {
  int studentClock;
  int studentSeq;
  bool studentsDirty;
  final Map<String, StudentTombstone> studentTombstones;
  bool clearsDirty;
  final Map<String, Map<String, DateTime>> clearedClasses;
  final Map<String, DateTime> clearedPools;
}
```

JSON key 用 snake_case：`student_clock`、`student_seq`、`students_dirty`、`student_tombstones`、`clears_dirty`、`cleared_classes`、`cleared_pools`。

## 任务 4：学生合并纯函数

### 测试 `test/student_sync_test.dart`

1. 云端独有学生加入本地。
2. 本地独有学生保留并 `needsPush`。
3. 高 `rev` 胜；同 rev 比 `revBy`。
4. 墓碑胜存活；存活胜墓碑。
5. 平局本地内容胜。
6. 两端 rev 0 且内容不同：本地胜并分配 `++studentClock`，第二次合并不再翻转。
7. 不同 uid、相同 `(className, id)`：两个都保留，后到者 id 重排。
8. 班级重命名：uid 不变、rev 递增（由 AppProvider 调用 `copyWith`，测试纯函数输入输出）。
9. `studentClock` 取本地与云端最大 rev。

### 实现 `lib/services/cloud/student_sync.dart`

```dart
class StudentMergeResult {
  final List<Student> students;
  final Map<String, StudentTombstone> tombstones;
  final int studentClock;
  final bool changed;
  final bool needsPush;
}

StudentMergeResult mergeStudents({
  required List<Student> local,
  required Map<String, StudentTombstone> localTombstones,
  required List<Student> cloud,
  required Map<String, StudentTombstone> cloudTombstones,
  required String deviceId,
  required int studentClock,
});
```

规则按设计文档 3.3。ID 重排：先保留本地学生 id，再按 uid 排序处理云端独有；冲突时分配该班 `max(id)+1`。

## 任务 5：历史分片完整性

### 测试 `test/history_stream_manager_test.dart`

1. 中间分片缺失：`readFrom` 抛 `IncompleteStreamException`，游标不前进。
2. 恢复分片后可完整读取。
3. 旧 meta 无 `shard_counts`：仍能读取。
4. 分片写成功、meta 写失败后重试：`appendOwn` 重建 meta，`total` 与分片一致。
5. 尾片在 meta 快照后增长：只消费到 `last_shard_count`，下一次再取新增。

### 实现 `lib/services/cloud/history_stream_manager.dart`

- `StreamMeta.shardCounts`，JSON `shard_counts`。
- `appendOwn` 维护 `shardCounts`；`pending.isEmpty` 时校验/重建 meta。
- `_readShard` 区分 not-found 与空片；not-found 抛 `IncompleteStreamException`。
- `readFrom` 按 `shardCounts` 校验；尾片按 `lastShardCount` 截断。
- `pullAll` 捕获单流异常，记 `PullResult.incompleteStreams`，不推进该流游标。
- `pullFullSnapshot` 任一流不完整抛错。

## 任务 6：CloudSyncService outbox 锁、学生同步、清空文档

### 测试 `test/cloud_sync_v2_test.dart` 扩展

1. 上传暂停期间 enqueue 的新记录不被 flush 成功后的旧快照覆盖。
2. 学生先读-合并-写；两台设备交错编辑后双方看到并集。
3. 墓碑压制旧客户端重新上传的已删除学生。
4. 清空文档合并：全局/班级/奖池取较晚时间。
5. 离线清空后 `clearsDirty` 保留，下一次 push 上传。
6. `syncStudents` 返回合并结果，且不整包覆盖本地独有学生。
7. `resetWorkspaceState` 清掉缓存状态。

### 实现 `lib/services/cloud/cloud_sync_service.dart`

- outbox 串行锁：`Future<void> _outboxLock = Future.value();`，读改写走 `_withOutboxLock`。
- `flushOutbox`：锁内取批次快照 → 网络追加 → 锁内按本批 UID 删除。
- `fetchStudents()`：读 `srlite.students` + `srlite.students.tombstones`。
- `syncStudents({local, localTombstones, deviceId, clock})`：读云端 → `mergeStudents` → 写回两个键 → 返回结果。
- `syncClears()`：读/合并/写 `srlite.clear.v2`。
- `pullAll` 返回 `students`、`studentTombstones`、`clearState`；过滤按全局/班级/奖池。
- `CloudFullSnapshot` 增加 `studentTombstones`、`clearState`。
- `pushAll` 去掉 `students` 参数（或保留但忽略）；学生由 `syncStudents` 单独同步。
- 墓碑序列化超过 32 KiB 时丢弃 365 天前旧墓碑。

## 任务 7：AppProvider 学生修订、墓碑、清空同步

### 测试

- `test/student_sync_test.dart` 纯函数已覆盖合并。
- `test/cloud_sync_v2_test.dart` 覆盖服务层。
- 新增 `test/app_provider_student_sync_test.dart`：
  1. 新增学生分配 uid/rev，`studentsDirty=true`。
  2. 编辑/删除学生 rev 递增，删除写墓碑。
  3. 班级重命名 uid 不变、rev 递增；班级删除写墓碑。
  4. `pushToCloud` 只在 dirty 时调用 `syncStudents`。
  5. `pullFromCloud` 合并云端学生并应用。
  6. 离线清空：本地立即生效，`clearsDirty=true`；恢复网络后 push 上传。
  7. 拉取到云端清空后本地旧记录被删除，outbox 同范围清理。

### 实现 `lib/providers/app_provider.dart`

- 字段：`_studentClock`、`_studentSeq`、`_studentsDirty`、`_studentTombstones`、`_clearsDirty`、`_clearedClasses`、`_clearedPools`。
- `_touchStudent(Student)`：`rev = ++_studentClock`，`revBy = _deviceId`。
- `_tombstoneStudent(Student)`：写墓碑，移除学生。
- 所有学生变更点调用 `_touchStudent` / `_tombstoneStudent` 并置 dirty。
- `pushToCloud`：`pushAll(ownRollcall, ownLottery)` + 若 `_studentsDirty` 则 `syncStudents` + 若 `_clearsDirty` 则 `syncClears`。
- `pullFromCloud`：`syncStudents` 合并 → 应用 → `_applyCloudClears()`。
- `clearHistory({className})`、`clearLotteryHistory({poolName})`：本地清空 + `markCleared(scope)` + 尝试 `syncClears`。
- `_applyCloudClears`：删除本地早于清空时间的记录，清 outbox 同范围。
- 登录初始同步：新工作区克隆；已有工作区按 3.4。

## 任务 8：UI 清空提示与按奖池清空

- `rollcall_history_detail_screen.dart`：清空弹窗加「其他登录同一账号的设备也会同步清空」。
- `lottery_history_detail_screen.dart`：同上；按奖池清空改调 `AppProvider.clearLotteryHistory(poolName: ...)`。
- 抽奖全局清空改调 `AppProvider.clearLotteryHistory()`，不再直接调 `LotteryService`。

## 任务 9：测试适配与全量验证

1. `test/app_provider_animation_mode_test.dart`、`test/app_provider_non_repeat_test.dart` 改为 `await provider.ready` + 显式播种学生。
2. `test/login_initial_sync_test.dart`、`test/history_refresh_test.dart` 适配 `setAuthState` 新参数；保留旧兼容路径的测试继续不传 userId。
3. 新增工作区测试使用 `userId` 并断言 guest 不变。
4. `flutter test --reporter compact` 全量通过（允许原有 skip）。
5. `flutter analyze` 只关注新增错误；不修改 `analysis_options.yaml`。

## 提交建议

按任务分提交：

1. `feat(data): isolate account workspaces and drop default roster`
2. `feat(provider): switch workspaces on auth changes`
3. `feat(sync): merge students by uid and sync clears`
4. `fix(sync): validate shard completeness and outbox ack`
5. `feat(ui): sync clear prompts and pool clears`
6. `test: cover workspace isolation and sync v2.1`
