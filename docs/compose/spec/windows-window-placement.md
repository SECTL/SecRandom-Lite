---
feature: windows-window-placement
status: delivered
updated: 2026-10-17
branch: main
commits:
---

# Windows 窗口位置记忆

## Report

**What was built** — Windows 侧新增窗口位置记忆：主窗口与点名悬浮窗在关闭/拖动结束时把当前位置写入 `HKCU\Software\SecRandom Lite\WindowPlacement`，下次打开时回到原处，而不是每次都回到默认位置。悬浮窗原本是「每次创建时贴在主窗口右上角」，现在优先回到用户拖到的地方；主窗口原本固定开在 `(10,10)`，现在回到上次的位置。

**只记位置，不记尺寸。** 这是有意的：位置在 PerMonitorV2 下读回来就是物理像素，可以原样写回；而尺寸如果一并记住，一个在 100% 屏上记下的 1280×720 搬到 200% 屏上会变成「半个窗口」。尺寸继续走原有的默认值 + 按宿主显示器缩放的逻辑，因此换屏后观感大小恒定。用户诉求是「位置记忆」，尺寸不记既符合诉求也避开了这个 DPI 陷阱。

**存过的位置一律先校验再用。** 拔掉副屏、改分辨率、改缩放之后，保存的坐标可能落在屏幕外。`IsUsablePoint()` 用 `MonitorFromRect(..., MONITOR_DEFAULTTONULL)`（而不是 `NEAREST`）判断该点是否仍落在某台显示器上，再与该显示器的工作区求交，要求至少 64px 可见——只剩几个像素挂在屏幕边缘的窗口技术上「可见」但实际上抓不回来。校验不过就当没存过，回落到默认放置，绝不把窗口开到够不到的地方。

**写入时机选在「用户动作完成」的瞬间，而不是销毁时。** 主窗口在 `WM_EXITSIZEMOVE`（拖动/缩放结束时只发一次）与 `WM_CLOSE` 保存；悬浮窗在 `WM_LBUTTONUP` 且确实发生了拖动（`moved_`）时保存。这样进程被崩溃或任务管理器直接结束时位置也已经落盘。保存主窗口位置时跳过最小化状态——最小化时 `GetWindowRect` 返回约 `(-32000, -32000)`，存下来下次会把窗口恢复到没人够得到的角落。

**Verification** — 全部为原生 C++ 改动，Dart 侧无变化，因此没有新增 Dart 用例；`flutter analyze` 仍为基线 7 条 info、0 error/warning。非 ASCII 检查：改动的 6 个 `windows/runner` 源文件全部纯 ASCII（`LC_ALL=C grep -P '[^\x00-\x7F]'` 无命中），符合代码页 936 下 C4819/C2220 不得出现非 ASCII 的约束。**实际编译在 GitHub Actions 的 `build-windows` job 完成**（本会话主机为 Linux，无 MSVC/Windows SDK），该 job 为推送触发，改动推送后由 CI 验证。

**Journey log** — 1. 存储选原生注册表而非 Dart `SharedPreferences`，是因为主窗口必须在 `Win32Window::Create()` 里决定位置，而那一步跑在 Flutter engine（也就是 Dart）起来之前，那一刻没有 Dart 状态可读；这与 auto-start 立下的「原生拥有的状态由注册表承载」先例一致。2. **DPI 是这个特性最容易踩的坑**：manifest 声明 `PerMonitorV2`，`GetWindowRect` 返回物理像素；而 `Win32Window::Create()` 会把传入的 origin **再乘一次** monitor 缩放系数。若把读到的物理坐标直接交给原路径，高分屏上位置会被缩放两次而飞出屏幕。因此 `Create()` 增加了「还原坐标原样写入、仅尺寸走缩放」的分支，并且缩放系数取自**真正要落脚的那台显示器**而不是默认显示器。3. 正因为上述 DPI 复杂度，「只记位置不记尺寸」的选择同时简化了实现并消除了尺寸跨缩放失真的问题——如果后续要记尺寸，必须以 DIP 存储并按目标显示器 DPI 换算，不能直接存物理像素。4. `Point` 结构体是**无符号**坐标，无法表达主显示器左侧副屏的负坐标，因此还原值没有复用 `Point`，而是在 `Win32Window` 里新增一对有符号成员 + `SetRestoredPosition(int, int)`；注册表里也按 DWORD 位模式存取有符号值。5. `SetRestoredPosition` 是**一次性**的：`Create()` 消费后立即清掉标志，避免之后的重建意外沿用陈旧坐标。6. 校验函数刻意用 `MONITOR_DEFAULTTONULL` 而非 `NEAREST`：后者会把屏幕外的点「悄悄吸附」回最近的显示器，让失效坐标看起来像生效了，掩盖问题。7. 未提供「重置窗口位置」的设置项：`IsUsablePoint()` 的回落已经兜住「窗口开到屏幕外」这一最坏情况，暂无额外逃生舱需求。

