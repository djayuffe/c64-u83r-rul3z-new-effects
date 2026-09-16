# New effects integration

The old active effects have been removed from dispatch and replaced with four new text-mode adaptations based on the uploaded sources.

## New effects

### 0. WIRE CUBE CLEAN
Adapted from the uploaded clean/stable wireframe-cube material.  The standalone source targets hi-res bitmap mode; the integrated megademo version keeps the shared text-mode/VIC framework and implements a light row-safe wire-cube visual.

### 1. INFINITY CORRIDOR
Adapted from the lowres pure-raster corridor upload.  It uses the existing distance table plus new corridor character, colour and column-warp tables.

### 2. GOLD TRENCH
Adapted from the clean gold trench upload.  It renders row-perspective rails with a gold palette and protected row-24 scroller.

### 3. CUBE V3 ROTOR FINAL
Adapted from the fixed cube-v3 upload.  The standalone source has its own memory/video model; the integrated version keeps the shared production framework and uses a table-driven rotor-point cube visual.

## Safety

- No new IRQ render path.
- Row 24 remains owned by the global scroller.
- Shared SID engine is retained.
- Old effect dispatch removed.
- Uploaded original sources are bundled in `source_material/`.
