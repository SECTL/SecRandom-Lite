# 云同步 v2.1：学生名单合并、清空同步与分片完整性

状态：已实现（2026-10-30）。用户已确认「清空历史需要跨设备同步」。

## 1. 目标

在不改服务端、继续使用 SECTL 云 KV API 的前提下，修掉 v2 同步里四个会丢数据或让两端不一致的问题：

1. 学生名单整包覆盖：两台设备同时改名单，后推送的直接盖掉先推送的。
2. 清空只在本机生效：另一台设备仍能看到旧记录；按班级清空后，下次登录初始同步还会把记录并回来。
3. 增量拉取把缺失分片当空：中间分片瞬时缺失时游标照样前进，记录永久跳过。
4. outbox 上传期间新入队的记录被旧快照覆盖；分片写成功但 meta 写失败后，重试只去重不补 meta。

同时保留现有优点：每设备 append-only 历史流、`uid` 并集去重、按设备统计贡献求和、本地优先与离线 outbox。

在此基础上加入**完整账号工作区隔离**：本地数据按账号分开存放，登录时账号工作区不存在就从云端克隆，guest 工作区原样保留、不合并；并移除内置默认 40 人学生名单。详见第 11 节。

## 2. 非目标

- 不引入服务端事务、CAS、条件写或新的后端接口。
- 不改变历史记录、抽奖记录的云端键名和 `uid` 规则。
- 不做实时推送；同步时机维持现状（登录、防抖推送、前台节流、手动同步）。
- 不做设备注册表 TTL 清理；留作后续。
- 不把统计贡献改成可回退的 CRDT；现有 G-Counter 求和保留。
- 不做账号工作区的删除/清理 UI；退出登录只切回 guest，不删账号数据。
- 不自动把 guest 数据导入账号；需要迁移时由用户通过现有导出/导入功能手动完成。

## 3. 学生名单同步

### 3.1 身份：稳定 uid，本地 id 只用于界面

`(className, id)` 不能做同步身份：两台设备离线各加一名学生，都会分配同一个 `max(id)+1`，合并时会把两个不同学生当成同一个人。`id` 还会在删除最高 id 后被复用，旧墓碑可能压掉新学生。

因此：

- `Student` 增加 `uid`（String）：同步身份，生成后不变。
- `Student` 保留 `id`（int）：只用于本机界面排序、编辑和删除定位。
- 新学生 uid：`<deviceId>:s<studentSeq>`，`studentSeq` 是 `sync_state.json` 里持久化的单调计数器。
- 旧学生没有 uid：按 `legacy:<sha256(className|id|name)[:32]>` 派生并写回本地文件。两台设备对同一份旧名单派生出相同 uid；名字或 id 不同的学生派生不同 uid，宁可多留也不误合并。
- 合并后如果云端学生的 `(className, id)` 和本地另一个 uid 的学生冲突，给云端学生分配新的本地 id（该班 `max(id)+1`），uid 不变。这样界面上的编辑/删除不会串人。
- `toJson` 写入 `uid`；`rev > 0` 时再写 `rev` / `rev_by`。旧客户端忽略这些字段。

`Student` 另增：

- `rev`：逻辑修订号，`int`，旧数据默认 `0`。
- `revBy`：写入该修订的设备 ID，`String`，旧数据默认空串。

墓碑按 uid 存在独立云端键 `srlite.students.tombstones`：

```json
{
  "<uid>": {"rev": 7, "by": "device-a", "at": "2026-10-30T12:00:00.000"}
}
```

单独一个键的原因：旧客户端仍把 `srlite.students` 当纯数组解析；墓碑键它们不认识，会原样忽略。新客户端用墓碑压制旧客户端可能重新上传的已删除学生。

本地墓碑存 `sync_state.json` 的 `student_tombstones`，结构与云端一致。

### 3.2 修订号规则

使用 Lamport 计数器，不用设备时间，避免时钟偏差：

