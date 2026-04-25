## 2026-04-25T16:01:00+08:00 Task: initialization
- Known risk: repeated stop / dispose races must not cause duplicate finalize.
- Known risk: rollcall runtime state is split across provider and NameDisplay timer.

## 2026-04-25T16:40:00+08:00 Task: T2 implementation
- Auto mode now relies on a delayed stop path, so dispose must invalidate the active rollcall session; otherwise an already-scheduled stop could try to finalize after teardown.
- Duplicate stop calls can race through async history persistence, so `_isFinalizingRollCall` needs to guard the entire finalize span, not just the final state flip.
