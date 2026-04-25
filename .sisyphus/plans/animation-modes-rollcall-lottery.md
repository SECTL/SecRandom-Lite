# 抽人/抽奖动画模式扩展计划

## TL;DR
> **Summary**: 为“抽人设置”和“抽奖设置”分别新增“抽取动画模式”，支持手动停止、自动播放、不播放三种模式，并将运行态按钮与结果产出时机对齐到模式语义。
> **Deliverables**:
> - 抽人/抽奖各自动画模式配置（独立持久化）
> - 抽人/抽奖运行态状态机改造（含手动停止）
> - 全量测试与验证证据
> **Effort**: Medium
> **Parallel**: YES - 3 waves
> **Critical Path**: 1 → 2/3 → 4/5/6 → 7

## Context
### Original Request
- 给抽人设置和抽奖设置都加上“抽取动画模式”，支持三种：
  - 手动停止动画：开始后持续跳动，按钮变“停止”；点击停止后再随机一次得结果。
  - 自动播放动画：保持当前逻辑。
  - 不播放动画：开始后直接显示结果。

### Interview Summary
- 两端配置分离：抽人和抽奖各自独立模式，不共享。
- 手动停止模式最终结果采用“停止后再随机一次”。
- 手动停止模式不自动结束，必须由用户主动点击“停止”才 finalize。
- 默认模式采用“自动播放动画”（兼容当前行为）。

### Metis Review (gaps addressed)
- 已纳入防线：
  - 防双重 finalize（停止、重复点击、dispose 竞争）
  - 覆盖 6 处按钮变体（rollcall 3 + lottery 3）
  - 旧配置迁移默认值与回归测试
  - 锁定范围：不引入自定义时长、不中心化到“抽取设置”、不新增 integration_test

## Work Objectives
### Core Objective
在不改随机算法正确性的前提下，为抽人与抽奖分别引入可持久化动画模式，并保证模式驱动的开始/停止/自动收敛行为一致、可测试、可回归。

### Deliverables
- `AppConfig` / `AppProvider` 新增并持久化 `rollcallAnimationMode`、`lotteryAnimationMode`
- `rollcall_settings_screen.dart` 新增抽人动画模式选择器
- `lottery_settings_screen.dart` 新增抽奖动画模式选择器
- Rollcall 运行态支持：开始→停止（手动）、自动播放、不播放
- Lottery 运行态支持：开始→停止（手动）、自动播放、不播放
- 新增/更新单测与 widget 测试，产出证据文件

### Definition of Done (verifiable conditions with commands)
- `flutter test test/app_config_test.dart` 通过，验证新字段默认值/序列化/旧配置回退。
- `flutter test test/app_provider_animation_mode_test.dart` 通过，验证 rollcall 三模式、停止行为、一次性 finalize。
- `flutter test test/lottery_animation_mode_widget_test.dart` 通过，验证 lottery 三模式按钮文案与行为。
- `flutter test test/responsive_layout_widget_test.dart` 通过，验证布局回归。
- `flutter test` 全量通过。
- `flutter analyze` 无 error（允许既有 info/warning 保持不扩大）。

### Must Have
- 两个独立模式字段，默认 `auto`。
- 手动停止模式：按钮“开始”→“停止”；仅在点击“停止”时再随机一次并 finalize。
- 不播放模式：点击开始后直接 finalize。
- 自动播放模式：保持现有时长（抽人 1s、抽奖 2s）。
- 活动轮次期间锁定会影响结果的输入（模式变更、池/计数等仅下一轮生效）。
- 手动停止模式允许持续播放，直到用户主动停止。

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- 不改公平抽取/非重复抽取算法语义。
- 不把动画模式放入 `draw_settings_screen.dart`。
- 不引入全局共享动画模式字段。
  - 不新增“时长可配置”或“自动停止”需求。
- 不新增 integration_test 或人工验证步骤。

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: **tests-after**（沿用现有 unit+widget 体系）
- QA policy: 每个任务均附 happy/failure 场景
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks for max parallelism.

Wave 1: 配置模型与状态机基线（T1-T3）
Wave 2: 双功能运行态改造（T4-T6）
Wave 3: 测试与回归验证（T7）

