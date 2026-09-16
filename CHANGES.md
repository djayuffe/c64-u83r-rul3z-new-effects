# New effects swap pass

## Changed

- Set `NUM_PARTS = 4`.
- Replaced active dispatch with new source-derived effects only.
- Removed old effect body section from the active source body.
- Replaced card tables with four new titles/subtitles.
- Added row-24-safe renderers for:
  - wire cube clean
  - infinity corridor
  - gold trench
  - cube v3 rotor final
- Bundled uploaded source material for traceability.
- Added `tools/static_audit.py` to enforce:
  - exactly 4 active parts
  - dispatch only targets `nw/ic/gt/cv`
  - old effects are not active
  - new source material is present
  - row 24 remains protected for the scroller
