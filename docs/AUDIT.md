# Release audit

The release gate is `tools/static_audit.py`, followed by ACME assembly and
`make verify` checksum validation.

## Checks performed

- Exactly four active parts and matching table lengths.
- No legacy effect targets in the active dispatch or source body.
- Presence of all four provenance files.
- Required active-effect routines, palettes, titles, and `sndPulse` use.
- Row-24 protection and global scroller ownership.
- Undefined global `JSR`/`JMP` targets and undefined local dot labels.
- Cube V3 geometry, connected edges, independent depth-vector offsets, and
  safe field clearing.
- Gold Trench's long-branch and store-label regressions.
- ACME assembly with strict segments and the committed SHA-256 manifest.

## Scope

The audit is a source-structure regression gate, not a substitute for manual
emulator testing. The checked-in gallery was captured from the built PRG in
VICE 3.9; run the smoke test in `DEVELOPMENT.md` when changing timing, input,
SID, VIC, or rendering code.