- `LocalSyncState.studentClock`：本机已见到的最大学生修订号。
- 新增学生：`uid = <deviceId>:s<++studentSeq>`，`rev = ++studentClock`，`revBy = deviceId`。
- 修改学生：uid 不变，`rev = ++studentClock`，`revBy = deviceId`。
- 删除学生：写墓碑 `{rev: ++studentClock, by: deviceId, at: now}`，从 `_allStudents` 移除。
- 拉取到云端 `rev` 时：`studentClock = max(studentClock, cloudRev)`。
- 比较两个修订：先比 `rev`，再比 `revBy` 字典序。`(rev, revBy)` 大者胜。

班级重命名：uid 不变，只改 `className` 并递增 `rev`。班级删除：该班每个学生写一条 uid 墓碑。这样不再需要「旧键墓碑 + 新键新增」的双写。

### 3.3 合并算法

新增纯函数 `mergeStudents`（`lib/services/cloud/student_sync.dart`），输入本地学生、本地墓碑、云端学生、云端墓碑、`deviceId`、`studentClock`，输出：

- `students`：合并后的学生列表（本地 id 已去重）
- `tombstones`：合并后的墓碑
- `studentClock`：推进后的计数器
- `changed`：本地是否需要落盘
- `needsPush`：云端是否需要更新

规则：

1. 键为 `uid`。
2. 同一 uid 的存活记录：`(rev, revBy)` 大者胜；完全相等时本地内容胜。
3. 墓碑与存活记录：`(rev, by)` 大者胜。墓碑胜则删除该学生；存活记录胜则丢弃该墓碑。
4. 键的并集：云端独有的存活记录加入本地；本地独有的存活记录保留并标记 `needsPush`。
5. `rev == 0` 的旧数据：两端都旧且内容相同则保持 0；内容不同或本地独有时，本地胜并分配 `rev = ++studentClock`、`revBy = deviceId`，写回云端后收敛。云端 `rev > 0` 时云端胜；本地 `rev > 0` 时本地胜。
6. 合并完成后按 `(className, id)` 检查本地 id 冲突；冲突的后到者分配该班新 id。排序按 uid 保证确定性。

第 5 条是关键：如果旧数据以 `rev == 0` 原样写回，两台设备会每次同步都「本地胜」并互相覆盖，永远不收敛。因此本地胜的旧记录必须在推送前拿到新修订号。

### 3.4 推送与拉取

`CloudSyncService` 增加：

- `fetchStudents()`：读 `srlite.students` 与 `srlite.students.tombstones`，兼容旧数组格式。
- `syncStudents({local, localTombstones, deviceId, clock})`：读云端 → `mergeStudents` → 写回两个键 → 返回合并结果。这是「先合并再写」的推送，不是整包覆盖。

`AppProvider`：

- 所有学生变更点（新增、编辑、删除、批量导入、班级重命名/删除、小组重命名/删除）都打修订/墓碑，并置持久化的 `studentsDirty = true`。
- `pushToCloud`：仅当 `studentsDirty` 时调用 `syncStudents`，成功后落盘合并结果并清脏标记。`pushAll` 不再无条件携带学生名单。
- `pullFromCloud`：调用 `syncStudents`，把合并结果应用到 `_allStudents`，再 `_applyPulledStudents`。
- 登录初始同步：
  - 新设备（无本地基线）：以云端学生 + 墓碑为准，严格覆盖本地占位名单。
  - 已有本地基线：`mergeStudents` 并集合并，本地独有学生补推。
  - 云端为空：本地是唯一数据源，本地名单整体补推，不看 `studentsDirty`。

### 3.5 本地基线判定

现有 `_hasLocalDataBaseline` 只看历史、outbox 和同步状态，不看学生。一个用户从没登录过、但在本地建好了名单，会被当成新设备，名单被云端覆盖。

修正：

- `LocalSyncState` 增加持久化的 `studentsDirty`。
- 学生发生任何变更时置 true，成功同步后置 false。
- 升级迁移：首次加载时，如果本地学生与旧版内置默认 40 人名单不同，视为用户数据，置 `studentsDirty = true`。
- `_hasLocalDataBaseline` 把 `studentsDirty`、`studentClock`、`student_tombstones`、`clearsDirty` 纳入判断。
- 只有「云端有数据 + 本地无历史/无 outbox/无同步状态/无学生变更 + `studentsDirty == false`」才走严格覆盖。
- 以上状态都在账号工作区内，天然按账号隔离。

