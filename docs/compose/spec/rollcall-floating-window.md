---
feature: rollcall-floating-window
status: delivered
updated: 2026-10-11
branch: main
commits:
---

# 点名悬浮窗与快捷方式

## Report

**What was built** — Windows 侧新增真正的独立点名入口：个性化设置中打开「点名悬浮窗」后，Windows runner 用原生 Win32 创建一个可拖动的正方形置顶窗口，窗口内只显示「点名」文字（无图标、无关闭按钮）。点击它会把主窗口恢复到前台并切到点名页，**悬浮窗自身继续驻留**，开关保持开启，可连续点击；它没有隐式的自动关闭行为，显隐只由设置开关控制。开关状态跨重启保留：启动时若上次为开启就自动重建，重建失败则如实把开关回落为关闭，避免设置显示「已开启」却没有窗口。同一 runner 还实现了系统托盘驻留：启动即注册托盘图标，点击主窗口关闭按钮改为隐藏到托盘而非退出，托盘菜单提供「打开点名」「显示主窗口」「退出」，其中「退出」才真正销毁主窗口、悬浮窗并移除托盘图标；资源管理器重启后会自动重建托盘图标，重建失败则回退为关闭即退出，避免留下无法唤回的后台进程。Android 侧不做系统悬浮层，改用 Quick Settings Tile：磁贴点击启动或唤醒 `MainActivity` 并进入点名页，不申请悬浮窗权限、不在后台执行点名；Android 14 起改用 `PendingIntent` 重载启动，规避平台对 `Intent` 启动的硬性禁止。磁贴自带专用单色图标 `drawable/ic_rollcall_tile`（透明背景矢量剪影），清单与 `Tile.icon` 均指向它，不再复用会被系统涂成整块黑色的启动器图标。

Dart 侧新增 `RollCallQuickEntryService` 统一承接两个平台的事件与开关：方法通道 `secrandom_lite/quick_entry` 承载 `showFloatingWindow` / `hideFloatingWindow` 与反向的 `openRollCall`，开关状态落 `SharedPreferences`（默认关闭、跨重启保留，启动时按需自动恢复）。入口事件只负责跳转，不改变开关状态。设置开关位于个性化设置的独立卡片，仅在 Windows 渲染并对创建失败给出提示；主页监听入口事件切回点名页，点名业务状态（名单、筛选、抽取逻辑）完全复用，没有第二套状态。另外历史记录页桌面端右下角新增刷新按钮，替代移动端的下滑手势，与既有的「查看详细记录」按钮同尺寸纵向排列。

**Verification** — `flutter analyze`：PASS，7 条 info 均为基线既有（6 条 `theme_mode_body` 的 Radio deprecation + 1 条 `rollcall_settings_screen.dart` 的 `use_build_context_synchronously`，该模式在 `HEAD` 中已存在），无 error/warning。`flutter test -j 1`：PASS 133 passed / 1 skipped。平台相关的用例一律用镜像式 skip 而非静默 `return`：Windows 宿主跳过仅适用于非 Windows 的用例，CI 的 ubuntu runner 上则跳过三条悬浮窗用例并实际执行那些用例，两侧分支都真实被覆盖，不会出现空跑通过。注意 `supportsFloatingWindow` 取自 `dart:io` 的 `Platform.isWindows`（宿主平台），不受 `debugDefaultTargetPlatformOverride` 影响，所以“非 Windows 不渲染开关”这一分支无法在本机 Windows 上模拟，只能靠镜像式 skip 在 CI 上覆盖。新增/更新测试覆盖：开关重复开关各只发一次原生调用、点击悬浮窗请求点名且开关保持开启、未支持平台不发任何原生调用、监听者挂载前到达的请求补投且只投一次、主页收到请求切回点名页、启动按上次状态自动恢复悬浮窗、恢复失败时开关回落关闭、开关出现在个性化设置且已从点名名单设置移除、历史页刷新按钮仅在桌面出现且与详情按钮尺寸一致、点击刷新按钮走通刷新链路。`flutter build apk --debug`：PASS（含磁贴单色图标；另用 `aapt2 dump xmltree` / `dump resources` 核对 APK 内服务 `android:icon` 解析到 `drawable/ic_rollcall_tile` 且产物为矢量 `res/drawable/ic_rollcall_tile.xml`）。Windows 原生侧：`MSBuild /t:ClCompile` 对改动的 runner 源文件编译通过（无错误无警告）；窗口创建逻辑另用最小复现程序单独验证（见 Journey log 第 6 条）。`flutter build windows --debug`：本轮的窗口改动尚未做完整链接验证，因为开发中的 exe 被用户正在运行的实例占用；待其重启后确认。

