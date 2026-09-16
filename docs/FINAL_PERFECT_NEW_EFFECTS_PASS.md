# Final perfect new-effects pass

This pass completes the new-only megademo build.

## Active effects only

0. WIRE CUBE CLEAN
1. INFINITY CORRIDOR
2. GOLD TRENCH
3. CUBE V3 ROTOR FINAL

The previous/current effects remain removed from active dispatch.

## Final fixes

- Removed duplicate SPACE compare in `ReadKeys`.
- `InitPart` now binds the current effect to a matching SID style via `SelectStyle`.
- All four active new effects directly use `sndPulse`.
- Added `NewFxPulsePolish`, a tiny shared musical accent layer driven by combined sound energy.
- `NewFxPulsePolish` writes only rows `4,6,8,10,13,16,19,22`, so row 24 remains exclusively for the global scroller.
- The polish loop uses `newfxPolishIdx` instead of unsafe `$ff` scratch.
- Static audit now fails if the new effects stop reacting to `sndPulse`, if the polish pass is missing, or if row 24 becomes unsafe.

## Validation

Run:

```bash
python3 tools/static_audit.py
```

Expected:

```text
STATIC AUDIT OK
new effects pulse-polished and mood-bound
```
