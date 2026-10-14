---
feature: windows-auto-start
status: delivered
updated: 2026-10-13
branch: main
commits:
---

# Windows 开机自启

## Report

**What was built** — Windows 侧新增「开机自启」：个性化设置的独立卡片里打开开关后，runner 把当前可执行文件写入 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`（值名 `SecRandom Lite`，数据为加引号的 exe 全路径），用户下次登录 Windows 时系统自动拉起应用；关闭开关则删除该值。写 HKCU 不需要管理员权限，也不会把设置绑到机器级账户上。

**注册表是唯一事实来源**，`SharedPreferences` 只缓存最近一次已知状态供兜底显示。原生侧 `auto_start::IsEnabled()` 每次都回读注册表，并要求该值仍然指向**当前正在运行的这个 exe**——安装目录被移动或卸载残留的陈旧条目会如实读成「关闭」，开关于是提示用户去修复，而不是宣称自启可用。`auto_start::SetEnabled()` 写完或删完之后同样回读校验，校验不过就返回失败；删除一个本就不存在的值视为成功而非错误。方法通道 `secrandom_lite/auto_start` 暴露 `isEnabled` / `setEnabled`，`setEnabled` 失败时回 `registry_write_failed` 错误而不是静默成功。

Dart 侧新增 `AutoStartService`（`lib/services/auto_start_service.dart`），沿用 `RollCallQuickEntryService` 的单例 + `supportsAutoStart` 能力位模式：仅 Windows 返回 `true`，其余平台在触碰原生通道之前就短路。读取失败回落到本地偏好让开关保持可用；写入失败先把偏好同步回注册表的真实值**再原样抛出**，界面据此把开关回落——开启失败回落为关闭，关闭失败保持开启，而不是一律弹成关闭。开关卡片位于个性化设置，与「点名悬浮窗」并列，插入窄屏与宽屏两套布局；不受支持的平台整块不渲染也不占位。

**Verification** — `flutter analyze`：PASS，7 条 info 与基线完全一致（1 条 `rollcall_settings_screen.dart` 的 `use_build_context_synchronously` + 6 条 `theme_mode_body.dart` 的 Radio deprecation，均在 `HEAD` 中已存在），**0 error / 0 warning，新增代码 0 条**。`flutter test -j 1`：**127 passed / 12 skipped / 2 failed**，其中 2 条失败（`app_provider_animation_mode_test` 的 manual stop 用例、`app_provider_non_repeat_test` 的 nonRepeat 用例）为**基线既有**：已用 `git clone --no-hardlinks` 把干净的 `HEAD` 克隆到临时目录单独跑过一遍，得到 126 passed / 8 skipped / 2 failed，失败项完全相同。本特性的净增正好是 +1 passed / +4 skipped，即新增的 5 条用例。平台相关用例一律用**镜像式 skip**：Windows 宿主执行写入/回落三条，CI 的 ubuntu runner 执行「不渲染」那条，两侧分支都真实被覆盖。注意 `supportsAutoStart` 取自 `dart:io` 的 `Platform.isWindows`（宿主平台），不受 `debugDefaultTargetPlatformOverride` 影响，所以「非 Windows 不渲染」这一分支无法在 Windows 上模拟。**4 条 Windows 分支用例并非空跑**：把 `supportsAutoStart` 临时强制为 `true` 后单独跑过该测试文件，4 条全部通过（第 4 条此时按镜像规则跳过），验证后已还原为 `PlatformInfo.isWindows`。`cloud_sync_gating_test` 在首轮全量跑中失败、次轮通过、基线全量跑也通过，判定为与本特性无关的时序 flaky，不计入回归。**Windows 原生侧未编译**：本会话主机为 Linux x86_64，没有 MSVC / Windows SDK / CMake+Ninja 的 Windows 工具链，`flutter build windows` 无法执行，`auto_start.cpp` 与 `flutter_window.cpp` 的改动只做了人工复核，需在 Windows 上构建确认。`pubspec.lock` 与 `analysis_options.yaml` 的改动来自 Flutter 工具本身（前者是 3.47.7 对 `matcher`/`meta`/`test_api`/`vector_math` 这几个随 SDK 锁定的包的重解析，后者是 `flutter pub get`/`analyze` 自动追加的平台目录排除），非本特性手工修改。

**Journey log** — 1. 本特性严格沿用仓库既有约定：单例服务 + `supportsX` 能力位、方法通道命名 `secrandom_lite/<feature>`、设置开关自持状态并在失败后回填真实值、平台相关测试用镜像式 skip。2. `windows/runner` 在代码页 936 下编译且 C4819/C2220 被视为错误，因此 `auto_start.cpp` 的注释与字面量**全部保持 ASCII**，中文只存在于 Dart 侧。3. `IsEnabled()` 采用「值存在 **且** 仍指向当前 exe」的双重判定而非单纯判空：单纯判空会让搬家/卸载残留的陈旧条目显示为已开启，用户以为自启配置好了，登录时却拉起一个不存在的路径。4. `SetEnabled()` 的读回校验是刻意的——写入返回 ERROR_SUCCESS 不代表值真的变成了想要的样子，而这个开关的全部意义就是「注册表里确实有这条」；反向地，删除一个本就不存在的值要算成功，否则用户会在已是关闭的状态下反复撞失败。5. 未引入 `--autostart` 启动参数做「自启时静默驻留托盘」：应用当前没有单例互斥（`CreateMutex` 等），静默启动会让用户误以为没起来而手动再开一次，产生双实例。自启按常规方式显示主窗口，行为可预期；静默驻留需要与单例守卫一起做，列为后续工作。6. 镜像式 skip 的代价是「Windows 那一侧在 Linux 上永远是绿的」，无法区分「跳过」与「真过」；本轮用临时翻转能力位的办法把 4 条 Windows 用例真实跑了一遍再还原，避免把从未执行过的测试当成交付物。7. `cloud_sync_gating_test` 的两条用例在不同轮次间结果不一致，第一反应是「我的改动引入了回归」，但改的东西与云同步毫无交集；对照基线全量跑 + 本树重跑才判定为 flaky。教训：**判回归前必须拿到同一环境下基线的全量结果**，只看单次全量跑的红绿差会得出错误结论。

## [S1] Problem

应用目前只能由用户手动启动。教师上课前需要它开机即在，却要逐次点开；而仓库此前**完全没有**任何自启实现——没有 `launch_at_startup` 之类的依赖，没有 `HKCU\Run` 写入，Android/macOS/Linux 侧同样没有，Dart 侧也没有对应的设置项。

## [S2] Design

### Windows 注册表实现

- 仅 Windows 桌面实现；首版不覆盖 macOS（`SMAppService`/登录项）、Linux（`~/.config/autostart` 的 `.desktop`）与 Android（厂商白名单差异过大）。
- 使用 `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`，值名 `SecRandom Lite`，数据为 `"C:\path\SecRandomLite.exe"`（加引号以容忍路径中的空格）。选择 HKCU 而非 HKLM：不需要管理员权限，也不把设置绑到整台机器。
- exe 全路径用 `GetModuleFileNameW` 取得，并处理其「缓冲区不足时按长度截断且不报错」的语义（循环扩容直到返回长度小于容量）。
- `IsEnabled()` 回读注册表并要求该值仍指向当前 exe；路径比较大小写不敏感。陈旧条目读作关闭，让开关引导用户修复。
- `SetEnabled()` 用 `RegCreateKeyExW` + `RegSetValueExW` / `RegDeleteValueW`，写完回读校验；删除不存在的值算成功。任何一步失败返回 `false`，由通道回 `registry_write_failed`。
- 打开应用不主动改写注册表——只有用户拨动开关才写。这样自启状态的变更永远出自用户意图。

### 方法通道

- 通道名 `secrandom_lite/auto_start`，方法 `isEnabled`（返回 bool）与 `setEnabled`（入参 bool）。`flutter_window.cpp` 中与既有 `quick_entry` 通道并列注册，`OnDestroy` 时一并释放。
- 参数不是 bool 时回 `invalid_arguments`，注册表写失败回 `registry_write_failed`，未知方法回 `NotImplemented`——与既有通道的错误约定一致。

### Dart 服务与持久化

- `AutoStartService` 单例，公开 `supportsAutoStart`、`loadAutoStartEnabled`、`setAutoStartEnabled`；非 Windows 直接短路，不触碰原生通道。
- 注册表是唯一事实来源；`SharedPreferences` 键 `auto_start_enabled` 仅在通道不可用时兜底显示，每次成功读取都会回写以保持新鲜。
- 写入失败时先把偏好对齐注册表真实值**再** `rethrow`；`_syncToRegistry()` 内部吞掉二次异常，避免盖掉调用方本来要处理的错误。
- 服务不持有 `initialize()`，也就不需要为「首次初始化只能走一次」拆测试文件。

### 设置 UI

- 个性化设置新增「开机自启」卡片（`Icons.power_settings_new`），内含 `登录时启动` 开关，与「点名悬浮窗」卡片并列；窄屏 `_buildNarrowLayout` 与宽屏 `_buildWideLayout` **两处都要插入**，间距跟随所在布局。
- 卡片下方间距由 `_AutoStartSection` 自带，与 `_FloatingWindowSection` 一致；不受支持的平台返回 `SizedBox.shrink()`，整块不渲染也不占位。
- 开关自持状态：`initState` 里 `_load()` 回填，读取失败回落为关闭但**恢复可操作**；切换期间 `_loading` 禁用开关防止重入；失败后按注册表真实值回落并 `SnackBar` 提示。

## [S3] Out of Scope

- macOS、Linux、Android 的开机自启。
- 登录时**静默驻留托盘**（需与单例互斥守卫一起做，见 Journey log 第 5 条）。
- 「启动时最小化」「自启时直接进点名页」等启动行为定制。
- 让用户选择自启时执行的命令行参数或以其他用户身份运行。
- 按计划任务（Task Scheduler）实现的延迟启动或触发器启动。
- 修改现有点名、抽奖、历史记录、云同步的数据模型。

## Tasks

- [x] T1: 实现 Windows 注册表自启原生层 — acceptance: `auto_start.cpp` 提供 `IsEnabled`/`SetEnabled`，写 HKCU `Run` 键成功后回读校验，陈旧条目读作关闭，删除缺失值不算失败；`auto_start.cpp` 已加入 `windows/runner/CMakeLists.txt` 的 `add_executable`（covers: S2 Windows 注册表实现）
- [x] T2: 接入 `secrandom_lite/auto_start` 方法通道 — acceptance: `isEnabled`/`setEnabled` 在 `FlutterWindow::OnCreate` 注册、`OnDestroy` 释放；参数非 bool 回 `invalid_arguments`，写失败回 `registry_write_failed`，未知方法回 `NotImplemented`（covers: S2 方法通道；depends: T1）
- [x] T3: 新增 `AutoStartService` 与状态持久化 — acceptance: 非 Windows 短路且不触碰通道；读取失败回落本地偏好，写入失败先对齐注册表真实值再 `rethrow`（covers: S2 Dart 服务与持久化；depends: T2）
- [x] T4: 在个性化设置接入开机自启开关 — acceptance: 窄屏与宽屏两套布局都渲染「开机自启」卡片；非 Windows 整块不渲染不占位；读取失败后开关仍可操作，写入失败后按真实值回落并提示（covers: S2 设置 UI；depends: T3）
- [x] T5: 增加行为测试与静态检查验证 — acceptance: `flutter analyze` 无 error/warning；测试用镜像式 skip 覆盖「开关按注册表状态显示」「开启写入注册表」「写入失败回落并提示」与「非 Windows 不渲染开关」，两侧宿主都真实执行（covers: S2 设置 UI、Dart 服务与持久化；depends: T4）