### Dependency Matrix (full, all tasks)
- T1 → T2, T3, T7
- T2 → T4, T7
- T3 → T5, T6, T7
- T4, T5, T6 → T7

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1 → 3 tasks → quick / unspecified-low
- Wave 2 → 3 tasks → unspecified-high / deep
- Wave 3 → 1 task → unspecified-high

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. 定义动画模式枚举与配置字段（双端独立）

  **What to do**:
  - 在 `lib/models/app_config.dart` 增加动画模式枚举（建议 `DrawAnimationMode { manualStop, auto, none }`）与两个字段：`rollcallAnimationMode`、`lotteryAnimationMode`。
  - 在构造器、`toJson`、`fromJson`、`defaultConfig` 全链路接入。
  - `fromJson` 对旧配置缺失字段默认回退为 `auto`。

  **Must NOT do**:
  - 不新增共享字段 `animationMode`。
  - 不引入可配置时长字段。

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: 单文件模型改动为主，边界清晰
  - Skills: `[]` - 不需额外技能
  - Omitted: `review-work` - 此阶段先实现，最终波次统一复核

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: T2,T3,T7 | Blocked By: None

  **References**:
  - Pattern: `lib/models/app_config.dart:13-80` - 现有字段定义、序列化与默认值模式
  - Test: `test/app_config_test.dart:5-71` - 旧配置回退测试写法

  **Acceptance Criteria**:
  - [ ] `AppConfig` 新增双字段并可编译。
  - [ ] 旧配置缺失新键时默认值为 `auto`。
  - [ ] JSON 输出包含两个独立键。

  **QA Scenarios**:
  ```
  Scenario: 旧配置迁移回退
    Tool: Bash
    Steps: flutter test test/app_config_test.dart --plain-name "fromJson"
    Expected: Exit code 0; 新增断言通过（缺失键 -> auto）
    Evidence: .sisyphus/evidence/task-1-config-migration.txt

  Scenario: 序列化键完整性
    Tool: Bash
    Steps: flutter test test/app_config_test.dart --plain-name "toJson"
    Expected: Exit code 0; 两个模式键均被持久化
    Evidence: .sisyphus/evidence/task-1-config-serialization.txt
  ```

  **Commit**: YES | Message: `feat(config): add rollcall and lottery animation mode persistence` | Files: `lib/models/app_config.dart`, `test/app_config_test.dart`

- [ ] 2. 扩展 AppProvider 状态与 API（模式读写 + 轮次生命周期守卫）

  **What to do**:
  - 在 `lib/providers/app_provider.dart` 增加双模式私有字段、getter、setter，并纳入 `_loadData`/`_saveConfig`。
  - 为 rollcall 增加明确生命周期方法：`startRollCallRound()`、`stopRollCallRound()`、`finalizeRollCallRound()`（命名可调整，但语义必须分离）。
  - 增加一次性 finalize 防重入保护（如 `_rollcallRoundToken` / `_isFinalizing`）。
  - 手动模式下：开始时仅进入 rolling，不写历史、不扣 remaining；仅在停止时 finalize 并写历史。

  **Must NOT do**:
  - 不在开始阶段提前写历史记录。
  - 不让一次轮次触发两次 finalize。

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: 状态机与副作用顺序改造
  - Skills: `[]`
  - Omitted: `playwright` - 非浏览器任务

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: T4,T7 | Blocked By: T1

  **References**:
  - Pattern: `lib/providers/app_provider.dart:55-66,113-126` - 配置读写接入点
  - Pattern: `lib/providers/app_provider.dart:624-699` - 现有 rollcall 一体化流程
  - API/Type: `lib/models/app_config.dart` - 新模式字段契约

  **Acceptance Criteria**:
  - [ ] Provider 可读写双模式并持久化。
  - [ ] Rollcall 手动模式满足“开始不落结果、仅停止时 finalize”。
  - [ ] 重复点击停止只会 finalize 一次。

  **QA Scenarios**:
  ```
  Scenario: 手动模式停止后才产出结果
    Tool: Bash
    Steps: flutter test test/app_provider_animation_mode_test.dart --plain-name "manual stop finalizes on stop"
    Expected: Exit code 0; stop 前 history/remaining 不变，stop 后只变化一次
    Evidence: .sisyphus/evidence/task-2-provider-manual-stop.txt

  Scenario: 重复停止防重入
    Tool: Bash
    Steps: flutter test test/app_provider_animation_mode_test.dart --plain-name "repeated stop remains idempotent"
    Expected: Exit code 0; finalize 调用计数=1
    Evidence: .sisyphus/evidence/task-2-provider-idempotent.txt
  ```

  **Commit**: YES | Message: `feat(rollcall): add mode-aware round lifecycle in provider` | Files: `lib/providers/app_provider.dart`, `test/app_provider_animation_mode_test.dart`

