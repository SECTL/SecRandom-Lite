## 2026-04-25T16:01:00+08:00 Task: initialization
- Plan initialized.
- Rollcall and lottery animation modes must remain separate persisted settings.
- Manual-stop mode has no auto-timeout and final result is produced only after explicit stop.

## 2026-04-25T16:01:00+08:00 Task: T1 implementation
- Backward compatibility requires `fromJson` to treat missing animation keys as `AnimationMode.auto` so older saved configs load safely.
- Each flow should persist its own animation key; sharing a single JSON key would re-couple rollcall and lottery state.

## 2026-04-25T16:01:00+08:00 Task: T1 correction
- The enum needs an explicit `none` state in addition to `manualStop` and `auto`; otherwise downstream logic cannot distinguish manual-stop flow from no-animation flow.
- Invalid persisted values should also fall back to `auto`, not just missing keys, to keep older or corrupted configs safe.

## 2026-04-25T16:01:00+08:00 Task: T1 verification
- It is worth round-tripping an explicitly stored `auto` value in tests, because fallback-only coverage does not prove `auto` survives persistence as a saved setting.

## 2026-04-25T16:40:00+08:00 Task: T2 verification
- Manual-stop coverage should assert the pre-stop state directly: `isRolling` stays true, `currentSelection` stays empty, history is unchanged, and the remaining pool is untouched until `stopRollCall()` runs.
- Persisting rollcall and lottery modes in the same provider test catches accidental coupling in `_saveConfig()` better than checking only one setting at a time.