### 3.6 兼容性

- 旧客户端仍能读 `srlite.students` 的数组；新增字段被忽略。
- 旧客户端不认识墓碑键，可能把已删除学生重新推回来；新客户端下次合并时用更高 `rev` 的墓碑再次压制。
- 旧客户端推送的 `rev == 0` 修改，无法胜过新客户端已产生的 `rev > 0` 修改；这是混合版本的已知降级。
- 旧数据派生 uid 依赖 `className|id|name`；如果两端旧数据在这三项上不同，会被当成两个学生。宁可重复，不静默合并。

## 4. 清空历史同步

### 4.1 云端清空文档

新增键 `srlite.clear.v2`：

```json
{
  "rollcall": {"all": "2026-10-30T12:00:00.000", "classes": {"1": "2026-10-30T12:05:00.000"}},
  "lottery": {"all": "2026-10-30T12:10:00.000", "pools": {"期末奖池": "2026-10-30T12:15:00.000"}}
}
```

时间使用本地时间，与现有 `draw_time` / `drawTime` 的解析方式一致。记录仍在云端保留，属于软删除；清空只影响可见视图。

点名支持「全部」和「按班级」；抽奖支持「全部」和「按奖池」。现有抽奖详情页确实有按奖池清空，本次一并纳入。

### 4.2 本地状态

`LocalSyncState`：

- 保留 `clearedAt`（kind -> DateTime，全局）。
- 新增 `clearedClasses`（kind -> className -> DateTime）。
- 新增 `clearedPools`（poolName -> DateTime，仅抽奖）。
- 新增持久化的 `clearsDirty`。

`markCleared(kind, at, {className, poolName})`：

- 全局清空：更新 `clearedAt[kind]`，取较晚时间。
- 班级清空：更新 `clearedClasses[kind][className]`，取较晚时间。
- 奖池清空：更新 `clearedPools[poolName]`，取较晚时间。
- 从 outbox 移除该范围内的待传记录（全局清空清空整个 kind；班级/奖池只删匹配记录）。
- 置 `clearsDirty = true` 并落盘。**清空本身不依赖网络，离线也必须成功。**
- 尝试 `syncClears()`；失败只记日志，保留脏标记，下一次推送/登录重试。

### 4.3 拉取与应用

`CloudSyncService.syncClears()`：读云端文档，与本地状态按 scope 取较晚时间合并；如果本地更新则写回云端。返回合并后的状态和 `needsPush`。

`pullAll` / `pullFullSnapshot`：

- 拉取云端清空文档并合并进本地状态。
- 远端记录按以下规则过滤：
  - 全局清空：记录时间早于 `clearedAt[kind]` 则跳过。
  - 班级清空：点名记录 `class_name` 匹配且时间早于该班清空时间则跳过。
  - 奖池清空：抽奖记录 `poolName` 匹配且时间早于该奖池清空时间则跳过。
- 抽奖记录的时间取 `drawTime`；点名取 `draw_time`。

`AppProvider` 在拉取后调用 `_applyCloudClears()`：

- 删除本地早于合并后清空时间的记录（按全局/班级/奖池 scope）。
- 从 outbox 删除同范围记录，防止它们被重新上传。
- 点名清空不动统计；抽奖全局清空沿用现有本地语义，重置本机抽奖统计贡献；按奖池清空不动统计（与现有行为一致）。
- 落盘并刷新 `_history` / 抽奖记录视图。

### 4.4 UI

- 点名「清空全部」和「清空当前班级」的确认弹窗增加一句「其他登录同一账号的设备也会同步清空」。
- 抽奖「清空全部」和「清空当前奖池」同样增加提示。
- 抽奖详情页的按奖池清空改走 `AppProvider.clearLotteryHistory(poolName)`，不再直接调 `LotteryService`，否则不会写清空文档和 outbox。
- 全量清空仍保留「无法撤销」提示；云端记录实际是软删除，但产品上不提供恢复入口。

