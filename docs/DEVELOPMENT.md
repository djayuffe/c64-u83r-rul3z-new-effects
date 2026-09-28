# Development guide

## Build targets

Run `make` to execute the static audit and assemble `build/megademo.prg`.
`make verify` additionally verifies every committed release checksum. Use
`make clean` to remove only the generated `build/` directory.

## Code map

| Area | Responsibility |
| --- | --- |
| `src/megademo.s` | BASIC loader, VIC setup, raster IRQ, SID engine, transitions, effects, and scroller. |
| `InitTbl` / `UpdateTbl` | The four-scene lifecycle dispatch; each must remain in matching order. |
| `nw_*` | Wire Cube Clean's mirrored edge accents. |
| `ic_*` | Infinity Corridor's distance, palette, and column-warp renderer. |
| `gt_*` | Gold Trench's perspective rails, centre line, and crossbars. |
| `cv_*` | Cube V3's clear, geometry, wire-edge, and connector routines. |
| `NewFxPulsePolish` | Beat accents for non-cube scenes; it never owns row 24. |
| `tools/static_audit.py` | Structural regression checks before ACME runs. |

## Invariants

- `NUM_PARTS` is exactly four and each dispatch table has four entries.
- All active renderers react to `sndPulse`.
- Rows 4–22 are scene space. Row 24 belongs only to `GlobalScroller`.
- Cube V3 uses `CvDiagXOffset` and `CvDiagYOffset` for depth connectors; do not
  collapse them into one shared step.
- `source_material/` is provenance only. Changes to the integrated runtime go
  in `src/megademo.s`.

## Emulator smoke test

```bash
make
x64sc -autostartprgmode 1 -autostart build/megademo.prg
```

Let the sequence cycle through all four title cards and scenes. Confirm the
scroller remains visible, the `Space`, `+`, and `-` controls work, and Cube V3
does not leave trails.