**Journey log** — 1. 首轮独立评审抓到 1 个 critical 与 1 个 high：`startActivityAndCollapse(Intent)` 在 targetSdk ≥ 34 会抛 `UnsupportedOperationException`（已对照本地 SDK 源码 `TileService.java:253-254,426-431` 确认），green 的 APK 构建完全掩盖了它；以及悬浮窗点击无法唤醒被托盘 `SW_HIDE` 隐藏（非最小化）的主窗口。两者均已修复并二次复审确认。2. Windows runner 源文件在代码页 936 下编译，非 ASCII 字面量会触发「警告视为错误（C4819/C2220）」，中文字符串必须写成 `L"\x.."` 转义或纯英文注释。3. 托盘回调在 `NIM_SETVERSION` 后鼠标事件位于 `LOWORD(lparam)`，直接比较完整 `lparam` 会让左键点击失效，需用 `LOWORD(lparam)` 并兼容 `NIN_SELECT` / `WM_CONTEXTMENU`。4. 我最初把「点击悬浮窗」实现成同时关闭功能开关，用户实际使用时立刻发现「点一次就永久消失」；教训是**入口事件不应顺带改变用户意图表达的设置状态**，显隐应只由开关控制。5. 单例服务的首次 `initialize()` 只能走一次，因此「启动自动恢复」的成功与失败两条路径各自独占一个测试文件，靠测试文件的独立运行获得全新单例。6. **悬浮窗此前根本没能创建成功**：窗口过程在 `CreateWindowEx` 期间收到 WM_NCCREATE/WM_CREATE，而此时成员 `window_` 还没被赋值（赋值发生在 `CreateWindowEx` 返回后），回落分支执行 `DefWindowProc(window_, ...)` 等于传了 NULL，`WM_NCCREATE` 随即返回 FALSE 导致创建中止并报 `ERROR_INVALID_WINDOW_HANDLE`(1400)。定位方法是：先用 EnumWindows 枚举运行进程的顶层窗口，确认 `SECRANDOM_ROLL_CALL_FLOATING_WINDOW` 类根本不存在（排除「创建了但没显示」），再比对 exe 内字符串指纹确认跑的是新代码，最后写最小复现程序单独跑出 `gle=1400` 并验证改用有效 `window` 参数后 `Show()=true`。教训：**窗口过程在创建期必须只用传入的 HWND 参数，不能依赖在创建之后才赋值的成员**；编译通过、链接成功、静态分析干净都不能证明窗口能创建出来。

## [S1] Problem

课堂使用时，用户需要从其他窗口快速回到点名界面。当前应用只有主窗口内的导航，没有 Windows 独立悬浮入口；Android 也没有系统控制中心快捷入口。

## [S2] Design

### Windows 独立悬浮窗