### 4.5 兼容性与边界

- 旧客户端忽略 `srlite.clear.v2`，仍能看到旧记录；它们重新上传的旧记录会被新客户端按清空时间过滤。
- 旧 `cleared_at` 在首次同步时并入云端文档，不需要单独迁移脚本。
- 时钟偏差：清空时间与记录时间都来自设备本地时钟。误差较大时可能多保留或少保留边界附近的记录；本次不引入服务端时间校准，文档记录此边界。
- 清空操作离线成功，但另一台设备要等下一次拉取才生效；这是「最终一致」，不是实时删除。

## 5. 分片完整性

### 5.1 meta 增加分片计数

`StreamMeta` 增加 `shardCounts: List<int>`，序列化为 `shard_counts`。旧 meta 没有该字段时为空列表，走兼容路径。

`appendOwn`：

- 每次写分片后同步维护 `shardCounts`。
- 如果 `pending` 为空（UID 已全部存在），读取实际分片计数；与 meta 不一致时重建 meta 并写回。这修复「分片写成功、meta 写失败、重试只去重不补 meta」的问题。

### 5.2 读取校验

`readFrom`：

- 分片读取区分「不存在」与「空片」。不存在时抛 `IncompleteStreamException`，不再当空数组。
- `meta.shardCounts` 非空时：
  - 非尾片：实际条数必须等于 `shardCounts[i]`。
  - 尾片：按 meta 快照的 `lastShardCount` 截断读取，实际条数少于该值视为不完整；多于该值时只消费到该值，避免消费尚未发布 meta 的追加内容。
- `meta.shardCounts` 为空（旧 meta）：非尾片 not-found 仍抛错；尾片允许增长。
- 只有全部校验通过才返回新游标。

`pullAll`：

- 单条设备流不完整时捕获异常，记录到 `PullResult.incompleteStreams`，继续处理其他设备流；该流游标不推进。
- 整轮仍可成功返回其他流的数据，但调用方能看到不完整流列表。

`pullFullSnapshot`：

- 任一流不完整即抛错，保持「不完整快照不覆盖本地」的现有保护。

### 5.3 测试

- 中间分片缺失：`readFrom` 抛错，游标不前进；恢复分片后可完整读取。
- meta 计数缺失（旧格式）：仍能读取。
- 分片写成功、meta 写失败后重试：meta 自愈，total 与分片一致。
- 尾片在 meta 快照后增长：只消费到快照长度，下一次拉取再取新增。

## 6. outbox 并发

`CloudSyncService` 内部增加 outbox 串行锁（Future 链），`enqueueAll`、`removeFromOutbox`、`clearOutbox`、`markCleared` 的读改写都在锁内执行。

`flushOutbox`：

1. 在锁内取一份不可变批次快照。
2. 释放锁，执行网络追加。
3. 成功后重新读取最新 outbox，只按本批 UID 删除，不再用旧快照整体覆盖。

这样上传期间新入队的记录不会被清掉。

## 7. 墓碑容量

`srlite.students.tombstones` 是单个 KV。按一个学校几百名学生的规模，删除和班级删除产生的墓碑通常只有几百条，远小于现有 48 KiB 分片上限。

保守处理：

- 每条墓碑带 `at`。
- 写云端前序列化检查；超过 32 KiB 时，丢弃 `at` 早于 365 天的墓碑再写。
- 丢弃旧墓碑的代价是极旧的客户端可能重新带回已删除学生；新客户端仍会用剩余墓碑和修订号尽量压制。记录日志。
- 不做分片墓碑；如果未来学生规模大到超过上限，再改成按 uid 哈希分片。

## 8. 验收

必须新增或更新的测试：

- `student_sync_test.dart`：
  - 云端独有、本地独有、高 `rev` 胜、墓碑胜、平局。
  - 旧 `rev == 0` 本地胜后分配新 rev，第二次合并不再翻转。
  - 不同 uid、相同 `(className, id)` 的学生合并后 id 被重排，两个学生都保留。
  - 班级重命名后 uid 不变、rev 递增。