## [S1] Problem

窗口位置是用户明确表达过意图的状态，但应用每次都丢弃它：主窗口固定开在 `(10,10)`，悬浮窗每次创建都重新贴在主窗口右上角。用户把悬浮窗拖到手边顺手的位置后，下次开软件就得再拖一次。

## [S2] Design

### 存储

- `HKCU\Software\SecRandom Lite\WindowPlacement`，四个 `REG_DWORD`：`MainX` / `MainY` / `FloatX` / `FloatY`。
- 只存原点，不存尺寸（理由见 Report）。尺寸继续由默认值 + 目标显示器缩放得到。
- 原点可能为负（主显示器左侧的副屏），因此按 DWORD 位模式存取有符号值。
- 打开应用不主动改写注册表；只有用户实际移动窗口才写。

### 校验（`IsUsablePoint(x, y, width, height)`）

- `width`/`height` 非正直接判定不可用。
- `MonitorFromRect(&rect, MONITOR_DEFAULTTONULL)`：落在任何显示器之外即不可用。
- 与该显示器 `rcWork` 求交，要求交集宽高均 ≥ 64px，保证窗口仍可抓取拖回。
- 调用方把 `false` 当作「没有存过」处理，回落到默认放置。

### 主窗口

- `main.cpp` 在 `window.Create()` 之前 `LoadMainWindowPosition()`，成功则 `window.SetRestoredPosition(x, y)`。
- `Win32Window::Create()`：若设置了还原位置且校验通过，则 x/y **原样**使用（物理像素不再缩放），尺寸按**落脚显示器**的 DPI 缩放；校验不通过则完全退回调用方传入的 origin/size，行为与改动前一致。还原标志消费后即清除。
- 保存时机：`FlutterWindow::MessageHandler` 的 `WM_EXITSIZEMOVE`（拖动/缩放结束，仅发一次）与 `WM_CLOSE`（托盘隐藏与真正退出都经过这里）。保存前若 `IsIconic()` 为真则跳过。

### 悬浮窗

- `RollCallFloatingWindow::Create()`：优先使用已存且可用的位置；否则退回「贴在主窗口右上角」的原有行为；主窗口不可用时退回 `CW_USEDEFAULT`。
- 保存时机：`WM_LBUTTONUP` 且 `moved_` 为真（即确实发生了拖动，而不是一次点击）。点击不改位置，因此不写注册表。
- 悬浮窗的显隐与外观仍由设置开关与既有通道控制，本特性不改变其任何交互语义。

## [S3] Out of Scope

- 记忆窗口尺寸（需以 DIP 存储并按目标显示器换算，见 Journey log 第 3 条）。
- 记忆窗口是否最大化/还原状态。
- macOS、Linux 的窗口位置记忆。
- 在设置页提供「重置窗口位置」入口。
- 改动 Dart 侧的任何状态、通道或设置项。

## Tasks

- [x] T1: 实现注册表读写与可用性校验 — acceptance: `window_placement.{h,cpp}` 提供读写接口与 `IsUsablePoint`；负坐标按位模式存取；校验用 `MONITOR_DEFAULTTONULL` 且要求 ≥64px 可见；文件纯 ASCII（covers: S2 存储、S2 校验）
- [x] T2: 主窗口位置还原与保存 — acceptance: `Create()` 在还原位置可用时原样使用物理坐标且尺寸按落脚显示器缩放，不可用时行为与改动前一致；`WM_EXITSIZEMOVE` 与 `WM_CLOSE` 保存，最小化时跳过（covers: S2 主窗口；depends: T1）
- [x] T3: 悬浮窗位置还原与保存 — acceptance: 有可用存档时优先使用，否则退回贴主窗口右上角；拖动结束才保存，单纯点击不写注册表（covers: S2 悬浮窗；depends: T1）
- [x] T4: 接入构建并由 CI 验证编译 — acceptance: `window_placement.cpp` 已加入 `add_executable`；改动的 runner 源文件全为 ASCII；`flutter analyze` 保持基线；实际编译由推送触发的 `build-windows` job 完成（covers: 全部；depends: T1, T2, T3）