- [ ] 3. 在抽人设置与抽奖设置页新增模式选择器

  **What to do**:
  - 在 `lib/screens/settings/rollcall_settings_screen.dart` 增加“抽取动画模式”选择 UI，绑定 `appProvider.rollcallAnimationMode`。
  - 在 `lib/screens/settings/lottery_settings_screen.dart` 增加“抽取动画模式”选择 UI，绑定 `appProvider.lotteryAnimationMode`。
  - 文案固定三选项：手动停止动画 / 自动播放动画 / 不播放动画。

  **Must NOT do**:
  - 不改动 `draw_settings_screen.dart` 的现有开关定位。
  - 不将两个模式共用一个 UI 值。

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: 纯设置 UI 绑定
  - Skills: `[]`
  - Omitted: `oracle` - 不需要高阶推理

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: T5,T6,T7 | Blocked By: T1

  **References**:
  - Pattern: `lib/screens/settings/draw_settings_screen.dart:13-31` - SwitchListTile 绑定风格
  - Pattern: `lib/screens/settings/personalization_settings_screen.dart:13-39` - Consumer + provider setter 绑定
  - API/Type: `lib/providers/app_provider.dart:40-49,358-380` - getter/setter 既有模式

  **Acceptance Criteria**:
  - [ ] 两个设置页均出现“抽取动画模式”且三选项完整。
  - [ ] 修改后重进页面可读取到持久化值。

  **QA Scenarios**:
  ```
  Scenario: 双端独立配置可持久化
    Tool: Bash
    Steps: flutter test test/app_provider_animation_mode_test.dart --plain-name "persists independent modes"
    Expected: Exit code 0; rollcall/lottery 模式互不覆盖
    Evidence: .sisyphus/evidence/task-3-settings-persistence.txt

  Scenario: 旧设置页不受影响
    Tool: Bash
    Steps: flutter test test/responsive_layout_widget_test.dart
    Expected: Exit code 0; 布局与现有控件无回归
    Evidence: .sisyphus/evidence/task-3-settings-regression.txt
  ```

  **Commit**: YES | Message: `feat(settings): add rollcall and lottery animation mode selectors` | Files: `lib/screens/settings/rollcall_settings_screen.dart`, `lib/screens/settings/lottery_settings_screen.dart`

- [ ] 4. 改造抽人开始按钮与运行态（开始/停止）

  **What to do**:
  - 更新 `lib/widgets/control_panel.dart` 的 3 套布局按钮：
    - manualStop：idle 显示“开始”，rolling 显示“停止”（可点击）
    - auto：rolling 时禁用并显示“点名中...”
    - none：点击开始立即 finalize，按钮快速回 idle
  - 按模式路由到 Provider 新 API（T2 产出）。
  - 活动轮次期间锁定会影响候选集的关键控件（例如 class/group/gender/selectCount 切换）直到 finalize。

  **Must NOT do**:
  - 不遗漏任何布局变体。
  - 不在 manualStop 中继续沿用“rolling 按钮禁用”。

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: 多布局按钮状态一致性要求高
  - Skills: `[]`
  - Omitted: `playwright` - 先由 widget 测试覆盖

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: T7 | Blocked By: T2

  **References**:
  - Pattern: `lib/widgets/control_panel.dart:201-215,321-335,477-491` - 3 套按钮现状
  - API/Type: `lib/providers/app_provider.dart:35,624-699` - isRolling 与当前开始流
  - Test: `test/responsive_layout_widget_test.dart` - 响应式布局回归基线

  **Acceptance Criteria**:
  - [ ] 三布局按钮在三模式下文案/可点击状态一致。
  - [ ] manualStop 下 rolling 时按钮为“停止”且可触发 stop。
  - [ ] 受控输入在活动轮次中被锁定，结束后恢复。

  **QA Scenarios**:
  ```
  Scenario: 手动模式按钮状态切换
    Tool: Bash
    Steps: flutter test test/app_provider_animation_mode_test.dart --plain-name "control button toggles to stop"
    Expected: Exit code 0; 开始后出现“停止”，点击后回“开始”
    Evidence: .sisyphus/evidence/task-4-rollcall-button-toggle.txt

  Scenario: none 模式立即完成
    Tool: Bash
    Steps: flutter test test/app_provider_animation_mode_test.dart --plain-name "none mode finalizes immediately"
    Expected: Exit code 0; 无持续 rolling 状态
    Evidence: .sisyphus/evidence/task-4-rollcall-none-mode.txt
  ```

  **Commit**: YES | Message: `feat(rollcall-ui): add mode-aware start stop button states` | Files: `lib/widgets/control_panel.dart`, `test/app_provider_animation_mode_test.dart`