- `cloud_sync_v2_test.dart`：
  - 学生名单先合并再推送，两台设备交错编辑后双方都看到并集。
  - 墓碑压制旧客户端重新上传的已删除学生。
  - 清空文档合并、按全局/班级/奖池过滤、outbox 同范围清理。
  - 离线清空后 `clearsDirty` 保留，下一次 push 上传。
  - 上传暂停期间 enqueue 的新记录不被覆盖。
- `history_stream_manager_test.dart`：缺片不推进游标、meta 自愈、旧 meta 兼容。
- `sync_state_test.dart`：新字段（uid 相关、`studentClock`、`studentsDirty`、`clearsDirty`、`clearedClasses`、`clearedPools`、墓碑）往返序列化。
- `workspace_isolation_test.dart`：
  - guest 有数据时登录新账号：账号工作区从云端克隆，guest 文件不变。
  - 新账号云端为空：账号工作区为空，guest 数据不上传。
  - 账号工作区已存在：再次登录加载本地，不重复克隆。
  - A→B→A：两个账号的数据与配置互不影响。
  - 退出登录：回到 guest，账号工作区保留。
  - 设备 UUID / 自动同步开关保持全局。
  - 新装学生名单为空；旧版默认 40 人不被自动删除。
  - 首次登录离线：账号工作区保持未初始化，不把空数据推上云。
- `login_initial_sync_test.dart` / `history_refresh_test.dart`：适配新签名，保持「新设备云端覆盖、老设备并集合并」，并覆盖「离线建好名单后首次登录不被覆盖」。
- 全量 `flutter test` 通过。

## 9. 实施顺序

1. `DataService` 工作区路径/存储前缀/存在性标记；移除默认 40 人；工作区单测。
2. `AppProvider` 认证切换、guest/账号工作区加载、首登克隆、`ready`；`main.dart` 传 userId；工作区隔离测试。
3. `sync_state.dart` 新字段与序列化；`student_sync.dart` 纯函数 + 单测。
4. `history_stream_manager.dart` 分片计数、缺片抛错、meta 自愈 + 单测。
5. `cloud_sync_service.dart` outbox 锁、flush 按 UID ack、学生 fetch/sync、清空文档、`resetWorkspaceState` + 单测。
6. `AppProvider` 学生 uid/修订/墓碑、清空调用、拉取合并、持久化脏标记。
7. `Student` 模型与本地 uid 迁移；`DataService` 写回派生 uid。
8. UI 清空提示与按奖池清空改走 AppProvider。
9. 适配既有测试，跑全量测试。

## 10. 已知边界

- 服务端没有 CAS：学生同步仍是「读-合并-写」，两个设备在同一瞬间推送时仍可能丢一次更新；合并把窗口缩小到一次网络往返，但不能彻底消除。
- 清空时间与记录时间都来自本地时钟，跨设备时钟偏差会影响边界记录。
- 旧客户端不参与墓碑和修订号，删除/编辑的跨版本一致性只能由新客户端事后修复。
- 旧数据派生 uid 依赖 `className|id|name`，极端情况下会把两个不同学生当成一个；这是迁移的保守边界。
- 设备注册表 TTL、服务端权威去重、实时推送不在本次范围。

## 11. 账号工作区隔离

### 11.1 行为

本地数据按账号分成独立工作区。未登录使用 `guest` 工作区；登录后使用该账号的工作区。

| 场景 | 行为 |
| --- | --- |
| 登录账号 A，本机没有 A 的工作区 | 创建 A 的工作区，从云端完整克隆；guest 工作区原样保留，不参与合并 |
| 登录账号 A，本机已有 A 的工作区 | 加载 A 的本地数据，按第 3.4 节的初始同步规则处理 |
| 账号 A 切换到账号 B | A 的工作区原样保留；B 使用自己的目录；两边数据、配置、同步状态互不影响 |
| 退出登录 | 切回 guest 工作区；账号 A 的工作区保留在磁盘，不删除 |
| 新账号云端为空 | 创建空工作区并初始化空基线；不上传 guest 数据 |
| 首次登录时离线 | 工作区保持「未初始化」，显示空数据并提示同步失败；不把空数据推上云；下次登录/手动同步重试克隆 |
| guest 有数据，用户想带到账号 | 由用户通过导出/导入手动完成；本次不做自动迁移弹窗 |

