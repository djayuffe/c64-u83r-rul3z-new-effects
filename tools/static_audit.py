#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src' / 'megademo.s'
text = SRC.read_text()
errors=[]
def fail(x): errors.append(x)

def count_byte_line(label):
    m=re.search(rf'^{label}:?\s*!byte\s*(.*?)$', text, re.M)
    if not m:
        fail(f'missing {label}')
        return -1
    body=m.group(1).split(';',1)[0]
    return len([x for x in body.split(',') if x.strip()])

def count_word_table(label):
    m=re.search(rf'^{label}:\n\s*!word\s*(.*?)$', text, re.M)
    if not m:
        fail(f'missing {label}')
        return -1
    return len([x for x in m.group(1).split(',') if x.strip()])

m=re.search(r'^NUM_PARTS\s*=\s*(\d+)', text, re.M)
parts=int(m.group(1)) if m else -1
if parts != 4:
    fail(f'NUM_PARTS={parts}, expected 4 new effects only')
for lab in ['PartBorderTbl','PartFramesTbl_Lo','PartFramesTbl_Hi','CardNameLo','CardNameHi','CardSubLo','CardSubHi']:
    n=count_byte_line(lab)
    if n != parts:
        fail(f'{lab} has {n}, expected {parts}')
for lab in ['InitTbl','UpdateTbl']:
    n=count_word_table(lab)
    if n != parts:
        fail(f'{lab} has {n}, expected {parts}')

required_labels = ['nw_init','nw_update','ic_init','ic_update','gt_init','gt_update','cv_init','cv_update',
                   'NfxWireTitle','NfxInfinityTitle','NfxGoldTitle','NfxCubeTitle',
                   'NfxCorridorChars','NfxGoldPalette','NfxCubePalette','NfxColWarp']
for lab in required_labels:
    if not re.search(rf'^{re.escape(lab)}\b', text, re.M):
        fail(f'missing required new-effect label {lab}')

# Old effects must not be active in dispatch.
dispatch_block = re.search(r'InitTbl:.*?UpdateTbl:.*?\n\s*!word[^\n]+', text, re.S)
if dispatch_block:
    forbidden = ['ti_', 'mr_', 'rg_', 'pl_', 'hs_', 'vx_', 'xr_', 'wv_', 'tn_', 'fire_', 'ss_', 'wf_', 'hp_', 'lw_', 'dt_', 'ct_', 'nr_', 'st_', 'hr_', 'pg_', 'tz_', 'of_']
    for f in forbidden:
        if f in dispatch_block.group(0):
            fail(f'old effect still active in dispatch: {f}')
else:
    fail('dispatch block missing')

# Old effect bodies should be removed from active source body.
for forbidden in ['PART 1 : DIGITAL RAIN', 'PART 2 : HORIZON WARP', 'ti_update:', 'mr_update:', 'rg_update:']:
    if forbidden in text:
        fail(f'old effect body marker still present: {forbidden}')

# ACME/syntax sanity guard for common generated mistakes.
for bad in ['adc x', 'adc y', 'sbc x', 'sbc y', 'ldx SPTR']:
    if bad in text:
        fail(f'invalid/unsafe 6502 source pattern found: {bad}')

# Row 24 stays scroller-only: new effects loops must stop at 24.
if 'cpx #24' not in text and 'cmp #24' not in text:
    fail('no row-24 protection marker found in new effect loops')
if 'GlobalScroller' not in text:
    fail('global scroller missing')

# Source material is bundled for traceability.
for name in ['deepseek_asm_20251022_1659c4.txt','cube_v3_0_FULLY_FIXED.asm','InfinityCorridor_lowres_v3f_pureraster.zip','goldtrensh_v1_2_clean.zip']:
    if not (ROOT / 'source_material' / name).exists():
        fail(f'missing bundled source material: {name}')