- [ ] 5. 改造抽人展示层动画生命周期（NameDisplay）

  **What to do**:
  - 在 `lib/widgets/name_display.dart` 中将本地 timer 行为与 provider 模式/轮次状态对齐：
    - manualStop/auto 才播放跳动；none 不启动 timer。
    - finalize 后统一停表并只显示最终结果。
  - 处理 dispose 与停止竞争，确保无悬挂 timer。

  **Must NOT do**:
  - 不在 build 中引入多重启动导致重复 timer。
  - 不让 none 模式出现过渡跳动帧。

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: UI 动画生命周期易产生竞态
  - Skills: `[]`
  - Omitted: `oracle` - 复杂度可控

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: T7 | Blocked By: T2

  **References**:
  - Pattern: `lib/widgets/name_display.dart:28-67` - 当前 timer 启停点
  - Pattern: `lib/widgets/name_display.dart:97-124,157-184` - AnimatedSwitcher 展示
  - API/Type: `lib/providers/app_provider.dart:33-49,624-699` - 轮次状态 getter 与 rollcall 生命周期基线

  **Acceptance Criteria**:
  - [ ] manualStop/auto 模式可见跳动，none 模式无跳动。
  - [ ] finalize 后 timer 必定停止且仅显示最终 selection。
  - [ ] 页面销毁不会残留 timer（无异常日志/状态泄漏）。

  **QA Scenarios**:
  ```
  Scenario: manual/auto 动画生效
    Tool: Bash
    Steps: flutter test test/app_provider_animation_mode_test.dart --plain-name "rolling animation active in manual and auto"
    Expected: Exit code 0; rolling 期间显示列表变化
    Evidence: .sisyphus/evidence/task-5-name-display-rolling.txt

  Scenario: dispose 安全
    Tool: Bash
    Steps: flutter test test/app_provider_animation_mode_test.dart --plain-name "timer disposed safely"
    Expected: Exit code 0; 无重复回调和异常
    Evidence: .sisyphus/evidence/task-5-name-display-dispose.txt
  ```

  **Commit**: YES | Message: `feat(rollcall-ui): align NameDisplay animation lifecycle with modes` | Files: `lib/widgets/name_display.dart`, `test/app_provider_animation_mode_test.dart`

- [ ] 6. 改造抽奖三模式流程与控制面板

  **What to do**:
  - 在 `lib/screens/lottery_screen.dart` 重构 `_startDraw` / `_startRollingAnimation` / `_finalizeDraw`：
    - manualStop：开始后持续 rolling，按钮变“停止”；仅在点击停止时触发 finalize（停止时再随机一次）。
    - auto：保持当前 2s 自动 finalize。
    - none：开始即 finalize。
  - 更新 `LotteryControlPanel` 的 3 套布局按钮状态与文案一致性。
  - 增加 finalize 幂等保护，防止重复停止/销毁过程双提交。

  **Must NOT do**:
  - 不改变 `LotteryService.drawPrizes` 算法语义。
  - 不在 manualStop 开始阶段提前持久化最终记录。

  **Recommended Agent Profile**:
  - Category: `deep` - Reason: 单文件内多状态分支 + 定时器 + 持久化时序
  - Skills: `[]`
  - Omitted: `review-work` - 最终波次统一审查

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: T7 | Blocked By: T1,T3

  **References**:
  - Pattern: `lib/screens/lottery_screen.dart:120-218` - 现有抽奖生命周期
  - Pattern: `lib/screens/lottery_screen.dart:850-873,963-986,1078-1102` - 3 套按钮实现
  - API/Type: `lib/services/lottery_service.dart:123-164,186-193` - 抽取与持久化边界

  **Acceptance Criteria**:
  - [ ] 三模式流程全部可达且结果时机正确。
  - [ ] manualStop 显示“停止”，点击后只 finalize 一次。
  - [ ] 重复点击停止不会重复写入记录。

  **QA Scenarios**:
  ```
  Scenario: lottery 手动模式 stop 后随机出结果
    Tool: Bash
    Steps: flutter test test/lottery_animation_mode_widget_test.dart --plain-name "manual mode stop triggers finalize"
    Expected: Exit code 0; stop 后才出现最终 records
    Evidence: .sisyphus/evidence/task-6-lottery-manual-stop.txt

  Scenario: 重复停止不会双写入
    Tool: Bash
    Steps: flutter test test/lottery_animation_mode_widget_test.dart --plain-name "finalize once under repeated stop"
    Expected: Exit code 0; 记录写入次数为1轮
    Evidence: .sisyphus/evidence/task-6-lottery-idempotent.txt
  ```

  **Commit**: YES | Message: `feat(lottery): add mode-aware draw lifecycle and controls` | Files: `lib/screens/lottery_screen.dart`, `test/lottery_animation_mode_widget_test.dart`