工作区隔离的是：学生名单、点名历史、抽奖记录、奖池、配置、`sync_state.json`、`sync_outbox.json`、墓碑与清空文档的本地副本。

保持全局的只有：设备 UUID（`TokenManager`）、自动同步开关（`SharedPreferences`）、日志。这样同一台设备上的所有账号仍被识别为同一台设备，但不会共享业务数据。

### 11.2 工作区 key 与路径

工作区 key：

- guest：`guest`。
- 账号：`acct_<sha256(userId)[:24]>`，只保留哈希前 24 个十六进制字符，不在磁盘上写邮箱或原始 userId。
- key 只允许 `[A-Za-z0-9_]+`，防止路径穿越。

路径：

| 平台 | guest | 账号 |
| --- | --- | --- |
| 桌面/移动 | `<data>/`（沿用旧版根目录） | `<data>/accounts/<key>/` |
| Web | 旧版无前缀 localStorage key | `<key>:<原文件名>` |

guest 直接使用旧版根目录/旧 key，因此升级后老用户的数据仍在 guest，不需要搬迁文件；账号目录只在首次登录时创建。

每个工作区目录内有一个 `workspace.json` 标记文件：

```json
{"version": 1, "created_at": "2026-10-30T12:00:00.000"}
```

`workspaceExists(key)` 以标记文件为准；如果标记缺失但目录里已有已知数据文件，也视为存在，避免旧版本或半初始化目录被误判为新工作区而重复克隆。`guest` 永远视为存在。

### 11.3 DataService

`DataService` 增加：

- `static String currentWorkspace`，默认 `guest`。
- `static String workspaceKeyForUser(String userId)`。
- `static void setWorkspace(String key)`。
- `static Future<bool> workspaceExists(String key)`。
- `static Future<void> ensureWorkspace(String key)`：创建目录并写 `workspace.json`；Web 写 `<key>:workspace.json`。
- `static void resetWorkspaceToGuest()`（测试与退出登录用）。

所有公开读写方法在入口捕获一次 `currentWorkspace`，后续路径/存储 key 都使用这个快照。这样切换工作区时，已经在飞行中的旧工作区写入会落回旧目录，不会漏进新工作区。

`loadAllPrizePools` 的目录扫描只扫当前工作区目录；Web 只匹配当前工作区前缀，避免 guest 扫到账号奖池或反过来。

### 11.4 AppProvider 生命周期

`AppProvider` 增加：

- `Future<void> get ready`：首次 `_loadData()` 完成。
- `setAuthState(bool loggedIn, {String? userId})`：
  - 未登录 → guest。
  - 已登录且 `userId` 非空 → `workspaceKeyForUser(userId)`。
  - 已登录但 `userId` 为空：保留当前工作区。这是测试和旧调用的兼容路径；生产入口 `main.dart` 始终传 `userId`。
- 内部用 Future 链串行化认证切换，并用 `_workspaceEpoch` 丢弃过期的异步结果。
- 切换前：取消防抖、取消云重试、等待待保存配置、等待当前加载完成。
- 切换后：`DataService.setWorkspace` → `cloudSyncService.resetWorkspaceState()` → 重新 `_loadData()` → 设置登录态。
- `main.dart` 的认证监听改为：
  ```dart
  final user = _authProvider.userInfo;
  _appProvider.setAuthState(_authProvider.isLoggedIn, userId: user?.userId);
  ```

`CloudSyncService` 增加 `resetWorkspaceState()`：清掉缓存的 `LocalSyncState`、默认本地存储实例、远端设备发现缓存、状态/错误/重试计时器。设备 UUID 不重置。

### 11.5 首次登录克隆

新增工作区登录时：

