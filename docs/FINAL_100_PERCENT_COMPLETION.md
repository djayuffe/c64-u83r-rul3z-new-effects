# 100% completion pass

This pass closes the new-effects-only build after the cube 3D fix.

## What was finished

- Removed stale/inaccurate source comments saying old effects remain.
- Removed the duplicated `bne @chkplus` in `ReadKeys`.
- Kept only four active new effects in `InitTbl` and `UpdateTbl`.
- Kept `SeedRand` local and audited so ACME does not see undefined startup symbols.
- Finished the Cube V3 wireframe renderer with depth-vector connector tables.

## Cube 3D final fix

The first real cube pass drew front square, rear square and connector lines, but the diagonal connector helper used the same `cv_diag_step` for both X and Y. That makes shallow depth vectors overshoot vertically, so the cube can look broken or wrong.

The final version stores the active `cv_depth_idx` and uses:

- `CvDiagXOffset`
- `CvDiagYOffset`

Each of the 8 depth vectors has 6 sampled connector offsets, so each depth connector lands on the actual rear-square corner instead of overshooting.

## Audit additions

`tools/static_audit.py` now validates:

- no duplicate `ReadKeys` branch/compare regression
- Cube V3 has real helpers
- Cube V3 has depth-vector connector tables
- old broken diagonal y=step overshoot does not return

## Build

```bash
./build.sh
x64sc -autostartprgmode 1 -autostart build/megademo.prg
```