- [ ] 7. 构建回归测试套件并执行最终验证命令

  **What to do**:
  - 新增/补齐测试文件：
    - `test/app_provider_animation_mode_test.dart`
    - `test/lottery_animation_mode_widget_test.dart`
    - 更新 `test/app_config_test.dart`
  - 覆盖关键边界：旧配置迁移、手动停止重随机、none 立即完成、双 finalize 防护、布局回归。
  - 执行命令：
    - `flutter test test/app_config_test.dart`
    - `flutter test test/app_provider_animation_mode_test.dart`
    - `flutter test test/lottery_animation_mode_widget_test.dart`
    - `flutter test test/responsive_layout_widget_test.dart`
    - `flutter analyze`
    - `flutter test`

  **Must NOT do**:
  - 不使用人工点击验收替代自动测试。
  - 不忽略新引入 error 级诊断。

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: 多层测试编排与故障定位
  - Skills: `[]`
  - Omitted: `playwright` - 当前仓库以 Flutter test 为主

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: Final Verification | Blocked By: T4,T5,T6

  **References**:
  - Test: `test/app_config_test.dart:5-71` - 配置迁移范式
  - Test: `test/responsive_layout_widget_test.dart` - UI 回归基线
  - CI: `.github/workflows/build.yml:40-44` - 现有 CI 执行 `flutter test`

  **Acceptance Criteria**:
  - [ ] 所有新增/更新测试通过，且覆盖三模式主流程与竞态边界。
  - [ ] `flutter analyze` 无新增 error。
  - [ ] `flutter test` 全量通过，退出码 0。

  **QA Scenarios**:
  ```
  Scenario: 全量命令验证
    Tool: Bash
    Steps: flutter analyze; flutter test
    Expected: analyze 无 error；test 退出码 0
    Evidence: .sisyphus/evidence/task-7-full-validation.txt

  Scenario: 关键用例定向回归
    Tool: Bash
    Steps: flutter test test/app_provider_animation_mode_test.dart; flutter test test/lottery_animation_mode_widget_test.dart
    Expected: Exit code 0; 手动/自动/无动画三模式断言全部通过
    Evidence: .sisyphus/evidence/task-7-targeted-regression.txt
  ```

  **Commit**: YES | Message: `test(animation): add mode behavior and regression coverage` | Files: `test/app_config_test.dart`, `test/app_provider_animation_mode_test.dart`, `test/lottery_animation_mode_widget_test.dart`

## Final Verification Wave (MANDATORY — after ALL implementation tasks)
> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback -> fix -> re-run -> present again -> wait for okay.
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Commit 1: `feat(config): add rollcall and lottery animation mode persistence`
- Commit 2: `feat(rollcall): support manual/auto/none draw animation modes`
- Commit 3: `feat(lottery): support manual/auto/none draw animation modes`
- Commit 4: `test(animation): add mode behavior and regression coverage`

## Success Criteria
- 用户可在“抽人设置”“抽奖设置”分别选择动画模式并持久保存。
- 手动模式下按钮与生命周期符合“开始→停止→停止后随机出结果”。
- 自动模式行为与当前版本一致（抽人1s、抽奖2s）。
- 不播放模式下立即出结果且无遗留定时器/运行态。
- 测试与分析命令全部达到预期结果。