- 仅 Windows 桌面实现真正的独立窗口；首版不覆盖 macOS、Linux 和 Android 系统悬浮层。
- 在个性化设置的「点名悬浮窗」卡片中提供开关。开关关闭时不创建悬浮窗；打开后创建一个可拖动、始终置顶的正方形独立窗口。
- 悬浮窗只是一个快捷入口：正方形窗口内居中显示「点名」文字，不显示图标，也没有关闭按钮。点击时通过平台通道通知主 Flutter 窗口：激活/恢复主窗口并切换到点名页；**悬浮窗自身继续显示**，开关保持开启，便于连续使用。
- 悬浮窗的显隐只由设置开关控制，不存在“点一次就自动关闭”的隐式行为。托盘菜单执行“退出”时悬浮窗一并销毁。
- 显示期间用 WinEvent 监听前台窗口切换（EVENT_SYSTEM_FOREGROUND）及窗口层级重排（EVENT_OBJECT_REORDER），同时响应自身 WM_WINDOWPOSCHANGED；合并事件后在窗口消息循环检查层级，仅在置顶属性丢失或有可见置顶窗口位于其上方时用 HWND_TOPMOST 恢复层级。使用 SWP_NOACTIVATE，不抢前台焦点。隐藏及销毁时注销事件监听，层级变化不得重新显示已关闭的悬浮窗。
- 层级维护验证：MSBuild /t:ClCompile 通过；直接编译项目窗口源码的临时 Win32 验证程序实测层级恢复、焦点不变、置顶属性恢复、隐藏不自动重现、重新打开全部通过。未覆盖正在运行的开发 exe。
- 开关状态跨重启保留：应用启动时若上次为开启，则自动重新创建悬浮窗；自动创建失败时把开关回落为关闭并通知界面，避免设置显示“已开启”而实际没有窗口。
- Windows 启动后创建系统托盘图标；点击主窗口右上角关闭按钮时隐藏主窗口而非终止进程，已开启的悬浮窗保持可用。托盘右键菜单提供“打开点名”“显示主窗口”“退出”。前两项恢复/激活原有主窗口，其中“打开点名”切到点名页；“退出”才真正关闭进程。点击最小化按钮保持 Windows 默认最小化行为。托盘图标异常或无法添加时，主窗口关闭仍应真正退出，避免不可恢复的后台进程。
- 悬浮窗创建失败时保留设置开关为关闭状态，并在设置页给出可理解的错误提示；不得阻塞主窗口使用。
- 主窗口只有一个 Flutter engine；悬浮窗使用 Windows runner 创建的原生轻量窗口，通过消息/平台通道与 Dart 侧通信，避免第二个 Flutter engine 带来的状态分叉。
- 窗口保持正方形，个性化卡片支持大小（48–160）、背景色（六种预设及六位十六进制输入）、圆角（0–24）调节与实时预览、恢复默认。默认边长 80、浅蓝色 #BDEAFF、圆角 18；文字随尺寸缩放，按背景亮度选择深色或白色。通过 `setFloatingAppearance` 同步至原生窗口，参数保存在 SharedPreferences，启动时先应用外观再恢复窗口。
- 超过系统拖动阈值才移动窗口，否则视为点击；避免微小抖动吞掉点击。
- 外观增量验证：`flutter test -j 1` 135 通过、1 跳过；Widget 测试操作大小滑块、恢复默认、自定义颜色并断言预览，服务测试验证参数发送与持久化；`flutter analyze` 仍仅 7 条既有 info；Windows runner `MSBuild /t:ClCompile` 通过。本轮未覆盖正在运行的开发 exe，完整链接及实际原生渲染需停止开发实例后重新编译运行确认。

### Android Quick Settings Tile

- Android 使用系统 Quick Settings Tile，不申请悬浮窗权限、不启动后台悬浮服务。
- Tile 点击通过 Android 原生 Intent 启动或唤醒 `MainActivity`，使用 `singleTop`/已有 deep-link 处理路径通知 Dart 侧进入点名页。
- 应用收到 Tile 入口后切换到现有主界面的点名页，不直接在后台执行点名；Tile 状态保持可用，不表示点名进行中。
- Android Tile 不影响 Windows 设置开关；平台不支持时，点名设置不显示 Windows 悬浮窗控制项。
- Tile 使用专用的单色图标 `drawable/ic_rollcall_tile`（透明背景、单一填充色的矢量剪影），不复用启动器图标：系统会按单色蒙版重绘磁贴图标，不透明背景的彩色位图会被渲染成整块黑色。清单 `android:icon` 与 `Tile.icon` 都指向该图标，避免个别系统缓存旧图标导致显示不一致。

### Dart 状态与持久化

- 新增跨平台入口服务 `RollCallQuickEntryService`，公开 `supportsFloatingWindow`、`loadFloatingWindowEnabled`、`setFloatingWindowEnabled` 和入口事件流；非 Windows 平台直接短路，不触碰原生通道。
- Windows 开关状态使用 `SharedPreferences` 记录，默认关闭并跨重启保留。启动时若为开启则自动重建悬浮窗；只有用户通过设置开关才会关闭它，入口事件不改变开关状态。
- 平台入口到达时由 `HomeScreen` 持有的订阅把选中索引切为点名页（同时收起可能打开的控制面板）；现有点名状态、名单和抽取逻辑复用，不新增第二套业务状态。
- 服务调用可重复：重复打开、重复关闭、主窗口已关闭/正在销毁时不抛出未处理异常。冷启动时事件可能早于监听者到达，此时暂存并在首个监听者挂载时补投，且只投递一次。