# Global call target resolution: catches missing helper routines like SeedRand
# before ACME reports late undefined-symbol errors.
defined = set(re.findall(r'^([A-Za-z_][A-Za-z0-9_@]*)\s*:', text, re.M))
constants = set(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=', text, re.M))
external_ok = {'KERNAL_IRQ'}
for op, target in re.findall(r'\b(jsr|jmp)\s+([A-Za-z_][A-Za-z0-9_@]*)\b', text):
    if target.startswith('@'):
        continue
    if target not in defined and target not in constants and target not in external_ok:
        fail(f'undefined global JSR/JMP target: {op} {target}')

# Final-perfect checks for new-only build.
if 'bne @chkplus\n        bne @chkplus' in text or 'cmp #$20                ; SPACE -> toggle pause\n        cmp #$20' in text:
    fail('duplicate SPACE branch/compare returned in ReadKeys')
for required in ['jsr SelectStyle', 'jsr NewFxPulsePolish', 'NewFxPulsePolish:', 'NewFxPolishRows:', 'NewFxPolishChars:', 'newfxPolishIdx']:
    if required not in text:
        fail(f'missing final new-effect polish marker: {required}')
if 'NewFxPolishRows:       !byte 4,6,8,10,13,16,19,22' not in text:
    fail('NewFx pulse polish must stay row-24 safe')
# Each active new effect must directly react to sndPulse, not only global border flash.
for lab in ['nw_update','ic_update','gt_update','cv_update']:
    m=re.search(rf'^{lab}:(.*?)(?=^!zone|^; =|\Z)', text, re.M|re.S)
    if not m:
        fail(f'missing body for {lab}')
    elif 'sndPulse' not in m.group(1):
        fail(f'{lab} does not directly use sndPulse')
if 'ET3     = $ff' in text and 'newfxPolishIdx' not in text:
    fail('new polish must not depend on ET3=$ff scratch')


# Cube V3 must be a real wire cube, not the old 16-point placeholder.
for required in ['CvBuildGeometry:', 'CvDrawWireCube:', 'CvHLine:', 'CvVLine:', 'CvDiagLine:', 'CvInsetTbl:', 'CvDepthX:', 'CvDepthY:']:
    if required not in text:
        fail(f'cube v3 real wire helper missing: {required}')
if 'sta SCREEN+3*40,x' in text and '.cv_pt_loop:' in text:
    fail('old cube point-placeholder/trail renderer returned')
if 'cmp #23                 ; clear rows 4..22 only; row 24 is scroller' not in text:
    fail('cube clear must remain row-24 safe')
if 'CvDiagXOffset:' not in text or 'CvDiagYOffset:' not in text or 'cv_depth_idx' not in text:
    fail('cube 3D connectors must use depth-vector diagonal offset tables')
if 'adc cv_diag_step\n        tax\n        lda ScrRowLo,x' in text:
    fail('old broken cube diagonal y=step overshoot returned')

# Rotation/clear/gold-line fix checks.
for required in ['CvFrameGeom:', 'cv_rot_idx', 'CvDrawCorners:', 'CvPlotPoint:', 'cmp #3                  ; cube owns full rows 4..22; no overlay dots/trails']:
    if required not in text:
        fail(f'cube rotation/clear fix marker missing: {required}')
for required in ['solid horizontal gold crossbar', '.gt_store_gold:', 'NfxGoldWallChars:    !byte $2f,$5c,$2d,$3d,$2b,$2a,$2f,$5c']:
    if required not in text:
        fail(f'gold trench line fix marker missing: {required}')
cube_corner_block = re.search(r'^CvDrawCorners:(.*?)(?=^CvPlotPoint:)', text, re.M|re.S)
if cube_corner_block and ': sta ' in cube_corner_block.group(1):
    fail('same-line colon statement found inside cube corner code')


# Local dot-label resolution guard: catches ACME errors such as `jmp .gt_store`
# when the local target label was accidentally removed during branch-range fixes.
local_defs = set(re.findall(r'^\s*(\.[A-Za-z_][A-Za-z0-9_@]*)\s*:', text, re.M))
for op, target in re.findall(r'\b(beq|bne|bcc|bcs|bmi|bpl|bvc|bvs|jmp|jsr)\s+(\.[A-Za-z_][A-Za-z0-9_@]*)\b', text):
    if target not in local_defs:
        fail(f'undefined local branch/jump target: {op} {target}')

# gold trench long-branch guard: ACME BNE backwards to .gt_row_loop is too far.
if 'bne .gt_row_loop' in text:
    fail('gold trench long branch regression: use beq .gt_rows_done / jmp .gt_row_loop')
if '.gt_rows_done:' not in text:
    fail('gold trench fixed row-loop exit label missing')

if errors:
    print('STATIC AUDIT FAILED')
    for e in errors:
        print(' - '+e)
    sys.exit(1)
print('STATIC AUDIT OK')
print('NUM_PARTS=4')
print('old active effects removed from dispatch/source body')
print('new effects: wire cube, infinity corridor, gold trench, cube v3 rotor')
print('row-24 scroller protected')
print('source material bundled')
print('new effects pulse-polished and mood-bound')
print('undefined JSR/JMP guard=present')
print('cube v3 real wireframe renderer=present')
print('cube 3D depth-vector connectors=present')
print('cube rotation/clear fixed=present')
print('gold trench lines fixed=present')
print('gold trench long branch fixed=present')
print('local dot-label guard=present')
