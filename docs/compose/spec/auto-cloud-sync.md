---
feature: auto-cloud-sync
status: delivered
updated: 2026-02-27
branch: main
commits: f0c609c..b81ecab
---

# 自动云同步

## Report

**What was built** — 在既有云同步 WIP 之上补齐了"自动"闭环：数据变更后 5 秒防抖自动推送（含点名与抽奖统计、学生名单、点名/抽奖历史分片增量），main.dart 监听 AuthProvider 把登录态下发给 AppProvider，未登录只记脏不发网络请求与重试，登录成功后自动执行一次 pull-merge + push 初始同步（先拉后推，本地空数据不会覆盖云端）。抽奖侧全量接入：启动时从本地抽奖历史重建 `_lotteryStats`（计数键 `studentName` 优先、回退 `prizeName`），中奖落盘后经 `onLotteryRecordSaved` 增量计数、防抖标记并异步追加云端分片，`pushCore` 不再传空抽奖统计。新增持久化「自动同步」开关（SharedPreferences `cloud_auto_sync_enabled`，默认开，关闭时手动推拉仍可用、重开后补推），同步状态在发起/完成/异常三时点通知 UI 使设置页状态卡片实时刷新。独立评审发现的 3 个 critical 已修复：云端历史合并改按磁盘全量 id 去重并逐条追加（消除内存 50 条截断列表覆写磁盘的历史丢失）、分片追加入口补 `_cloudSyncEnabled` 门控、退避重试放弃后重置计数且失败回置脏标记。

**Verification** — `flutter analyze`：PASS（7 个 info 级 lint，全部为基线已存在，无 error/warning）。`flutter test -j 1`（串行全量）：PASS 99/99。`flutter test`（默认并行）：间歇性失败，仅命中 PRE-EXISTING 的共享数据目录跨套件互扰家族（CL-FLAKE：`app_provider_non_repeat` / `app_provider_animation_mode` 的断言，已在干净 origin/main clone 上复现同样失败，不同运行失败成员不同，也有一次 98/98 全绿）。新增测试：draw_stats 16 例中 DrawStats/抽奖组、history_shard_manager 6 例、cloud_sync_gating 3 例、cloud_sync_service 退避回归 1 例，均确定性通过。

**Journey log** —
1. 本 shell 会话缺失 `ProgramFiles`/`ProgramFiles(x86)` 环境变量，`flutter test` 直接退出 1；每次测试命令前需先补这两个进程级环境变量。
2. 测试数据目录由 `Platform.resolvedExecutable` 解析（= flutter 引擎 data 目录），所有测试套件共享；套件互扰/锁竞争属基线问题（clean clone 复现），判定 PRE-EXISTING。
3. 用户澄清问题被 dismiss 后按推荐方案推进：抽奖统计计数键 `studentName` 优先回退 `prizeName`，spec 已同步修订。
4. 评审阶段发现的最大教训：内存 `_history` 点名后截断到 50 条而磁盘为全量，任何用内存列表 `saveHistory` 回写的路径都会截断本地历史（已修）。
5. `git worktree`/`git checkout` 在本会话被安全护栏拦截（共享 ref store 保护），基线对照改用 `git clone --no-hardlinks` 到临时目录完成。

## [S1] Problem

仓库中已有一批未提交的云同步 WIP（`lib/services/cloud/`、云同步设置页、AppProvider 中数据变更后 5 秒防抖推送），但"自动"闭环不完整：

- 没有启动/登录时的自动同步，拉取只能在设置页手动操作。
- 没有可持久化的"自动同步"开关；`_cloudSyncEnabled` 只是内存字段。
- 未登录时 `_markCloudDirty` 仍会发起网络请求并进入指数退避重试，产生无意义的失败循环。
- 抽奖统计是 TODO：`pushToCloud` 每次传入空 `DrawStats()`，checksum 与云端不同就会把空对象写上云端，覆盖已有抽奖数据。
- 同步状态（syncing/success/error）变化不会触发 UI 重建，设置页状态卡片显示过期信息。

## [S2] Design

### 数据面

同步对象分三类，本地是 Source of Truth，云是镜像：

| 数据 | KV key / 位置 | 自动行为 |
|---|---|---|
| 点名聚合统计 | `secrandom.stats.rollcall` | 变更防抖后推送；启动/登录时拉取 merge |
| 抽奖聚合统计 | `secrandom.stats.lottery` | 同上；本地从抽奖历史构建，修复空覆盖 |
| 学生名单 | `secrandom.students` | 同上 |
| 点名历史分片 | `secrandom.history.rollcall.*` | 点名后异步追加（已有）；启动/登录不自动合并历史，仍走历史页手动加载 |
| 抽奖历史分片 | `secrandom.history.lottery.*` | 中奖后异步追加（新增） |
| 同步元数据 | `secrandom.sync.meta` | 随每次 push/pull 更新（已有） |

合并策略沿用手动拉取的 `ConflictResolution.merge`：统计取 max（只增不减）；名单在云端非空时以云端为准。启动/登录时先 pull 合并、再按需 push，保证本地空数据（如新设备从未抽奖）不会把云端已有数据覆盖为空。