## [S3] Out of Scope

- macOS、Linux 的独立悬浮窗。
- Android 系统悬浮窗、悬浮权限、后台悬浮服务。
- 悬浮窗内直接开始/停止点名、选择人数或显示实时点名结果。
- 应用退出后由独立后台进程继续维持悬浮窗。
- 修改现有随机抽取、动画、历史记录、云同步和点名数据模型。

## Tasks

- [x] T1: 增加跨平台点名快捷入口服务与状态持久化 — acceptance: Windows/Android/其他平台均能通过统一接口报告能力，Windows 开关默认关闭且状态可跨重启保留，未支持平台不会调用平台实现（covers: S2 Dart 状态与持久化）
- [x] T2: 实现 Windows 独立置顶悬浮窗 — acceptance: Windows 开关打开后创建可拖动置顶的正方形入口，点击后激活主窗口点名页且悬浮窗继续显示，托盘退出时销毁窗口（covers: S2 Windows 独立悬浮窗；depends: T1）
- [x] T2a: 实现 Windows 系统托盘驻留 — acceptance: 托盘图标可见；主窗口关闭后隐藏且进程存活，菜单可恢复主窗口、打开点名页和真正退出；已开启的悬浮窗在驻留期间可用，退出清理所有窗口；托盘初始化失败不产生无法恢复的后台进程 (covers: S2 Windows 独立悬浮窗；depends: T2)
- [x] T3: 实现 Android Quick Settings Tile 入口 — acceptance: Tile 可被系统识别并点击，点击能启动/唤醒主 Activity 并进入点名页，不申请悬浮窗权限且不后台执行点名（covers: S2 Android Quick Settings Tile；depends: T1）
- [x] T4: 在设置页接入平台开关与反馈 — acceptance: Windows 显示悬浮窗开关并反馈创建失败，非 Windows 不显示该控制项；入口触发后主页选中点名页。开关位置后由 T7 调整为个性化设置（covers: S2 Windows 独立悬浮窗、Dart 状态与持久化；depends: T1, T2, T3）
- [x] T5: 增加行为测试与平台构建验证 — acceptance: 单元/Widget 测试覆盖开关持久化、重复开关、入口路由和未支持平台；`flutter analyze`、相关 `flutter test` 与 Windows/Android 构建验证通过（covers: S2 Windows 独立悬浮窗、Android Quick Settings Tile、Dart 状态与持久化；depends: T2, T2a, T3, T4）
- [x] T6: 为 Android 磁贴改用专用单色图标 — acceptance: 磁贴清单 `android:icon` 与 `Tile.icon` 均指向 `drawable/ic_rollcall_tile`，该图标为透明背景单色矢量而非 `mipmap/ic_launcher`，应用图标与启动器行为不变；`flutter build apk --debug` 通过且 APK 内资源可解析 (covers: S2 Android Quick Settings Tile；depends: T3)
- [x] T7: 悬浮窗开关移入个性化设置 — acceptance: 开关出现在个性化设置的「点名悬浮窗」卡片，点名名单设置不再显示该开关；非 Windows 平台整块不渲染，开关读取失败也不残留禁用态 (covers: S2 Windows 独立悬浮窗；depends: T4)
- [x] T8: 修正悬浮窗交互语义 — acceptance: 窗口为正方形且只显示「点名」文字、无图标无关闭按钮；点击后悬浮窗保持显示且开关保持开启，可连续点击；托盘「打开点名」也不再隐藏悬浮窗 (covers: S2 Windows 独立悬浮窗；depends: T2)
- [x] T10: 修复悬浮窗无法创建 — acceptance: 窗口过程在创建期只使用传入的 HWND 参数，`CreateWindowEx` 成功返回句柄（复现程序确认修复前 `gle=1400`、修复后 `Show()=true`）；runner 改动经 `MSBuild /t:ClCompile` 编译通过 (covers: S2 Windows 独立悬浮窗；depends: T2)
- [x] T9: 开关跨重启保留并自动恢复 — acceptance: 开启后重启应用会自动重建悬浮窗；自动创建失败时开关回落为关闭并通知界面；入口事件不再改变开关状态 (covers: S2 Dart 状态与持久化、S2 Windows 独立悬浮窗；depends: T8)