1. 先检查 `workspaceExists(key)`；不存在则 `ensureWorkspace(key)`。
2. 切到该工作区并加载（空学生、空历史、空配置）。
3. `cloudHasAnyData()`：
   - `false`：写入空基线，置 `baselineInitialized = true`、`legacyUploaded = true`，清空 outbox，`_cloudDirty = false`。**不 push。**
   - `true`：`pullFullSnapshot()`，严格覆盖本地：学生 + 墓碑、点名历史、抽奖记录、统计贡献、清空文档；重置 `ownSeq`、`pulled`、`clearedAt`/`clearedClasses`/`clearedPools`、outbox；置 `baselineInitialized = true`、`legacyUploaded = true`。
4. 克隆成功前 `_workspaceReady = false`，`pushToCloud` / `pullFromCloud` 直接返回 false，避免把空工作区推上云覆盖真实数据。
5. 克隆失败：保留空工作区与 `baselineInitialized = false`，不 push；下次登录、手动同步或前台恢复时重试。

已有工作区登录时沿用第 3.4 节：

- 云端为空 → 本地是唯一数据源，本地名单/历史整体补推。
- 云端有数据、本地无基线 → 严格覆盖（同克隆）。
- 云端有数据、本地有基线 → 并集合并，本地独有补推。

`pullFullSnapshot` 需要返回墓碑与清空文档；`CloudFullSnapshot` 增加 `studentTombstones`、`clearState` 字段。

### 11.6 默认 40 人名单移除

- `DataService.loadStudents()` 在文件缺失、为空或解析失败时返回空列表，不再生成「学生 1..40」。
- 删除 `_getInitialStudents()` 的 40 人生成逻辑。
- 已有用户的 40 人文件不自动删除；升级时如果名单与旧版默认 40 人完全一致，视为默认占位、不置 `studentsDirty`；否则视为用户数据并置 `studentsDirty = true`。
- 新装用户首次打开是空名单，界面显示空状态；用户自行添加学生或登录账号从云端克隆。
- 测试不再依赖默认学生，改用 `provider.addStudentToClass(...)` 或直接 `DataService.saveStudents([...])` 播种。

### 11.7 兼容性与边界

- 旧版本的数据都在根目录/无前缀 key，升级后自然归入 guest；不会自动归到某个账号。
- 旧版本用户升级后直接登录账号：guest 数据不会进入账号，账号从云端克隆。这是有意的行为变化，避免 A 的数据进入 B 的云。
- 账号工作区按 userId 哈希命名，同一账号在不同设备上得到同一个 key，但本地目录内容各自独立；云端仍是跨设备同步源。
- 首次登录必须联网才能克隆；离线时账号工作区为空，不会回退显示 guest 数据（那会造成串号）。
- 工作区只增不减；磁盘占用随登录过的账号数增长。删除本地账号数据不在本次范围。
- Web localStorage 配额有限，多账号会更快触及上限；本次只做前缀隔离，不做配额管理。
- 账号工作区标记存在但数据文件损坏时，按空数据处理；`baselineInitialized` 缺失则走克隆路径，避免把损坏数据推上云。

### 11.8 测试

- `DataService` 工作区单测：key 派生稳定、guest 走根目录、账号走 `accounts/<key>`、`workspaceExists` 标记与回退、Web key 前缀、`loadAllPrizePools` 不跨工作区。
- `workspace_isolation_test.dart`：
  - guest 有历史/学生时登录新账号（云端有数据）→ 账号数据 = 云端，guest 文件字节不变。
  - 新账号云端为空 → 账号为空，guest 未被上传。
  - 已有账号工作区再次登录 → 不重复克隆，保留本地新增数据。
  - A→B→A → 两边数据与主题配置互不影响。
  - 退出登录 → 回到 guest。
  - 首次登录离线 → `baselineInitialized` 仍为 false，push 被拒绝，云端不变。
  - 默认 40 人移除与旧数据保留。
- `AppProvider.ready` 让测试不再靠 `totalCount > 0` 轮询；现有依赖默认学生的测试改为显式播种。
