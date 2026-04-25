## 2026-04-25T16:01:00+08:00 Task: initialization
- Default mode for both rollcall and lottery is auto.
- Manual-stop mode must keep animating until the user clicks stop.
- No new duration customization or shared global animation setting is allowed.

## 2026-04-25T16:01:00+08:00 Task: T1 implementation
- Kept the local enum name `AnimationMode` with `auto` and `manual` values so the persisted JSON stays simple and the two flows remain clearly separated.

## 2026-04-25T16:01:00+08:00 Task: T1 correction
- Renamed the enum values to `auto`, `manualStop`, and `none` so each persisted option maps unambiguously to downstream runtime behavior.

## 2026-04-25T16:40:00+08:00 Task: T2 implementation
- Kept `startRollCall()` as the compatibility entry point, but split the runtime into explicit start/stop/finalize phases so existing callers still work while manual-stop mode can defer all side effects until stop.
- Chose session-id invalidation plus an in-flight finalize guard to make delayed auto-stop and dispose races harmless without changing draw fairness semantics.
