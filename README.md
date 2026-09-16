# U83R RUL3Z — new effects only build

This package removes the previous active effect sequence and replaces it with four new effects adapted from the uploaded source material.

## Active effects

0. WIRE CUBE CLEAN
1. INFINITY CORRIDOR
2. GOLD TRENCH
3. CUBE V3 ROTOR FINAL

## Removed from active dispatch

The old title/matrix/rings/plasma/starfield/trench/cube/etc. sequence is not referenced by `InitTbl` or `UpdateTbl`.  The active runtime uses only:

```asm
InitTbl:
        !word nw_init, ic_init, gt_init, cv_init
UpdateTbl:
        !word nw_update, ic_update, gt_update, cv_update
```

## Source material bundled

The original uploaded sources are included under `source_material/` for traceability:

- `deepseek_asm_20251022_1659c4.txt`
- `cube_v3_0_FULLY_FIXED.asm`
- `InfinityCorridor_lowres_v3f_pureraster.zip`
- `goldtrensh_v1_2_clean.zip`

## Build

```bash
cd mega
./build.sh
x64sc -autostartprgmode 1 -autostart build/megademo.prg
```

`build.sh` runs `tools/static_audit.py` before ACME.


## Final perfect pass

The final pass binds each new effect to a matching SID style and makes all four active renderers directly react to `sndPulse`.  A tiny shared `NewFxPulsePolish` overlay adds beat-driven accent cells on rows 4..22 only, leaving row 24 exclusively for the scroller.

## 100% completion pass

Final completion closes the Cube V3 diagonal connector bug: connector lines now use depth-vector offset tables (`CvDiagXOffset` / `CvDiagYOffset`) instead of using the same step for X and Y. This prevents shallow 3D depth vectors from overshooting vertically.