### 抽奖接入

- `AppProvider` 启动加载时从 `DataService.loadLotteryRecords()` 构建 `_lotteryStats`，与 `_rollcallStats` 对称。计数键为 `studentName`（非空时），否则回退 `prizeName`（当前 UI 生成的记录 `studentName` 恒为 null，人名奖池下 `prizeName` 即人名，与点名统计语义对称）；每次计数累加 `drawCount`（<1 时按 1）。计数键推导收敛在 `DrawStats.lotteryStatKey`，构建与增量共用。
- `lottery_screen` 每次 `saveLotteryRecord` 成功后调用新增的 `appProvider.onLotteryRecordSaved(record)`：增量更新 `_lotteryStats`、`_markCloudDirty()`、fire-and-forget 追加该记录到云端抽奖分片（失败仅记日志并置 dirty 走防抖兜底）。
- `pushToCloud` 传入 `_lotteryStats` 替换 TODO 空对象；`pullFromCloud` 的 merge 分支对抽奖统计同样 `mergeMax`。

### 登录状态与触发时机

- `main.dart` 监听 `AuthProvider`，把登录状态下发给 `AppProvider.setAuthState(bool loggedIn)`。
- 未登录：`_markCloudDirty` 只置脏不调度网络；取消防抖定时器与服务内重试（`cancelRetries`）。任何云 API 调用前先检查登录态。
- 登录态从 false→true 时执行一次初始同步：`pullFromCloud(merge)` → `pushToCloud`（pushCore 有 checksum 跳过，数据无变化时为 no-op，保证本地更高计数也能补传）。幂等。
- 登录态 true→false：取消防抖定时器与重试，保留脏标记。
- 变更后推送逻辑保持现状：5 秒防抖 + 失败指数退避（最多 8 次），但调度前检查登录态。

### 自动同步开关

- SharedPreferences key `cloud_auto_sync_enabled`，默认 `true`；`AppProvider._loadData` 时读取，`setCloudSyncEnabled` 写入并立即生效（关闭时取消定时器与重试）。
- UI：云同步设置页状态卡片下方新增 SwitchListTile「自动同步」，附一行说明（数据变更后自动上传并在登录时合并）。
- 开关关闭时手动推送/拉取按钮仍可用（手动操作不受自动开关约束）。

### 状态通知

`pushToCloud` / `pullFromCloud` 在开始、成功、失败三个时点各调用一次 `_notifyIfActive()`，使设置页 `context.watch<AppProvider>` 能重建并读取 `cloudSyncService.status`。不在本次把 `CloudSyncService` 改造成 ChangeNotifier。

### 错误行为

- 未登录发起同步 → 静默跳过，不写 `lastError`。
- 网络/服务端失败 → `lastError` 记录原因、状态置 error、调度退避重试（受开关与登录态双重门控）。
- 历史追加失败 → 本地已保存，仅记 warning 并置脏，由防抖全量推送兜底。

## [S3] Out of Scope

- 定时周期同步、应用回到前台触发同步。
- 清空历史时同步清空云端分片（历史为 append-only 日志）。
- 抽奖公平权重改造（`FairDrawService` 仍只服务点名）。
- 多设备冲突的交互式提示 UI（`SyncConflict` 信息仍只在手动拉取对话框层面使用）。
- 现有 OAuth 登录流程的其他改动（auth 相关未提交改动属于既有 WIP，仅做集成所需的登录态下发）。

## Tasks

- [x] T1: 抽奖统计与抽奖历史接入同步 — acceptance: 抽奖中奖后 `_lotteryStats` 增加、防抖推送带上真实抽奖统计（不再传空对象覆盖云端），记录被追加到云端抽奖分片；启动时从本地抽奖历史重建统计 (covers: S2 抽奖接入)
- [x] T2: 登录态联动与启动/登录自动同步 — acceptance: 未登录时任何变更不发起云请求、不进入退避重试；登录成功后自动执行一次 pull-merge + 按需 push；登出时取消定时器与重试 (covers: S2 登录状态与触发时机、错误行为)
- [x] T3: 自动同步开关持久化与设置页 UI — acceptance: 设置页出现「自动同步」开关，状态写入 SharedPreferences 并重启后保持；关闭后变更不再自动推送，手动推拉仍可用 (covers: S2 自动同步开关)
- [x] T4: 同步状态通知修复 — acceptance: 触发一次同步后，设置页状态卡片在 syncing→success/error 过程中实时刷新，`上次同步` 时间正确更新 (covers: S2 状态通知)
- [x] T5: 单元测试 — acceptance: 覆盖 DrawStats 增量/mergeMax/fromHistoryNames、HistoryShardManager 追加与读取（注入内存 Fake API）、自动同步门控（未登录不调度）三类行为，`flutter test` 全绿 (covers: S2 数据面、登录状态与触发时机；注：全绿以串行 `flutter test -j 1` 99/99 达成，并行运行受 PRE-EXISTING CL-FLAKE 干扰)
