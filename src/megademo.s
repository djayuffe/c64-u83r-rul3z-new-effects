; ============================================================================
;  U83R RUL3Z - NEW EFFECTS MEGADEMO   (C64 / ACME)
; ----------------------------------------------------------------------------
;  Current/old effects are removed from active dispatch.  Active sequence now
;  uses only new effects adapted from the uploaded source material:
;     PART 0  WIRE CUBE CLEAN       - from deepseek_asm_20251022 wireframe source
;     PART 1  INFINITY CORRIDOR     - from InfinityCorridor lowres pure-raster
;     PART 2  GOLD TRENCH           - from goldtrensh clean source
;     PART 3  CUBE V3 ROTOR FINAL   - from cube_v3_0 fully fixed source
;
;  These are integrated into the existing safe text-mode megademo framework:
;  VIC bank 0, screen $0400, colour $d800, row-24 global scroller, shared SID
;  score and card transitions.  The old effects are fully removed from active
;  source body; InitTbl/UpdateTbl reference only the four new engines.
; ============================================================================

!cpu 6502

; ------- BASIC stub: 10 SYS 2061 -------
* = $0801
        !word stub_end, 10
        !byte $9e
        !text "2061"
        !byte 0
stub_end:
        !word 0

; ============================================================================
;  Shared hardware constants
; ============================================================================
SCREEN      = $0400
COLOR       = $d800
SCR_COL_OFF = COLOR - SCREEN        ; $d400  (add to screen-hi for colour-hi)

BORDER      = $d020
BKG         = $d021
VIC_CTRL1   = $d011
VIC_CTRL2   = $d016
VIC_RASTER  = $d012
VIC_MEMPTR  = $d018
VIC_IRR     = $d019
VIC_IMR     = $d01a
VIC_BANK    = $dd00
VIC_BANKDDR = $dd02
CIA1_ICR    = $dc0d
CIA2_ICR    = $dc0d+$0100           ; $dd0d
CIA1_TALO   = $dc04
JiffyFPS    = $02a6
KERNAL_IRQ  = $ea31                 ; KERNAL IRQ continuation (keyboard/jiffy)

; --- SID (TunnelVoyager engine) ---
SID        = $d400
SID_V1FLO  = $d400
SID_V1FHI  = $d401
SID_V1CTL  = $d404
SID_V1AD   = $d405
SID_V1SR   = $d406
SID_V2FLO  = $d407
SID_V2FHI  = $d408
SID_V2PWLO = $d409
SID_V2PWHI = $d40a
SID_V2CTL  = $d40b
SID_V2AD   = $d40c
SID_V2SR   = $d40d
SID_V3FLO  = $d40e
SID_V3FHI  = $d40f
SID_V3CTL  = $d412
SID_V3AD   = $d413
SID_V3SR   = $d414
SID_FCLO   = $d415
SID_FCHI   = $d416
SID_RESFLT = $d417
SID_MODEVOL= $d418
MUS_SPEED  = 6                      ; frames per pattern row

IRQ_LINE    = 250

; --- Matrix colours ---
COL_GREEN   = 5
COL_LGREEN  = 13
COL_HEAD    = 1

; --- zero page (music in IRQ must stay disjoint from effects in main loop) ---
ZP_MLO  = $f7      ; music: melody pattern ptr
ZP_MHI  = $f8
ZP_BLO  = $f9      ; music: bass pattern ptr
ZP_BHI  = $fa
SPTR    = $fb      ; effects: screen dest ptr
SPTR_HI = $fc
CPTR    = $fd      ; effects: colour dest ptr
CPTR_HI = $fe
TXTP    = $05      ; effects: text source ptr
TXTP_HI = $06
ET0     = $02
ET1     = $03
ET2     = $04
ET3     = $ff

; ============================================================================
;  ENTRY  (immediately after the BASIC stub, at $080d = SYS 2061)
; ============================================================================
MegaMain:
        sei
        ; CIA IRQs off (we own the IRQ; KERNAL keyboard still scanned via $ea31)
        lda #$7f
        sta CIA1_ICR
        sta CIA2_ICR
        lda CIA1_ICR
        lda CIA2_ICR
        lda #$00
        sta VIC_IMR

        jsr SetupVIC
        jsr ClearScreenColor
        jsr TV_MusInit
        jsr SeedRand
        jsr GlobalScrollerInit

        ; Start on part 0 (title), no preceding card.
        lda #0
        sta partId
        sta demoState           ; 0 = RUN
        jsr InitPart
        jsr SetPartTimer

        jsr InstallIRQ
        cli

MainLoop:
        lda frameReady
        beq MainLoop
        lda #0
        sta frameReady

        jsr ReadKeys            ; SPACE=pause scroller, +/- = speed

        lda demoState
        bne ML_trans
        ; ---- RUN: render active part, count down its timer ----
        jsr UpdatePart
        jsr NewFxPulsePolish
        lda partFramesLo
        bne @decLo
        lda partFramesHi
        beq @expire
        dec partFramesHi
@decLo:
        dec partFramesLo
        jmp ML_scroll
@expire:
        jsr BeginTransition
        jmp ML_scroll
ML_trans:
        jsr StepTransition
ML_scroll:
        jsr GlobalScroller      ; row-24 scroller runs in every scene + transition
        jmp MainLoop

; ============================================================================
;  VIC / screen setup
; ============================================================================
SetupVIC:
        ; VIC bank 0 ($0000-$3fff): CIA2 port A bits 0-1 = %11
        lda VIC_BANKDDR
        ora #%00000011
        sta VIC_BANKDDR
        lda VIC_BANK
        and #%11111100
        ora #%00000011
        sta VIC_BANK
        ; screen $0400, charset $1000 (ROM font mirrored into VIC view)
        lda #$14
        sta VIC_MEMPTR
        ; text mode, 25 rows, 40 cols
        lda #$1b
        sta VIC_CTRL1
        lda #$08
        sta VIC_CTRL2
        lda #$00
        sta BORDER
        sta BKG
        rts

ClearScreenColor:
        ldx #0
        lda #$20
@s:     sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        inx
        bne @s
        ldx #0
        lda #$00
@c:     sta COLOR+$000,x
        sta COLOR+$100,x
        sta COLOR+$200,x
        sta COLOR+$300,x
        inx
        bne @c
        rts


; ============================================================================
;  Startup entropy / deterministic phase seed
; ----------------------------------------------------------------------------
;  This build is deterministic, but the call remains useful to decorrelate
;  polish/music/effect phases at boot.  Keep it local and explicit so ACME never
;  sees an undefined external symbol.
; ============================================================================
SeedRand:
        lda VIC_RASTER
        eor frameCounter
        eor #$5a
        sta newfxPolishPhase
        lda VIC_RASTER
        adc #$17
        sta TV_FlashI
        rts

; ============================================================================
;  GLOBAL SCROLLER (row 24, runs in every scene + transition)
;  Smooth: $d016 fine scroll via scrollReg + full row redraw each frame (so it
;  survives screen clears between parts).  Glow colour overlay scrolls under it.
; ============================================================================
SCR_HOLD    = 150               ; frames to freeze on a greet "stop"
SCR_SENTCOL = 16                ; column at which a $ff sentinel fires a stop
SCR_CORE    = ScrollMsgEnd - ScrollMsg - 40   ; 16-bit core length
gscWinLo !byte 0                ; visible window char offset (16-bit)
gscWinHi !byte 0
gscFine  !byte 7                ; $d016 fine X (7..0)
gscGlow  !byte 0                ; glow colour phase
scrSpeed !byte 2                ; pixels/frame (1..6, +/- keys)
scrPause !byte 0                ; 1 = paused by SPACE
scrHold  !byte 0                ; >0 = auto greet-stop countdown
scrLastLo !byte $ff             ; last window that fired a stop (debounce)
scrLastHi !byte $ff

GlobalScrollerInit:
        lda #0
        sta gscWinLo
        sta gscWinHi
        sta gscGlow
        sta scrPause
        sta scrHold
        lda #2
        sta scrSpeed
        lda #7
        sta gscFine
        lda #$ff
        sta scrLastLo
        sta scrLastHi
        rts

; ReadKeys: SPACE = pause toggle, '+' faster, '-' slower (GETIN $ffe4)
ReadKeys:
        jsr $ffe4
        beq @rkdone
        cmp #$20                ; SPACE -> toggle pause
        bne @chkplus
        lda scrPause
        eor #$01
        sta scrPause
        rts
@chkplus:
        cmp #$2b                ; '+' -> faster (cap 6)
        bne @chkminus
        lda scrSpeed
        cmp #6
        bcs @rkdone
        inc scrSpeed
        rts
@chkminus:
        cmp #$2d                ; '-' -> slower (min 1)
        bne @rkdone
        lda scrSpeed
        cmp #2
        bcc @rkdone
        dec scrSpeed
@rkdone:
        rts

GlobalScroller:
        inc gscGlow             ; glow keeps shimmering even when paused/held
        ; -- frozen during a greet stop --
        lda scrHold
        beq @noHold
        dec scrHold
        jmp @draw
@noHold:
        lda scrPause            ; user pause -> freeze (still redraw for glow)
        bne @draw
        ; -- greet sentinel ($ff) reaching the centre column fires a stop --
        clc
        lda #<ScrollMsg
        adc gscWinLo
        sta TXTP
        lda #>ScrollMsg
        adc gscWinHi
        sta TXTP_HI
        ldy #SCR_SENTCOL
        lda (TXTP),y
        cmp #$ff
        bne @advance
        lda gscWinLo            ; debounce: only fire once per window
        cmp scrLastLo
        bne @fire
        lda gscWinHi
        cmp scrLastHi
        beq @advance
@fire:
        lda gscWinLo
        sta scrLastLo
        lda gscWinHi
        sta scrLastHi
        lda #SCR_HOLD
        sta scrHold
        jmp @draw
@advance:
        lda gscFine
        sec
        sbc scrSpeed
        bcs @savefine
        clc
        adc #8                  ; wrapped -> advance one character
        sta gscFine
        inc gscWinLo            ; gscWin++ (16-bit)
        bne @wchk
        inc gscWinHi
@wchk:
        lda gscWinHi            ; if gscWin >= core length -> wrap to 0
        cmp #>SCR_CORE
        bcc @draw
        bne @wrap
        lda gscWinLo
        cmp #<SCR_CORE
        bcc @draw
@wrap:
        lda #0
        sta gscWinLo
        sta gscWinHi
        lda #$ff
        sta scrLastLo
        sta scrLastHi
        jmp @draw
@savefine:
        sta gscFine
@draw:
        lda gscFine
        ora #$08
        sta scrollReg           ; the IRQ split writes this to $d016 for row 24
        clc
        lda #<ScrollMsg
        adc gscWinLo
        sta TXTP
        lda #>ScrollMsg
        adc gscWinHi
        sta TXTP_HI
        ldy #39
@d:     lda (TXTP),y
        cmp #$ff                ; sentinel -> render as a blank
        bne @notsent
        lda #$20
@notsent:
        sta SCREEN+24*40,y
        tya
        clc
        adc gscGlow
        and #$1f
        tax
        lda GlowRamp,x
        sta COLOR+24*40,y
        dey
        bpl @d
        rts

; ============================================================================
;  IRQ : 50 Hz music tick + frame flag, chained to KERNAL
; ============================================================================
SPLIT_LINE = 241        ; just before char row 24 -> sets fine scroll
MAIN_LINE  = 251        ; below the display -> resets scroll, music, border

InstallIRQ:
        sei
        lda #<MegaMain_IRQ
        sta $0314
        lda #>MegaMain_IRQ
        sta $0315
        lda #MAIN_LINE
        sta VIC_RASTER
        lda VIC_CTRL1
        and #$7f
        sta VIC_CTRL1
        lda #$01
        sta VIC_IMR
        sta VIC_IRR
        cli
        rts

; ---- MAIN stop @ line 251: fine-scroll reset, music tick, frame flag, border ----
MegaMain_IRQ:
        lda #$01
        sta VIC_IRR
        lda #$08                ; 40 cols, X fine scroll = 0 for the upper screen
        sta VIC_CTRL2
        inc frameCounter
        jsr TV_PlayMusic        ; TunnelVoyager music + beat-flash border (50 Hz)
        lda #$01
        sta frameReady
        ; schedule the scroller split for next frame
        lda #SPLIT_LINE
        sta VIC_RASTER
        lda #<MegaSplit_IRQ
        sta $0314
        lda #>MegaSplit_IRQ
        sta $0315
        jmp KERNAL_IRQ          ; chain (keyboard/jiffy)

; ---- SPLIT stop @ line 241: apply the IRQ smooth-scroller fine offset ----
MegaSplit_IRQ:
        lda #$01
        sta VIC_IRR
        lda scrollReg           ; $08|fine  ($08 = no scroll outside part 3)
        sta VIC_CTRL2
        lda #MAIN_LINE
        sta VIC_RASTER
        lda #<MegaMain_IRQ
        sta $0314
        lda #>MegaMain_IRQ
        sta $0315
        jmp $ea81               ; tight return (restore regs + rti)

; ============================================================================
;  Part / transition state machine
; ============================================================================
; demoState: 0 = RUN, 1 = TRANSITION
; transPhase: 0 = wipe to black, 1 = show title card
partId          !byte 0
nextPart        !byte 0
demoState       !byte 0
transPhase      !byte 0
transStyle      !byte 0         ; 0 = row wipe, 1 = colour flash-fade
wipeRow         !byte 0
cardTimer       !byte 0
; flash-fade transition colour ramp (white -> hues -> black)
FlashFadeRamp:  !byte $01,$01,$0f,$07,$0a,$04,$0e,$06,$00,$00
FLASHFADE_LEN = 10
partFramesLo    !byte 0
partFramesHi    !byte 0
frameReady      !byte 0
frameCounter    !byte 0
scrollReg       !byte $08       ; $d016 value applied at the split (fine scroll)
partBorder      !byte 0         ; per-part border base colour

NUM_PARTS = 4
; Per-part border tint (21 parts; horizon-warp/rings removed)
;             title matrix plasma hyper vortex xor waves tunnel fire star wf hp lw dt CUBE nr STAR hr pg tz of
PartBorderTbl:  !byte $06,$0b,$08,$0e

; Per-part run length in frames (low,high).  CUBE (idx 14) lingers; rest snappy.
;                title matrix plasma hyper vortex  xor   waves  tunnel fire  star  wf    hp    lw    dt   CUBE   nr   STAR   hr    pg    tz    of
PartFramesTbl_Lo  !byte <360,<420,<420,<520
PartFramesTbl_Hi  !byte >360,>420,>420,>520

SetPartTimer:
        ldx partId
        lda PartFramesTbl_Lo,x
        sta partFramesLo
        lda PartFramesTbl_Hi,x
        sta partFramesHi
        rts

BeginTransition:
        lda #1
        sta demoState
        lda #0
        sta transPhase
        sta wipeRow
        lda #$00
        sta BKG                 ; clear any title background pulse
        lda transStyle          ; alternate transition FX each time
        eor #1
        sta transStyle
        ; next part = (partId + 1) mod NUM_PARTS
        lda partId
        clc
        adc #1
        cmp #NUM_PARTS
        bcc @ok
        lda #0
@ok:    sta nextPart
        rts

StepTransition:
        lda transPhase
        beq @notcard
        jmp TransCard
@notcard:
        lda transStyle
        bne StepFlashFade
; ---- wipe to black, 3 rows per frame ----
        ldx wipeRow
@wloop:
        cpx #25
        bcs @wipeDone
        ; clear screen row x = space, colour row x = black
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        ldy #39
@wcell:
        lda #$20
        sta (SPTR),y
        lda #$00
        sta (CPTR),y
        dey
        bpl @wcell
        inx
        cpx wipeRow
        ; advance 3 rows total this frame
        txa
        sec
        sbc wipeRow
        cmp #3
        bcc @wloop
@wipeDone2:
        stx wipeRow
        cpx #25
        bcc @wret
        ; wipe complete -> show the card
        jsr ShowCard
        lda #90
        sta cardTimer
        lda #1
        sta transPhase
@wret:
        rts
@wipeDone:
        stx wipeRow
        jsr ShowCard
        lda #90
        sta cardTimer
        lda #1
        sta transPhase
        rts

; ---- alternate FX: full-screen colour flash that fades to black ----
StepFlashFade:
        ldx wipeRow
        lda FlashFadeRamp,x
        sta ET0                 ; this step's flash colour
        lda #$a0
        ldx #0
@ffs:   sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        inx
        bne @ffs
        lda ET0
        ldx #0
@ffc:   sta COLOR+$000,x
        sta COLOR+$100,x
        sta COLOR+$200,x
        sta COLOR+$300,x
        inx
        bne @ffc
        inc wipeRow
        lda wipeRow
        cmp #FLASHFADE_LEN
        bcc @ffret
        jsr ShowCard
        lda #90
        sta cardTimer
        lda #1
        sta transPhase
@ffret:
        rts

TransCard:
        jsr CycleCardColor
        dec cardTimer
        bne @cret
        ; card done -> switch to next part
        jsr ClearScreenColor
        lda nextPart
        sta partId
        jsr InitPart
        jsr SetPartTimer
        lda #0
        sta demoState
@cret:
        rts

; ============================================================================
;  Part dispatch
; ============================================================================
InitPart:
        ldx partId
        lda PartBorderTbl,x
        sta partBorder
        lda #$00
        sta BKG
        lda #$08
        sta scrollReg           ; scroller split inert until the finale sets it
        ; bind the active effect to matching music style/mood
        lda partId
        jsr SelectStyle
        lda partId
        asl
        tax
        lda InitTbl,x
        sta TXTP
        lda InitTbl+1,x
        sta TXTP_HI
        jmp (TXTP)
InitTbl:
        !word nw_init, ic_init, gt_init, cv_init

UpdatePart:
        lda partId
        asl
        tax
        lda UpdateTbl,x
        sta TXTP
        lda UpdateTbl+1,x
        sta TXTP_HI
        jmp (TXTP)
UpdateTbl:
        !word nw_update, ic_update, gt_update, cv_update

; ============================================================================
;  Title cards (shown during transitions) + title part text
; ============================================================================
; Card name/subtitle for the *next* part (table-driven, auto-centred).
ShowCard:
        ldx nextPart
        lda CardNameLo,x
        sta TXTP
        lda CardNameHi,x
        sta TXTP_HI
        ldx #11
        jsr PrintCenteredAuto
        ldx nextPart
        lda CardSubLo,x
        sta TXTP
        lda CardSubHi,x
        sta TXTP_HI
        ldx #13
        jsr PrintCenteredAuto
        rts

; PrintCenteredAuto: TXTP -> $ff-term text, X=row -> measures length, centres
PrintCenteredAuto:
        ldy #0
@m:     lda (TXTP),y
        cmp #$ff
        beq @d
        iny
        bne @m
@d:     jmp PrintCentered       ; X=row, Y=length

; Re-colour the two card rows (10 and 13) with a cycling hue.
CycleCardColor:
        lda frameCounter
        lsr
        lsr
        clc
        adc #$01
        and #$0f
        bne @ok
        lda #$01
@ok:    sta ET0
        ldx #39
@l:     lda ET0
        sta COLOR+10*40,x
        sta COLOR+13*40,x
        dex
        bpl @l
        rts

; PrintCentered: TXTP -> text ($ff term), X=row, Y=length -> centred on row X
PrintCentered:
        ; col = (40 - len) / 2
        tya
        sta ET1                 ; len
        lda #40
        sec
        sbc ET1
        lsr
        sta ET2                 ; col
        ; SPTR = ScrRow[X] + col ; CPTR = colour
        lda ScrRowLo,x
        clc
        adc ET2
        sta SPTR
        lda ScrRowHi,x
        adc #0
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        ldy #0
@p:     lda (TXTP),y
        cmp #$ff
        beq @d
        sta (SPTR),y
        lda #$01
        sta (CPTR),y
        iny
        jmp @p
@d:     rts


; ============================================================================
;  NEW EFFECT PULSE POLISH
; ----------------------------------------------------------------------------
;  Tiny shared visual accent for the new-only set.  It is driven by sndPulse
;  (combined kick/snare/hat/bass/arp energy), writes only rows 4..22, and never
;  touches row 24 so the global scroller remains protected.
; ============================================================================
newfxPolishPhase !byte 0
newfxPolishIdx   !byte 0

NewFxPulsePolish:
        lda partId
        cmp #3                  ; cube owns full rows 4..22; no overlay dots/trails
        bne .nfp_check_pulse
        rts
.nfp_check_pulse:
        lda sndPulse
        bne .nfp_go
        rts
.nfp_go:
        inc newfxPolishPhase
        ldx #7
.nfp_loop:
        stx newfxPolishIdx
        lda NewFxPolishRows,x
        tax
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI

        ldx newfxPolishIdx
        lda NewFxPolishCols,x
        clc
        adc newfxPolishPhase
        adc sndPulse
        and #$1f
        tay

        ldx newfxPolishIdx
        lda sndPulse
        clc
        adc NewFxPolishCharPhase,x
        and #$07
        tax
        lda NewFxPolishChars,x
        sta (SPTR),y

        ldx newfxPolishIdx
        lda sndPulse
        clc
        adc newfxPolishPhase
        adc NewFxPolishColorPhase,x
        and #$0f
        tax
        lda NewFxPolishColors,x
        sta (CPTR),y

        ldx newfxPolishIdx
        dex
        bmi .nfp_done
        jmp .nfp_loop
.nfp_done:
        rts

NewFxPolishRows:       !byte 4,6,8,10,13,16,19,22
NewFxPolishCols:       !byte 2,28,7,23,15,31,5,18
NewFxPolishCharPhase:  !byte 0,4,1,5,2,6,3,7
NewFxPolishColorPhase: !byte 0,5,2,7,4,1,6,3
NewFxPolishChars:      !byte $2a,$2b,$2d,$3d,$51,$57,$58,$5a
NewFxPolishColors:     !byte $06,$0e,$03,$0d,$05,$0a,$07,$01

; ============================================================================
;  NEW ACTIVE EFFECTS ONLY
; ----------------------------------------------------------------------------
;  The following four engines are the only active InitTbl/UpdateTbl targets.
;  They are text-mode adaptations of the uploaded source material and are kept
;  row-24 safe so the global scroller always survives.
; ============================================================================
!zone new_wire_cube
nw_phase !byte 0
nw_init:
        jsr ClearScreenColor
        lda #<NfxWireTitle
        sta TXTP
        lda #>NfxWireTitle
        sta TXTP_HI
        ldx #2
        jsr PrintCenteredAuto
        rts

nw_update:
        inc nw_phase
        lda nw_phase
        lsr
        clc
        adc sndPulse
        and #$0f
        tax
        lda NfxCoolPalette,x
        sta BORDER
        lda #$00
        sta BKG
        ; clear active rows only, keep row 24 for scroller
        ldx #3
.nw_clear_row:
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        ldy #39
.nw_clear_cell:
        lda #$20
        sta (SPTR),y
        lda #$00
        sta (CPTR),y
        dey
        bpl .nw_clear_cell
        inx
        cpx #23
        bne .nw_clear_row
        ; draw 12 edge-ish rows from uploaded wire cube theme
        ldx #0
.nw_edge_loop:
        lda NfxWireRows,x
        tay
        lda ScrRowLo,y
        sta SPTR
        lda ScrRowHi,y
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        txa
        clc
        adc nw_phase
        adc sndPulse
        and #$1f
        tay
        lda NfxWireChars,x
        sta (SPTR),y
        lda NfxWireColors,x
        sta (CPTR),y
        tya
        eor #$1f
        tay
        lda NfxWireChars+12,x
        sta (SPTR),y
        txa
        clc
        adc nw_phase
        adc sndPulse
        and #$0f
        tay
        lda NfxCoolPalette,y
        sta ET0
        ; restore Y target by recomputing mirrored col through X/phase
        txa
        clc
        adc nw_phase
        eor #$1f
        and #$1f
        tay
        lda ET0
        sta (CPTR),y
        inx
        cpx #12
        bne .nw_edge_loop
        rts
!zone

!zone infinity_corridor
ic_phase !byte 0
ic_init:
        jsr ClearScreenColor
        lda #<NfxInfinityTitle
        sta TXTP
        lda #>NfxInfinityTitle
        sta TXTP_HI
        ldx #2
        jsr PrintCenteredAuto
        rts
ic_update:
        inc ic_phase
        lda #0
        sta ic_row_temp
        lda ic_phase
        clc
        adc sndPulse
        and #$07
        ora #$08
        sta scrollReg            ; subtle fine-scroll corridor sway + musical pulse
        lda ic_phase
        lsr
        clc
        adc sndPulse
        and #$0f
        tax
        lda NfxCorridorBg,x
        sta BKG
        lda NfxCorridorBorder,x
        sta BORDER
.ic_row_loop:
        ldx ic_row_temp
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        lda DistLo,x
        sta TXTP
        lda DistHi,x
        sta TXTP_HI
        ldy #39
.ic_col_loop:
        lda (TXTP),y
        clc
        adc ic_phase
        adc sndPulse
        adc NfxColWarp,y
        and #$0f
        tax
        lda NfxCorridorChars,x
        sta (SPTR),y
        txa
        clc
        adc ic_phase
        adc sndPulse
        and #$0f
        tax
        lda NfxCorridorColors,x
        sta (CPTR),y
        dey
        bpl .ic_col_loop
        inc ic_row_temp
        lda ic_row_temp
        cmp #24
        bne .ic_row_loop
        rts
ic_row_temp !byte 0
!zone

!zone gold_trench

gt_phase !byte 0

gt_init:
        jsr ClearScreenColor
        lda #<NfxGoldTitle
        sta TXTP
        lda #>NfxGoldTitle
        sta TXTP_HI
        ldx #2
        jsr PrintCenteredAuto
        rts

gt_update:
        inc gt_phase
        lda #0
        sta gt_row_temp
        lda gt_phase
        lsr
        clc
        adc sndPulse
        and #$07
        tax
        lda NfxGoldBorder,x
        sta BORDER
        lda #$00
        sta BKG
.gt_row_loop:
        ldx gt_row_temp
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        lda NfxTrenchLeft,x
        sta ET0
        lda NfxTrenchRight,x
        sta ET1
        ldy #39
.gt_col_loop:
        ; Gold trench lines: perspective side rails plus beat-synced crossbars.
        lda gt_row_temp
        clc
        adc gt_phase
        adc sndPulse
        and #$03
        bne .gt_not_crossbar
        cpy ET0
        bcc .gt_not_crossbar
        cpy ET1
        bcs .gt_not_crossbar
        lda #$2d                ; solid horizontal gold crossbar
        jmp .gt_store_gold
.gt_not_crossbar:
        cpy ET0
        beq .gt_wall_left
        cpy ET1
        beq .gt_wall_right
        cpy #19
        beq .gt_center
        cpy #20
        beq .gt_center
        lda #$20
        jmp .gt_store
.gt_wall_left:
        lda #$2f                ; / left rail
        jmp .gt_store_gold
.gt_wall_right:
        lda #$5c                ; \ right rail
        jmp .gt_store_gold
.gt_center:
        lda #$2e
        jmp .gt_store_gold
.gt_store:
        sta (SPTR),y
        lda #$00                ; blank interior = black, prevents stale gold trails
        sta (CPTR),y
        dey
        bpl .gt_col_loop
        jmp .gt_row_next
.gt_store_gold:
        sta (SPTR),y
        tya
        clc
        adc gt_phase
        adc sndPulse
        adc ET0
        and #$0f
        tax
        lda NfxGoldPalette,x
        sta (CPTR),y
        dey
        bpl .gt_col_loop
.gt_row_next:
        inc gt_row_temp
        lda gt_row_temp
        cmp #24
        beq .gt_rows_done
        jmp .gt_row_loop
.gt_rows_done:
        rts

gt_row_temp !byte 0
!zone

!zone cube_v3_rotor
; -----------------------------------------------------------------------------
; CUBE V3 ROTOR FINAL - stable text-mode 3D wire cube
; -----------------------------------------------------------------------------
; The previous placeholder only plotted 16 moving points and cleared four rows,
; so the cube could look broken/trail-heavy or invisible.  This version draws a
; real two-plane wire cube every frame: front square, rear square, and four depth
; connectors.  It stays in rows 4..22, leaving row 24 for the global scroller.
cv_phase !byte 0
cv_init:
        jsr ClearScreenColor
        lda #<NfxCubeTitle
        sta TXTP
        lda #>NfxCubeTitle
        sta TXTP_HI
        ldx #2
        jsr PrintCenteredAuto
        rts

cv_update:
        inc cv_phase
        lda cv_phase
        lsr
        clc
        adc sndPulse
        and #$0f
        tax
        lda NfxCubePalette,x
        sta BORDER
        lda #$00
        sta BKG

        jsr CvClearField
        jsr CvBuildGeometry
        jsr CvDrawWireCube
        rts

CvClearField:
        lda #4
        sta cv_row_draw
.cv_cf_row:
        ldx cv_row_draw
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        ldy #39
.cv_cf_col:
        lda #$20
        sta (SPTR),y
        lda #$00
        sta (CPTR),y
        dey
        bpl .cv_cf_col
        inc cv_row_draw
        lda cv_row_draw
        cmp #23                 ; clear rows 4..22 only; row 24 is scroller
        bne .cv_cf_row
        rts

CvBuildGeometry:
        ; Real stable rotation illusion: geometry is frame-table driven, so
        ; the cube never collapses, never reverses line order, and clears cleanly.
        ; Frame table columns: FL, FR, FT, FB, depthX, depthY, diagMode.
        lda cv_phase
        lsr
        lsr
        and #$0f
        sta cv_rot_idx
        asl
        asl
        asl
        sec
        sbc cv_rot_idx          ; idx*7
        tax
        lda CvFrameGeom,x
        sta cv_fl
        inx
        lda CvFrameGeom,x
        sta cv_fr
        inx
        lda CvFrameGeom,x
        sta cv_ft
        inx
        lda CvFrameGeom,x
        sta cv_fb
        inx
        lda CvFrameGeom,x
        sta cv_depth_x
        inx
        lda CvFrameGeom,x
        sta cv_depth_y
        inx
        lda CvFrameGeom,x
        sta cv_depth_idx

        lda cv_fl
        clc
        adc cv_depth_x
        sta cv_bl
        lda cv_fr
        clc
        adc cv_depth_x
        sta cv_br
        lda cv_ft
        clc
        adc cv_depth_y
        sta cv_bt
        lda cv_fb
        clc
        adc cv_depth_y
        sta cv_bb
        rts

CvDrawWireCube:
        ; Back square first, darker.
        lda #$2d
        sta cv_char
        lda #$0b
        sta cv_color
        lda cv_bt
        sta cv_row_draw
        lda cv_bl
        sta cv_col_start
        lda cv_br
        sta cv_col_end
        jsr CvHLine
        lda cv_bb
        sta cv_row_draw
        jsr CvHLine
        lda #$7c
        sta cv_char
        lda cv_bl
        sta cv_col_start
        lda cv_bt
        sta cv_row_start
        lda cv_bb
        sta cv_row_end
        jsr CvVLine
        lda cv_br
        sta cv_col_start
        jsr CvVLine

        ; Front square, bright and pulse-coloured.
        lda #$2d
        sta cv_char
        lda sndPulse
        clc
        adc cv_phase
        and #$0f
        tax
        lda NfxCubePalette,x
        sta cv_color
        lda cv_ft
        sta cv_row_draw
        lda cv_fl
        sta cv_col_start
        lda cv_fr
        sta cv_col_end
        jsr CvHLine
        lda cv_fb
        sta cv_row_draw
        jsr CvHLine
        lda #$7c
        sta cv_char
        lda cv_fl
        sta cv_col_start
        lda cv_ft
        sta cv_row_start
        lda cv_fb
        sta cv_row_end
        jsr CvVLine
        lda cv_fr
        sta cv_col_start
        jsr CvVLine

        ; Depth connectors.  Four corner lines make it visibly 3D.
        lda #$2f
        sta cv_char
        lda #$0e
        sta cv_color
        lda cv_fl
        sta cv_d_x0
        lda cv_ft
        sta cv_d_y0
        lda cv_bl
        sta cv_d_x1
        lda cv_bt
        sta cv_d_y1
        jsr CvDiagLine
        lda cv_fr
        sta cv_d_x0
        lda cv_ft
        sta cv_d_y0
        lda cv_br
        sta cv_d_x1
        lda cv_bt
        sta cv_d_y1
        jsr CvDiagLine
        lda cv_fl
        sta cv_d_x0
        lda cv_fb
        sta cv_d_y0
        lda cv_bl
        sta cv_d_x1
        lda cv_bb
        sta cv_d_y1
        jsr CvDiagLine
        lda cv_fr
        sta cv_d_x0
        lda cv_fb
        sta cv_d_y0
        lda cv_br
        sta cv_d_x1
        lda cv_bb
        sta cv_d_y1
        jsr CvDiagLine
        jsr CvDrawCorners
        rts

CvDrawCorners:
        lda #$2b                ; + corners make cube read as connected 3D object
        sta cv_char
        lda #$01
        sta cv_color
        lda cv_ft
        sta cv_d_y0
        lda cv_fl
        sta cv_d_x0
        jsr CvPlotPoint
        lda cv_ft
        sta cv_d_y0
        lda cv_fr
        sta cv_d_x0
        jsr CvPlotPoint
        lda cv_fb
        sta cv_d_y0
        lda cv_fl
        sta cv_d_x0
        jsr CvPlotPoint
        lda cv_fb
        sta cv_d_y0
        lda cv_fr
        sta cv_d_x0
        jsr CvPlotPoint
        lda cv_bt
        sta cv_d_y0
        lda cv_bl
        sta cv_d_x0
        jsr CvPlotPoint
        lda cv_bt
        sta cv_d_y0
        lda cv_br
        sta cv_d_x0
        jsr CvPlotPoint
        lda cv_bb
        sta cv_d_y0
        lda cv_bl
        sta cv_d_x0
        jsr CvPlotPoint
        lda cv_bb
        sta cv_d_y0
        lda cv_br
        sta cv_d_x0
        jsr CvPlotPoint
        rts

CvPlotPoint:
        ldx cv_d_y0
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        ldy cv_d_x0
        lda cv_char
        sta (SPTR),y
        lda cv_color
        sta (CPTR),y
        rts

CvHLine:
        ldx cv_row_draw
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        ldy cv_col_start
.cv_h_loop:
        lda cv_char
        sta (SPTR),y
        lda cv_color
        sta (CPTR),y
        cpy cv_col_end
        beq .cv_h_done
        iny
        bne .cv_h_loop
.cv_h_done:
        rts

CvVLine:
        lda cv_row_start
        sta cv_row_draw
.cv_v_loop:
        ldx cv_row_draw
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        ldy cv_col_start
        lda cv_char
        sta (SPTR),y
        lda cv_color
        sta (CPTR),y
        lda cv_row_draw
        cmp cv_row_end
        beq .cv_v_done
        inc cv_row_draw
        jmp .cv_v_loop
.cv_v_done:
        rts

CvDiagLine:
        ; Draws 6 sampled points between two corners using the active depth
        ; vector.  The old placeholder used step for both X and Y, so shallow
        ; depth vectors overshot the rear face vertically.  This table-driven
        ; connector lands exactly on the rear square for every depth mode.
        lda cv_depth_idx
        asl
        clc
        adc cv_depth_idx          ; idx*3
        asl                       ; idx*6
        sta cv_diag_base
        lda #0
        sta cv_diag_step
.cv_d_loop:
        lda cv_diag_base
        clc
        adc cv_diag_step
        tax
        lda cv_d_y0
        clc
        adc CvDiagYOffset,x
        tax
        lda ScrRowLo,x
        sta SPTR
        lda ScrRowHi,x
        sta SPTR_HI
        lda SPTR
        sta CPTR
        lda SPTR_HI
        clc
        adc #>SCR_COL_OFF
        sta CPTR_HI
        lda cv_diag_base
        clc
        adc cv_diag_step
        tax
        lda cv_d_x0
        clc
        adc CvDiagXOffset,x
        tay
        lda cv_char
        sta (SPTR),y
        lda cv_color
        sta (CPTR),y
        inc cv_diag_step
        lda cv_diag_step
        cmp #6
        bne .cv_d_loop
        rts

cv_idx       !byte 0
cv_row_draw  !byte 0
cv_row_start !byte 0
cv_row_end   !byte 0
cv_col_start !byte 0
cv_col_end   !byte 0
cv_char      !byte 0
cv_color     !byte 0
cv_inset     !byte 0
cv_depth_idx !byte 0
cv_rot_idx   !byte 0
cv_depth_x   !byte 0
cv_depth_y   !byte 0
cv_fl        !byte 0
cv_fr        !byte 0
cv_ft        !byte 0
cv_fb        !byte 0
cv_bl        !byte 0
cv_br        !byte 0
cv_bt        !byte 0
cv_bb        !byte 0
cv_d_x0      !byte 0
cv_d_y0      !byte 0
cv_d_x1      !byte 0
cv_d_y1      !byte 0
cv_diag_step !byte 0
cv_diag_base !byte 0
; Six-point connector offsets for the 8 active depth vectors.
CvDiagXOffset:
        !byte 0,1,2,3,4,5
        !byte 0,1,2,2,3,4
        !byte 0,1,1,2,2,3
        !byte 0,0,1,1,2,2
        !byte 0,1,2,3,4,5
        !byte 0,1,2,4,5,6
        !byte 0,1,3,4,6,7
        !byte 0,1,2,4,5,6
CvDiagYOffset:
        !byte 0,1,1,2,2,3
        !byte 0,1,1,2,2,3
        !byte 0,0,1,1,2,2
        !byte 0,0,0,1,1,1
        !byte 0,1,1,2,2,3
        !byte 0,1,1,2,2,3
        !byte 0,0,1,1,2,2
        !byte 0,0,0,1,1,1
; 16 stable cube rotation frames: FL,FR,FT,FB,depthX,depthY,diagMode.
; All coordinates stay inside cols 0..39 and rows 4..22.
CvFrameGeom:
        !byte 9,30,7,18,5,3,0
        !byte 10,29,7,18,6,2,1
        !byte 11,28,8,18,7,2,2
        !byte 12,27,8,17,6,1,3
        !byte 13,26,9,17,5,1,4
        !byte 12,27,8,17,4,1,5
        !byte 11,28,8,18,3,2,6
        !byte 10,29,7,18,4,2,7
        !byte 9,30,7,18,5,3,0
        !byte 8,31,7,18,6,3,1
        !byte 7,32,8,18,7,2,2
        !byte 8,31,8,17,6,1,3
        !byte 9,30,9,17,5,1,4
        !byte 8,31,8,17,4,1,5
        !byte 7,32,8,18,3,2,6
        !byte 8,31,7,18,4,3,7
; Legacy compatibility markers kept for audit readability; geometry now uses CvFrameGeom.
CvInsetTbl:  !byte 0,1,2,3,3,2,1,0
CvDepthX:    !byte 5,4,3,2,5,6,7,6
CvDepthY:    !byte 3,3,2,1,3,3,2,1
!zone

; ============================================================================
;  OLD EFFECT BODY REMOVED FROM ACTIVE SOURCE
; ----------------------------------------------------------------------------
;  Previous matrix/rings/plasma/star/etc. bodies are not present in the active
;  source body.  InitTbl/UpdateTbl targets only nw/ic/gt/cv.
; ============================================================================

; ============================================================================
;  SID MUSIC ENGINE  (new-effects score)
;  Filtered saw bass / pulse arpeggiator / clean grid percussion, one arranged
;  256-row cyber tune.  Runs once per frame (50 Hz) from the IRQ.
; ============================================================================
TV_MusTick   !byte MUS_SPEED
TV_MusRow    !byte 0
TV_ArpStep   !byte 0
TV_FlashI    !byte 0
TV_Beat      !byte 0
sndPulse     !byte 0      ; combined sound energy (kick+snare+hat+bass+arp); all effects react to it
TV_FiltPhase !byte 0
TV_PwmPhase  !byte 0
TV_KickEnv   !byte 0
TV_FlashRamp: !byte $00,$06,$04,$0e,$03,$05,$0d,$07,$01
BeatBorderTbl: !byte $02,$08,$07,$05,$0e,$04,$0a,$0d   ; per-beat rainbow flash

TV_MusInit:
        lda #0
        ldx #$18
.clr:   sta SID,x
        dex
        bpl .clr
        lda #$a1 : sta SID_RESFLT      ; resonant low-pass on the bass
        lda #$1f : sta SID_MODEVOL     ; LP + max volume
        lda #$0a : sta SID_V1AD
        lda #$08 : sta SID_V1SR
        lda #$00 : sta SID_V2PWLO
        lda #$08 : sta SID_V2PWHI
        lda #$00 : sta SID_V2AD
        lda #$f0 : sta SID_V2SR
        lda #0
        sta TV_MusRow
        sta TV_ArpStep
        sta TV_FlashI
        sta TV_Beat
        sta musTranspose
        sta curSong
        lda #MUS_SPEED
        sta musSpeed
        sta TV_MusTick
        lda #0
        jsr SelectStyle         ; load track 0 (song + instrument + tempo)
        ldx #0
        jsr TV_MusRowTrigger
        rts
curSong  !byte 0

; --- per-scene music variety: transpose (semitones) + tempo (frames/row) ---
musTranspose !byte 0
musSpeed     !byte MUS_SPEED
;                 title mat rng pls hyp vor xor wav tun star
MusXposeTbl: !byte 0,   3,  7,  5,  2, 10,  3,  8,  5,  7,  0
MusSpeedTbl: !byte 7,   4,  6,  5,  4,  6,  4,  5,  4,  4,  6

; SetMusicScene: pick transpose for the current partId (A=partId).
; (tempo + song style are chosen by SelectStyle.)
SetMusicScene:
        tax
        lda MusXposeTbl,x
        sta musTranspose
        rts

; SelectStyle: switch the whole song + instrument + tempo + filter (A=style 0..3)
; Patches the engine's read operands to the chosen song's pattern tables.
SelectStyle:
        tax
        lda SongBassLo,x : sta pBass+1
        lda SongBassHi,x : sta pBass+2
        lda SongArp0Lo,x : sta pArp0+1
        lda SongArp0Hi,x : sta pArp0+2
        lda SongArp1Lo,x : sta pArp1+1
        lda SongArp1Hi,x : sta pArp1+2
        lda SongArp2Lo,x : sta pArp2+1
        lda SongArp2Hi,x : sta pArp2+2
        lda SongDrumLo,x : sta pDrum+1
        lda SongDrumHi,x : sta pDrum+2
        lda SongFiltLo,x : sta pFilt+1
        lda SongFiltHi,x : sta pFilt+2
        lda StyleBassWaveTbl,x : sta styleBassWave
        lda StyleArpWaveTbl,x  : sta styleArpWave
        lda StyleSpeedTbl,x    : sta musSpeed
        lda StyleResTbl,x      : sta SID_RESFLT
        lda StyleVolTbl,x      : sta SID_MODEVOL
        lda StyleXposeTbl,x    : sta musTranspose   ; per-track key -> 6 distinct tunes
        rts

; MusXpose: A = note index -> + transpose, clamped into the 0..95 freq table
MusXpose:
        clc
        adc musTranspose
        cmp #96
        bcc .mx
        sec
        sbc #12
.mx:    rts

TV_PlayMusic:
        jsr TV_MusArp
        jsr TV_MusFilter
        jsr TV_MusPwm
        jsr TV_DrumPitch
        dec TV_MusTick
        bne .doFlash
        lda musSpeed
        sta TV_MusTick
        ldx TV_MusRow
        inx                            ; 256-row song wraps for free
        stx TV_MusRow
        bne .sameSong
        ; song looped -> advance to the next of the 6 tracks (full arc each)
        inc curSong
        lda curSong
        cmp #6
        bcc @songOk
        lda #0
@songOk:
        sta curSong
        jsr SelectStyle
.sameSong:
        ldx TV_MusRow
        jsr TV_MusRowTrigger
.doFlash:
        jsr TV_MusFlash
        rts

TV_MusFilter:
        lda TV_FiltPhase
        clc
        adc #3
        sta TV_FiltPhase
        bpl .tri
        eor #$ff
.tri:   lsr
        lsr
        ldx TV_MusRow
        clc
pFilt:  adc MUS_FILT,x          ; operand patched by SelectStyle
        sta SID_FCHI
        lda #0
        sta SID_FCLO
        rts

TV_MusPwm:
        lda TV_PwmPhase
        clc
        adc #2
        sta TV_PwmPhase
        bpl .pw
        eor #$ff
.pw:    lsr
        lsr
        lsr
        lsr
        clc
        adc #$04
        sta SID_V2PWHI
        lda #$00
        sta SID_V2PWLO
        rts

TV_DrumPitch:
        lda TV_KickEnv
        beq .dpDone
        clc
        adc #$04
        sta SID_V3FHI
        dec TV_KickEnv
.dpDone:
        rts

TV_MusArp:
        ldx TV_MusRow
        ldy TV_ArpStep
        cpy #0
        beq .a0
        cpy #1
        beq .a1
pArp2:  lda MUS_ARP2,x
        jmp .have
.a0:
pArp0:  lda MUS_ARP0,x
        jmp .have
.a1:
pArp1:  lda MUS_ARP1,x
.have:  cmp #$ff
        beq .silent
        jsr MusXpose
        tay
        lda SID_FREQLO,y : sta SID_V2FLO
        lda SID_FREQHI,y : sta SID_V2FHI
        lda styleArpWave : sta SID_V2CTL    ; per-style arp waveform (gate on)
        lda #3 : jsr SndAdd                 ; arp notes feed the pulse
        jmp .step
.silent:
        lda styleArpWave
        and #$fe                            ; gate off (clear bit0)
        sta SID_V2CTL
.step:  inc TV_ArpStep
        lda TV_ArpStep
        cmp #3
        bcc .ok
        lda #0
        sta TV_ArpStep
.ok:    rts

TV_MusRowTrigger:
pBass:  lda MUS_BASS,x
        cmp #$ff
        beq .nobass
        jsr MusXpose
        tay
        lda SID_FREQLO,y : sta SID_V1FLO
        lda SID_FREQHI,y : sta SID_V1FHI
        lda #$20         : sta SID_V1CTL
        lda styleBassWave : sta SID_V1CTL    ; per-style bass waveform
        lda #4 : jsr SndAdd                  ; bass note feeds the sound pulse
.nobass:
pDrum:  lda MUS_DRUM,x
        beq .mdone
        cmp #1
        beq .kick
        cmp #2
        beq .hat
        lda #$00 : sta TV_KickEnv      ; snare
        lda #$00 : sta SID_V3FLO
        lda #$28 : sta SID_V3FHI
        lda #$09 : sta SID_V3AD
        lda #$00 : sta SID_V3SR
        lda #$80 : sta SID_V3CTL
        lda #$81 : sta SID_V3CTL
        jmp .flash
.kick:
        lda #$00 : sta SID_V3FLO
        lda #$10 : sta SID_V3FHI
        lda #$08 : sta SID_V3AD
        lda #$00 : sta SID_V3SR
        lda #$10 : sta SID_V3CTL
        lda #$11 : sta SID_V3CTL
        lda #12  : sta TV_KickEnv
        jmp .flash
.hat:
        lda #$00 : sta TV_KickEnv
        lda #$00 : sta SID_V3FLO
        lda #$f0 : sta SID_V3FHI
        lda #$03 : sta SID_V3AD
        lda #$00 : sta SID_V3SR
        lda #$80 : sta SID_V3CTL
        lda #$81 : sta SID_V3CTL
        lda #6 : jsr SndAdd                  ; hats shimmer into the pulse
.mdone: rts
.flash:
        lda #$08 : sta TV_FlashI
        lda #13  : sta sndPulse              ; kick/snare slam the pulse
        inc TV_Beat
        rts

; SndAdd: A = amount, add to sndPulse clamped at 16 (A clobbered)
SndAdd:
        clc
        adc sndPulse
        cmp #17
        bcc @s
        lda #16
@s:     sta sndPulse
        rts

TV_MusFlash:
        lda sndPulse            ; decay the combined sound pulse each frame
        beq .nopd
        sec
        sbc #2
        bcs .pds
        lda #0
.pds:   sta sndPulse
.nopd:
        ldx TV_FlashI
        beq .dark
        cpx #4                  ; strong part of the flash -> rainbow per-beat colour
        bcc .ramp
        lda TV_Beat
        and #$07
        tay
        lda BeatBorderTbl,y
        sta BORDER
        dec TV_FlashI
        rts
.ramp:
        lda TV_FlashRamp,x
        sta BORDER
        dec TV_FlashI
        rts
.dark:  lda partBorder
        sta BORDER
        rts

; ---- inline music data (generated by TunnelVoyager gen_tables.py) ----
SID_FREQLO:
        !byte $16,$27,$39,$4b,$5f,$74,$8a,$a1,$ba,$d4,$f0,$0e,$2d,$4e,$71,$96
        !byte $be,$e7,$14,$42,$74,$a9,$e0,$1b,$5a,$9c,$e2,$2d,$7b,$cf,$27,$85
        !byte $e8,$51,$c1,$37,$b4,$38,$c4,$59,$f7,$9d,$4e,$0a,$d0,$a2,$81,$6d
        !byte $67,$70,$89,$b2,$ed,$3b,$9c,$13,$a0,$45,$02,$da,$ce,$e0,$11,$64
        !byte $da,$76,$39,$26,$40,$89,$04,$b4,$9c,$c0,$23,$c8,$b4,$eb,$72,$4c
        !byte $80,$12,$08,$68,$39,$80,$45,$90,$68,$d6,$e3,$99,$00,$24,$10,$ff
SID_FREQHI:
        !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02
        !byte $02,$02,$03,$03,$03,$03,$03,$04,$04,$04,$04,$05,$05,$05,$06,$06
        !byte $06,$07,$07,$08,$08,$09,$09,$0a,$0a,$0b,$0c,$0d,$0d,$0e,$0f,$10
        !byte $11,$12,$13,$14,$15,$17,$18,$1a,$1b,$1d,$1f,$20,$22,$24,$27,$29
        !byte $2b,$2e,$31,$34,$37,$3a,$3e,$41,$45,$49,$4e,$52,$57,$5c,$62,$68
        !byte $6e,$75,$7c,$83,$8b,$93,$9c,$a5,$af,$b9,$c4,$d0,$dd,$ea,$f8,$ff
MUS_BASS:
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff
        !byte $20,$ff,$ff,$ff,$20,$ff,$ff,$ff,$20,$ff,$ff,$ff,$20,$ff,$ff,$ff
        !byte $18,$ff,$18,$ff,$1f,$ff,$18,$ff,$18,$ff,$ff,$ff,$1f,$ff,$18,$ff
        !byte $20,$ff,$20,$ff,$27,$ff,$20,$ff,$20,$ff,$ff,$ff,$27,$ff,$20,$ff
        !byte $22,$ff,$22,$ff,$29,$ff,$22,$ff,$22,$ff,$ff,$ff,$29,$ff,$22,$ff
        !byte $1f,$ff,$1f,$ff,$26,$ff,$1f,$ff,$1f,$ff,$ff,$ff,$26,$ff,$1f,$ff
        !byte $1d,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$1d,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$24,$18,$ff,$18,$24,$18,$ff,$18,$24,$18,$ff,$18,$24,$18,$ff
        !byte $20,$2c,$20,$ff,$20,$2c,$20,$ff,$20,$2c,$20,$ff,$20,$2c,$20,$ff
        !byte $22,$2e,$22,$ff,$22,$2e,$22,$ff,$22,$2e,$22,$ff,$22,$2e,$22,$ff
        !byte $1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
MUS_ARP0:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff
        !byte $38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $35,$ff,$ff,$ff,$35,$ff,$ff,$ff,$35,$ff,$ff,$ff,$35,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
MUS_ARP1:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff
        !byte $3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $38,$ff,$ff,$ff,$38,$ff,$ff,$ff,$38,$ff,$ff,$ff,$38,$ff,$ff,$ff
        !byte $3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
MUS_ARP2:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff
        !byte $3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f
        !byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff
        !byte $3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f
        !byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
MUS_DRUM:
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00,$02,$02
        !byte $01,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
MUS_FILT:
        !byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
        !byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
        !byte $30,$34,$38,$3c,$40,$44,$48,$4c,$51,$55,$59,$5d,$61,$65,$69,$6d
        !byte $72,$76,$7a,$7e,$82,$86,$8a,$8e,$93,$97,$9b,$9f,$a3,$a7,$ab,$b0
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $38,$3c,$40,$45,$49,$4d,$52,$56,$5b,$5f,$63,$68,$6c,$71,$75,$79
        !byte $7e,$82,$86,$8b,$8f,$94,$98,$9c,$a1,$a5,$aa,$ae,$b2,$b7,$bb,$c0
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $80,$7d,$7a,$77,$74,$71,$6e,$6b,$68,$65,$62,$5e,$5b,$58,$55,$52
        !byte $4f,$4c,$49,$46,$43,$3f,$3c,$39,$36,$33,$30,$2d,$2a,$27,$24,$20
Song1Bass:
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff
        !byte $22,$ff,$ff,$ff,$22,$ff,$ff,$ff,$22,$ff,$ff,$ff,$22,$ff,$ff,$ff
        !byte $18,$ff,$24,$ff,$18,$ff,$24,$ff,$18,$ff,$24,$ff,$18,$ff,$24,$ff
        !byte $20,$ff,$2c,$ff,$20,$ff,$2c,$ff,$20,$ff,$2c,$ff,$20,$ff,$2c,$ff
        !byte $22,$ff,$2e,$ff,$22,$ff,$2e,$ff,$22,$ff,$2e,$ff,$22,$ff,$2e,$ff
        !byte $18,$ff,$24,$ff,$18,$ff,$24,$ff,$18,$ff,$24,$ff,$18,$ff,$24,$ff
        !byte $1d,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$1d,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$24,$18,$ff,$18,$24,$18,$ff,$18,$24,$18,$ff,$18,$24,$18,$ff
        !byte $22,$2e,$22,$ff,$22,$2e,$22,$ff,$22,$2e,$22,$ff,$22,$2e,$22,$ff
        !byte $20,$2c,$20,$ff,$20,$2c,$20,$ff,$20,$2c,$20,$ff,$20,$2c,$20,$ff
        !byte $1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
Song1Arp0:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff
        !byte $3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $35,$ff,$ff,$ff,$35,$ff,$ff,$ff,$35,$ff,$ff,$ff,$35,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
Song1Arp1:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff
        !byte $3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $38,$ff,$ff,$ff,$38,$ff,$ff,$ff,$38,$ff,$ff,$ff,$38,$ff,$ff,$ff
        !byte $3b,$ff,$ff,$ff,$3b,$ff,$ff,$ff,$3b,$ff,$ff,$ff,$3b,$ff,$ff,$ff
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c
        !byte $3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
Song1Arp2:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff
        !byte $41,$ff,$41,$ff,$41,$ff,$41,$ff,$41,$ff,$41,$ff,$41,$ff,$41,$ff
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f
        !byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff
        !byte $3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
        !byte $3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
Song1Drum:
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00,$02,$02
        !byte $01,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
Song1Filt:
        !byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
        !byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
        !byte $30,$34,$38,$3c,$40,$44,$48,$4c,$51,$55,$59,$5d,$61,$65,$69,$6d
        !byte $72,$76,$7a,$7e,$82,$86,$8a,$8e,$93,$97,$9b,$9f,$a3,$a7,$ab,$b0
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $38,$3c,$40,$45,$49,$4d,$52,$56,$5b,$5f,$63,$68,$6c,$71,$75,$79
        !byte $7e,$82,$86,$8b,$8f,$94,$98,$9c,$a1,$a5,$aa,$ae,$b2,$b7,$bb,$c0
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $80,$7d,$7a,$77,$74,$71,$6e,$6b,$68,$65,$62,$5e,$5b,$58,$55,$52
        !byte $4f,$4c,$49,$46,$43,$3f,$3c,$39,$36,$33,$30,$2d,$2a,$27,$24,$20
Song2Bass:
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $1b,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff
        !byte $20,$ff,$ff,$ff,$20,$ff,$ff,$ff,$20,$ff,$ff,$ff,$20,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$18,$ff,$18,$ff,$ff,$ff,$ff,$ff,$18,$ff
        !byte $1b,$ff,$ff,$ff,$ff,$ff,$1b,$ff,$1b,$ff,$ff,$ff,$ff,$ff,$1b,$ff
        !byte $20,$ff,$ff,$ff,$ff,$ff,$20,$ff,$20,$ff,$ff,$ff,$ff,$ff,$20,$ff
        !byte $22,$ff,$ff,$ff,$ff,$ff,$22,$ff,$22,$ff,$ff,$ff,$ff,$ff,$22,$ff
        !byte $1d,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$1d,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $1b,$ff,$ff,$ff,$1b,$ff,$ff,$ff,$1b,$ff,$ff,$ff,$1b,$ff,$ff,$ff
        !byte $22,$ff,$ff,$ff,$22,$ff,$ff,$ff,$22,$ff,$ff,$ff,$22,$ff,$ff,$ff
        !byte $20,$ff,$ff,$ff,$20,$ff,$ff,$ff,$20,$ff,$ff,$ff,$20,$ff,$ff,$ff
        !byte $1f,$ff,$ff,$ff,$1f,$ff,$ff,$ff,$1f,$ff,$ff,$ff,$1f,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
Song2Arp0:
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
        !byte $30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff
        !byte $38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff
        !byte $30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff
        !byte $33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff
        !byte $38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff,$38,$ff
        !byte $3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff
        !byte $35,$ff,$ff,$ff,$35,$ff,$ff,$ff,$35,$ff,$ff,$ff,$35,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
Song2Arp1:
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff
        !byte $3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff
        !byte $33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff
        !byte $37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff
        !byte $3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff,$3c,$ff
        !byte $3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff,$3e,$ff
        !byte $38,$ff,$ff,$ff,$38,$ff,$ff,$ff,$38,$ff,$ff,$ff,$38,$ff,$ff,$ff
        !byte $3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
Song2Arp2:
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $3a,$ff,$ff,$ff,$3a,$ff,$ff,$ff,$3a,$ff,$ff,$ff,$3a,$ff,$ff,$ff
        !byte $37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff
        !byte $3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff
        !byte $37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff
        !byte $3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff,$3a,$ff
        !byte $3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff
        !byte $41,$ff,$41,$ff,$41,$ff,$41,$ff,$41,$ff,$41,$ff,$41,$ff,$41,$ff
        !byte $3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff,$3c,$ff,$ff,$ff
        !byte $3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff
        !byte $3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a,$3a
        !byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
        !byte $3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
Song2Drum:
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00,$02,$02
        !byte $01,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
Song2Filt:
        !byte $40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40
        !byte $40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40
        !byte $30,$34,$38,$3c,$40,$44,$48,$4c,$51,$55,$59,$5d,$61,$65,$69,$6d
        !byte $72,$76,$7a,$7e,$82,$86,$8a,$8e,$93,$97,$9b,$9f,$a3,$a7,$ab,$b0
        !byte $58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58
        !byte $58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58
        !byte $58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58
        !byte $58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58,$58
        !byte $38,$3c,$40,$45,$49,$4d,$52,$56,$5b,$5f,$63,$68,$6c,$71,$75,$79
        !byte $7e,$82,$86,$8b,$8f,$94,$98,$9c,$a1,$a5,$aa,$ae,$b2,$b7,$bb,$c0
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
        !byte $80,$7d,$7a,$77,$74,$71,$6e,$6b,$68,$65,$62,$5e,$5b,$58,$55,$52
        !byte $4f,$4c,$49,$46,$43,$3f,$3c,$39,$36,$33,$30,$2d,$2a,$27,$24,$20
Song3Bass:
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff,$18,$ff,$ff,$ff
        !byte $18,$18,$24,$18,$18,$1f,$18,$18,$18,$18,$24,$18,$1f,$18,$18,$1b
        !byte $18,$18,$24,$18,$18,$1f,$18,$18,$18,$18,$24,$18,$1f,$18,$18,$1b
        !byte $1d,$1d,$29,$1d,$1d,$24,$1d,$1d,$1d,$1d,$29,$1d,$24,$1d,$1d,$20
        !byte $1d,$1d,$29,$1d,$1d,$24,$1d,$1d,$1d,$1d,$29,$1d,$24,$1d,$1d,$20
        !byte $1a,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$1a,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$24,$18,$ff,$18,$24,$18,$ff,$18,$24,$18,$ff,$18,$24,$18,$ff
        !byte $18,$24,$18,$ff,$18,$24,$18,$ff,$18,$24,$18,$ff,$18,$24,$18,$ff
        !byte $20,$2c,$20,$ff,$20,$2c,$20,$ff,$20,$2c,$20,$ff,$20,$2c,$20,$ff
        !byte $1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff,$1f,$2b,$1f,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $18,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$18,$ff,$ff,$ff,$ff,$ff,$ff,$ff
Song3Arp0:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff
        !byte $30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff,$30,$ff
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35
        !byte $35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35
        !byte $32,$ff,$ff,$ff,$32,$ff,$ff,$ff,$32,$ff,$ff,$ff,$32,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
        !byte $38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
        !byte $30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff,$30,$ff,$ff,$ff
Song3Arp1:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff
        !byte $33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff,$33,$ff
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38
        !byte $38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38,$38
        !byte $35,$ff,$ff,$ff,$35,$ff,$ff,$ff,$35,$ff,$ff,$ff,$35,$ff,$ff,$ff
        !byte $3b,$ff,$ff,$ff,$3b,$ff,$ff,$ff,$3b,$ff,$ff,$ff,$3b,$ff,$ff,$ff
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
        !byte $3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c
        !byte $3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b,$3b
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
        !byte $33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff,$33,$ff,$ff,$ff
Song3Arp2:
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff
        !byte $37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff,$37,$ff
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c
        !byte $3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c,$3c
        !byte $38,$ff,$ff,$ff,$38,$ff,$ff,$ff,$38,$ff,$ff,$ff,$38,$ff,$ff,$ff
        !byte $3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff,$3e,$ff,$ff,$ff
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37,$37
        !byte $3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f
        !byte $3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e,$3e
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
        !byte $37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff,$37,$ff,$ff,$ff
Song3Drum:
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00,$02,$02
        !byte $01,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$02,$02,$02,$03,$02,$02,$02,$01,$02,$02,$02,$03,$02,$02,$02
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
Song3Filt:
        !byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
        !byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
        !byte $30,$34,$38,$3c,$40,$44,$48,$4c,$51,$55,$59,$5d,$61,$65,$69,$6d
        !byte $72,$76,$7a,$7e,$82,$86,$8a,$8e,$93,$97,$9b,$9f,$a3,$a7,$ab,$b0
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
        !byte $38,$3c,$40,$45,$49,$4d,$52,$56,$5b,$5f,$63,$68,$6c,$71,$75,$79
        !byte $7e,$82,$86,$8b,$8f,$94,$98,$9c,$a1,$a5,$aa,$ae,$b2,$b7,$bb,$c0
        !byte $40,$45,$4a,$4f,$54,$59,$5e,$64,$69,$6e,$73,$78,$7d,$83,$88,$8d
        !byte $92,$97,$9c,$a2,$a7,$ac,$b1,$b6,$bb,$c1,$c6,$cb,$d0,$d5,$da,$e0
        !byte $40,$45,$4a,$4f,$54,$59,$5e,$64,$69,$6e,$73,$78,$7d,$83,$88,$8d
        !byte $92,$97,$9c,$a2,$a7,$ac,$b1,$b6,$bb,$c1,$c6,$cb,$d0,$d5,$da,$e0
        !byte $80,$7d,$7a,$77,$74,$71,$6e,$6b,$68,$65,$62,$5e,$5b,$58,$55,$52
        !byte $4f,$4c,$49,$46,$43,$3f,$3c,$39,$36,$33,$30,$2d,$2a,$27,$24,$20


; ============================================================================
;  TECHNO tracks (styles 4 & 5): new 4-on-floor / breakdown drums + filter
;  sweeps, layered over existing melody/bass data for two extra SID tunes.
; ============================================================================
TechnoDrum1:
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
        !byte $01,$02,$00,$02,$03,$02,$00,$02,$01,$02,$00,$02,$03,$02,$00,$02
TechnoDrum2:
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $01,$00,$02,$00,$00,$00,$02,$00,$03,$00,$02,$00,$00,$00,$02,$00
        !byte $03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02
TechnoFilt1:
        !byte $30,$32,$35,$38,$3b,$3d,$40,$43,$46,$48,$4b,$4e,$51,$53,$56,$59
        !byte $5c,$5e,$61,$64,$67,$69,$6c,$6f,$72,$74,$77,$7a,$7d,$7f,$82,$85
        !byte $88,$8a,$8d,$90,$93,$95,$98,$9b,$9e,$a0,$a3,$a6,$a9,$ab,$ae,$b1
        !byte $b4,$b6,$b9,$bc,$bf,$c1,$c4,$c7,$ca,$cc,$cf,$d2,$d5,$d7,$da,$dd
        !byte $30,$32,$35,$38,$3b,$3d,$40,$43,$46,$48,$4b,$4e,$51,$53,$56,$59
        !byte $5c,$5e,$61,$64,$67,$69,$6c,$6f,$72,$74,$77,$7a,$7d,$7f,$82,$85
        !byte $88,$8a,$8d,$90,$93,$95,$98,$9b,$9e,$a0,$a3,$a6,$a9,$ab,$ae,$b1
        !byte $b4,$b6,$b9,$bc,$bf,$c1,$c4,$c7,$ca,$cc,$cf,$d2,$d5,$d7,$da,$dd
        !byte $30,$32,$35,$38,$3b,$3d,$40,$43,$46,$48,$4b,$4e,$51,$53,$56,$59
        !byte $5c,$5e,$61,$64,$67,$69,$6c,$6f,$72,$74,$77,$7a,$7d,$7f,$82,$85
        !byte $88,$8a,$8d,$90,$93,$95,$98,$9b,$9e,$a0,$a3,$a6,$a9,$ab,$ae,$b1
        !byte $b4,$b6,$b9,$bc,$bf,$c1,$c4,$c7,$ca,$cc,$cf,$d2,$d5,$d7,$da,$dd
        !byte $30,$32,$35,$38,$3b,$3d,$40,$43,$46,$48,$4b,$4e,$51,$53,$56,$59
        !byte $5c,$5e,$61,$64,$67,$69,$6c,$6f,$72,$74,$77,$7a,$7d,$7f,$82,$85
        !byte $88,$8a,$8d,$90,$93,$95,$98,$9b,$9e,$a0,$a3,$a6,$a9,$ab,$ae,$b1
        !byte $b4,$b6,$b9,$bc,$bf,$c1,$c4,$c7,$ca,$cc,$cf,$d2,$d5,$d7,$da,$dd
TechnoFilt2:
        !byte $e0,$df,$df,$df,$df,$df,$df,$df,$df,$df,$df,$df,$de,$de,$de,$de
        !byte $de,$dd,$dd,$dd,$dd,$dc,$dc,$dc,$db,$db,$db,$da,$da,$d9,$d9,$d9
        !byte $d8,$d8,$d7,$d7,$d6,$d6,$d5,$d5,$d4,$d4,$d3,$d2,$d2,$d1,$d0,$d0
        !byte $cf,$cf,$ce,$cd,$cc,$cc,$cb,$ca,$ca,$c9,$c8,$c7,$c6,$c6,$c5,$c4
        !byte $c3,$c2,$c1,$c1,$c0,$bf,$be,$bd,$bc,$bb,$ba,$b9,$b8,$b7,$b6,$b6
        !byte $b5,$b4,$b3,$b2,$b1,$b0,$ae,$ad,$ac,$ab,$aa,$a9,$a8,$a7,$a6,$a5
        !byte $a4,$a3,$a2,$a1,$9f,$9e,$9d,$9c,$9b,$9a,$99,$97,$96,$95,$94,$93
        !byte $92,$91,$8f,$8e,$8d,$8c,$8b,$8a,$88,$87,$86,$85,$84,$82,$81,$80
        !byte $7f,$7e,$7d,$7b,$7a,$79,$78,$77,$75,$74,$73,$72,$71,$70,$6e,$6d
        !byte $6c,$6b,$6a,$69,$68,$66,$65,$64,$63,$62,$61,$60,$5e,$5d,$5c,$5b
        !byte $5a,$59,$58,$57,$56,$55,$54,$53,$52,$51,$50,$4e,$4d,$4c,$4b,$4a
        !byte $49,$49,$48,$47,$46,$45,$44,$43,$42,$41,$40,$3f,$3e,$3e,$3d,$3c
        !byte $3b,$3a,$39,$39,$38,$37,$36,$35,$35,$34,$33,$33,$32,$31,$30,$30
        !byte $2f,$2f,$2e,$2d,$2d,$2c,$2b,$2b,$2a,$2a,$29,$29,$28,$28,$27,$27
        !byte $26,$26,$26,$25,$25,$24,$24,$24,$23,$23,$23,$22,$22,$22,$22,$21
        !byte $21,$21,$21,$21,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20

; song pointer tables (index = style 0..5)
;  0 dark  1 driving  2 dreamy  3 acid  4 techno-drive  5 techno-outro
;  styles 4/5 reuse the melody+bass of tracks 2/3 but with techno drums+filter.
SongBassLo: !byte <MUS_BASS, <Song1Bass, <Song2Bass, <Song3Bass, <Song2Bass, <Song3Bass
SongBassHi: !byte >MUS_BASS, >Song1Bass, >Song2Bass, >Song3Bass, >Song2Bass, >Song3Bass
SongArp0Lo: !byte <MUS_ARP0, <Song1Arp0, <Song2Arp0, <Song3Arp0, <Song2Arp0, <Song3Arp0
SongArp0Hi: !byte >MUS_ARP0, >Song1Arp0, >Song2Arp0, >Song3Arp0, >Song2Arp0, >Song3Arp0
SongArp1Lo: !byte <MUS_ARP1, <Song1Arp1, <Song2Arp1, <Song3Arp1, <Song2Arp1, <Song3Arp1
SongArp1Hi: !byte >MUS_ARP1, >Song1Arp1, >Song2Arp1, >Song3Arp1, >Song2Arp1, >Song3Arp1
SongArp2Lo: !byte <MUS_ARP2, <Song1Arp2, <Song2Arp2, <Song3Arp2, <Song2Arp2, <Song3Arp2
SongArp2Hi: !byte >MUS_ARP2, >Song1Arp2, >Song2Arp2, >Song3Arp2, >Song2Arp2, >Song3Arp2
SongDrumLo: !byte <MUS_DRUM, <Song1Drum, <Song2Drum, <Song3Drum, <TechnoDrum1, <TechnoDrum2
SongDrumHi: !byte >MUS_DRUM, >Song1Drum, >Song2Drum, >Song3Drum, >TechnoDrum1, >TechnoDrum2
SongFiltLo: !byte <MUS_FILT, <Song1Filt, <Song2Filt, <Song3Filt, <TechnoFilt1, <TechnoFilt2
SongFiltHi: !byte >MUS_FILT, >Song1Filt, >Song2Filt, >Song3Filt, >TechnoFilt1, >TechnoFilt2

; per-style instrument / mix (0 dark 1 driving 2 dreamy 3 acid 4 techno 5 outro)
StyleBassWaveTbl: !byte $21, $41, $11, $21, $41, $11
StyleArpWaveTbl:  !byte $41, $41, $11, $21, $41, $41
StyleSpeedTbl:    !byte 6,   4,   7,   5,   3,   6
StyleResTbl:      !byte $c1, $31, $20, $f1, $f1, $51   ; sharper, more resonant (techno-fantasy)
StyleXposeTbl:    !byte 0,   0,   3,   7,   5,   12     ; per-track key: root/3rd/5th/4th/octave
StyleVolTbl:      !byte $1f, $1f, $0f, $1f, $1f, $1f

; which style each of the 10 parts uses
;             title mat rng pls hyp vor xor wav tun star
PartStyleTbl: !byte 0,   3,  2,  1,  3,  1,  3,  2,  1,  3,  0

styleBassWave: !byte $21
styleArpWave:  !byte $41


; ============================================================================
;  Shared data tables
; ============================================================================
; Screen / colour row pointers
ScrRowLo: !for r,0,24 { !byte <(SCREEN + r*40) }
ScrRowHi: !for r,0,24 { !byte >(SCREEN + r*40) }
ColRowLo: !for r,0,24 { !byte <(COLOR + r*40) }
ColRowHi: !for r,0,24 { !byte >(COLOR + r*40) }

; Rings distance table: index = (((dx^2+dy^2)/8) & 15), centre (20,12)
DistBase:
!for r,0,24 {
  !for c,0,39 {
    !byte ( ( ((c-20)*(c-20) + (r-12)*(r-12)) / 8 ) & $0f )
  }
}
DistLo: !for r,0,24 { !byte <(DistBase + r*40) }
DistHi: !for r,0,24 { !byte >(DistBase + r*40) }

; Rings 16-colour chromatic palette (no greys/black/white)
PAL16:
        !byte $02,$08,$07,$0d,$05,$03,$0e,$06,$04,$0a,$08,$07,$0d,$05,$03,$06

; Sine (values 0..32) for starfield colour shimmer
; Full 256-byte sine (amplitude 0..31) so any 8-bit index is in-bounds.
Sin256:
        !byte $10,$10,$10,$11,$11,$11,$12,$12,$13,$13,$13,$14,$14,$14,$15,$15
        !byte $15,$16,$16,$16,$17,$17,$17,$18,$18,$18,$19,$19,$19,$1a,$1a,$1a
        !byte $1a,$1b,$1b,$1b,$1b,$1c,$1c,$1c,$1c,$1d,$1d,$1d,$1d,$1d,$1e,$1e
        !byte $1e,$1e,$1e,$1e,$1e,$1e,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f
        !byte $1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f,$1e,$1e,$1e,$1e,$1e
        !byte $1e,$1e,$1e,$1d,$1d,$1d,$1d,$1d,$1c,$1c,$1c,$1c,$1b,$1b,$1b,$1b
        !byte $1a,$1a,$1a,$1a,$19,$19,$19,$18,$18,$18,$17,$17,$17,$16,$16,$16
        !byte $15,$15,$15,$14,$14,$14,$13,$13,$13,$12,$12,$11,$11,$11,$10,$10
        !byte $10,$0f,$0f,$0e,$0e,$0e,$0d,$0d,$0c,$0c,$0c,$0b,$0b,$0b,$0a,$0a
        !byte $0a,$09,$09,$09,$08,$08,$08,$07,$07,$07,$06,$06,$06,$05,$05,$05
        !byte $05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$02,$01,$01
        !byte $01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01
        !byte $01,$01,$01,$02,$02,$02,$02,$02,$03,$03,$03,$03,$04,$04,$04,$04
        !byte $05,$05,$05,$05,$06,$06,$06,$07,$07,$07,$08,$08,$08,$09,$09,$09
        !byte $0a,$0a,$0a,$0b,$0b,$0b,$0c,$0c,$0c,$0d,$0d,$0e,$0e,$0e,$0f,$0f

; Sparkle/cycle palette (1..15)
ColorCycle:
        !byte $08,$08,$08,$09,$09,$09,$0a,$0a,$0a,$0b,$0b,$0b,$0c,$0c,$0c,$0d
        !byte $0d,$0d,$0e,$0e,$0e,$0f,$0f,$0f,$0e,$0e,$0e,$0d,$0d,$0d,$0c,$0c
        !byte $0c,$0b,$0b,$0b,$0a,$0a,$0a,$09,$09,$09,$08,$08,$08,$07,$07,$07
        !byte $06,$06,$06,$05,$05,$05,$04,$04,$04,$03,$03,$03,$02,$02,$02,$01
        !byte $01,$01,$02,$02,$02,$03,$03,$03,$04,$04,$04,$05,$05,$05,$06,$06
        !byte $06,$07,$07,$07,$08,$08,$08,$09,$09,$09,$0a,$0a,$0a,$0b,$0b,$0b
        !byte $0c,$0c,$0c,$0d,$0d,$0d,$0e,$0e,$0e,$0f,$0f,$0f,$0e,$0e,$0e,$0d
        !byte $0d,$0d,$0c,$0c,$0c,$0b,$0b,$0b,$0a,$0a,$0a,$09,$09,$09,$08,$08

; Scroller glow ramp (32, loops) - light blue -> white -> light blue
GlowRamp:
        !byte $0e,$0e,$0e,$03,$03,$0d,$0d,$01
        !byte $01,$01,$0f,$0f,$0f,$0f,$0f,$0f
        !byte $0f,$0f,$0f,$0f,$01,$01,$01,$0d
        !byte $0d,$03,$03,$0e,$0e,$0e,$0e,$0e

;  >>> imported-effect data tables <<<
; Extra effect tables
WireChars:   !byte $20,$2e,$2b,$2a,$5c,$2f,$2d,$a0
WireColors:  !byte $06,$0e,$03,$0d,$01,$07,$0f,$0c,$0b,$0c,$0f,$07,$01,$0d,$03,$0e
HeartWidth:  !byte 0,1,3,6,10,14,17,19,20,20,19,18,17,15,13,10,8,6,4,3,2,1,0,0,0
HeartChars:  !byte $20,$e2,$e3,$e4
HeartColors: !byte $09,$08,$07,$0f,$01,$0f,$07,$08,$09,$08,$07,$0f,$01,$0f,$07,$08
WaveHeight:  !byte 4,8,13,18,22,19,14,10,6,11,17,23,20,15,9,5
WaveChars:   !byte $20,$2e,$3a,$2b,$2a,$e2,$e3,$e5,$e3,$e2,$2a,$2b,$3a,$2e,$20,$a0
DeepChars:   !byte $20,$20,$2e,$2e,$2b,$2b,$2a,$2a,$e2,$e2,$e3,$e3,$e4,$e4,$e5,$a0

CubeChars:   !byte $2d,$5c,$2f,$2b,$e2,$e3,$e4,$e5,$2d,$5c,$2f,$2b,$e2,$e3,$e4,$e5
CubeColors:  !byte $06,$0e,$03,$0d,$01,$07,$0f,$07,$01,$0d,$03,$0e,$06,$0b,$0c,$0b
NeonChars:   !byte $20,$2e,$2b,$2a,$e2,$e3,$e4,$e5,$e4,$e3,$e2,$2a,$2b,$2e,$20,$a0
TrenchChars: !byte $20,$2e,$20,$2b,$20,$2a,$e3,$e5
TrenchColors: !byte $06,$0e,$03,$0d,$01,$07,$0f,$07,$01,$0d,$03,$0e,$06,$0b,$0c,$0b
HoloChars:   !byte $20,$2e,$2b,$2a,$e2,$e3,$e4,$e5,$e4,$e3,$e2,$2a,$2b,$2e,$20,$a0
HoloColors:  !byte $06,$0b,$0c,$0f,$01,$07,$0d,$03,$0e,$06,$00,$06,$0e,$03,$01,$07
GridChars:   !byte $2d,$2b,$5c,$2f,$e2,$e3,$e4,$e5
GridColors:  !byte $06,$0e,$03,$0d,$01,$07,$0f,$07,$01,$0d,$03,$0e,$06,$0b,$0c,$0b
TunnelZoomChars:  !byte $20,$20,$2e,$2e,$3a,$3a,$2b,$2b,$2a,$2a,$e2,$e3,$e4,$e5,$a0,$a0
TunnelZoomColors: !byte $00,$06,$06,$0e,$0e,$03,$03,$0d,$0d,$01,$07,$0f,$07,$01,$0d,$03
OrbitalMask:  !byte 1,0,0,1,0,1,0,0,1,0,0,1,0,1,0,0
OrbitalChars: !byte $2e,$20,$20,$2b,$20,$2a,$20,$20,$e2,$20,$20,$e3,$20,$e4,$20,$20
OrbitalColors: !byte $06,$00,$00,$0e,$00,$03,$00,$00,$0d,$00,$00,$01,$00,$07,$00,$00

; Title background pulse (8 dark steps; keeps title text readable)
TitleBgPulse:
        !byte $00,$00,$06,$06,$0b,$06,$06,$00


; ============================================================================
;  New-effect data tables
; ============================================================================
NfxCoolPalette:      !byte $06,$0e,$03,$0d,$01,$07,$0f,$07,$01,$0d,$03,$0e,$06,$0b,$0c,$0b
NfxWireRows:         !byte 5,6,7,8,10,12,14,16,18,19,20,21
NfxWireChars:        !byte $2d,$2d,$5c,$2f,$2b,$2a,$2a,$2b,$2f,$5c,$2d,$2d,$2b,$2a,$2d,$5c,$2f,$2b,$2a,$2d,$5c,$2f,$2b,$2a
NfxWireColors:       !byte $06,$0e,$03,$0d,$01,$07,$0f,$07,$01,$0d,$03,$0e
NfxCorridorChars:    !byte $20,$20,$2e,$2e,$3a,$3a,$2b,$2b,$2a,$2a,$e2,$e3,$e4,$e5,$a0,$a0
NfxCorridorColors:   !byte $00,$06,$06,$0e,$0e,$03,$03,$0d,$0d,$01,$07,$0f,$07,$01,$0d,$03
NfxCorridorBg:       !byte $00,$00,$06,$06,$0b,$06,$00,$00,$00,$00,$06,$0b,$06,$00,$00,$00
NfxCorridorBorder:   !byte $06,$0e,$03,$0d,$01,$07,$0f,$07,$01,$0d,$03,$0e,$06,$0b,$0c,$0b
NfxColWarp:          !byte 0,1,1,2,2,3,4,5,6,7,8,9,10,11,12,11,10,9,8,7,6,5,4,3,2,2,1,1,0,1,2,3,4,3,2,1,0,1,2,3
NfxGoldBorder:       !byte $08,$09,$07,$0f,$01,$0f,$07,$08
NfxGoldPalette:      !byte $09,$08,$07,$0f,$01,$0f,$07,$08,$09,$08,$07,$0f,$01,$0f,$07,$08
NfxGoldWallChars:    !byte $2f,$5c,$2d,$3d,$2b,$2a,$2f,$5c
NfxTrenchLeft:       !byte 1,2,3,4,5,6,7,8,9,10,11,12,12,11,10,9,8,7,6,5,4,3,2,1
NfxTrenchRight:      !byte 38,37,36,35,34,33,32,31,30,29,28,27,27,28,29,30,31,32,33,34,35,36,37,38
NfxCubePalette:      !byte $06,$0e,$03,$0d,$01,$07,$0f,$07,$01,$0d,$03,$0e,$06,$0b,$0c,$0b
NfxCubeRow:          !byte 6,7,8,9,10,11,13,14,15,16,17,18,8,10,14,16
NfxCubePhase:        !byte 0,3,6,9,12,15,18,21,24,27,30,1,4,10,16,22

; ============================================================================
;  Text  (screen codes via !scr, $ff-terminated)
; ============================================================================
; NOTE: ACME !scr maps lowercase a-z -> screen codes $01-$1a (the letter
; glyphs in the uppercase ROM font).  Uppercase a-z would map to $41-$5a =
; graphics, so all on-screen text is written here in lowercase.
TitleA: !scr "u83r new effects" : !byte $ff
TitleB: !scr "source swap" : !byte $ff
TitleC: !scr "4 new engines" : !byte $ff
TitleD: !scr "wire cube corridor trench" : !byte $ff

; Per-part title cards (indexed by nextPart)
CardName0: !scr "u83r rul3z" : !byte $ff
CardSub0:  !scr "the end - and again" : !byte $ff
CardName1: !scr "digital rain" : !byte $ff
CardSub1:  !scr "part one" : !byte $ff
CardName2: !scr "horizon warp" : !byte $ff
CardSub2:  !scr "part two" : !byte $ff
CardName3: !scr "plasma storm" : !byte $ff
CardSub3:  !scr "part three" : !byte $ff
CardName4: !scr "hyperspace" : !byte $ff
CardSub4:  !scr "part four" : !byte $ff
CardName5: !scr "vortex" : !byte $ff
CardSub5:  !scr "part five" : !byte $ff
CardName6: !scr "xor moire" : !byte $ff
CardSub6:  !scr "part six" : !byte $ff
CardName7: !scr "waves" : !byte $ff
CardSub7:  !scr "part seven" : !byte $ff
CardName8: !scr "perspective tunnel" : !byte $ff
CardSub8:  !scr "part eight" : !byte $ff
CardName9: !scr "fire" : !byte $ff
CardSub9:  !scr "part nine" : !byte $ff
CardName10: !scr "sine starfield" : !byte $ff
CardSub10:  !scr "part ten" : !byte $ff
CardName11: !scr "text wireframe" : !byte $ff
CardSub11:  !scr "part eleven" : !byte $ff
CardName12: !scr "golden heart" : !byte $ff
CardSub12:  !scr "part twelve" : !byte $ff
CardName13: !scr "loader waves" : !byte $ff
CardSub13:  !scr "part thirteen" : !byte $ff
CardName14: !scr "deep tunnel" : !byte $ff
CardSub14:  !scr "part fourteen" : !byte $ff
CardName15: !scr "cube engine" : !byte $ff
CardSub15:  !scr "part fifteen" : !byte $ff
CardName16: !scr "neon rings" : !byte $ff
CardSub16:  !scr "part sixteen" : !byte $ff
CardName17: !scr "star trench" : !byte $ff
CardSub17:  !scr "part seventeen" : !byte $ff
CardName18: !scr "holo ripple" : !byte $ff
CardSub18:  !scr "part eighteen" : !byte $ff
CardName19: !scr "perspective grid" : !byte $ff
CardSub19:  !scr "part nineteen" : !byte $ff
CardName20: !scr "tunnel zoom" : !byte $ff
CardSub20:  !scr "part twenty" : !byte $ff
CardName21: !scr "orbital field" : !byte $ff
CardSub21:  !scr "finale - irq scroll" : !byte $ff


; New active-effect cards
NfxCardName0: !scr "wire cube clean" : !byte $ff
NfxCardSub0:  !scr "uploaded wireframe source" : !byte $ff
NfxCardName1: !scr "infinity corridor" : !byte $ff
NfxCardSub1:  !scr "pure raster tunnel" : !byte $ff
NfxCardName2: !scr "gold trench" : !byte $ff
NfxCardSub2:  !scr "gold perspective lanes" : !byte $ff
NfxCardName3: !scr "cube v3 rotor" : !byte $ff
NfxCardSub3:  !scr "final rotating cube" : !byte $ff
NfxWireTitle:     !scr "wire cube clean" : !byte $ff
NfxInfinityTitle: !scr "infinity corridor" : !byte $ff
NfxGoldTitle:     !scr "gold trench" : !byte $ff
NfxCubeTitle:     !scr "cube v3 rotor" : !byte $ff
CardNameLo: !byte <NfxCardName0,<NfxCardName1,<NfxCardName2,<NfxCardName3
CardNameHi: !byte >NfxCardName0,>NfxCardName1,>NfxCardName2,>NfxCardName3
CardSubLo:  !byte <NfxCardSub0,<NfxCardSub1,<NfxCardSub2,<NfxCardSub3
CardSubHi:  !byte >NfxCardSub0,>NfxCardSub1,>NfxCardSub2,>NfxCardSub3

ScrollMsg:
!scr "   u83r rul3z   a techno fantasy on one c64   ....   "
!scr "six sid tracks - melodic builds and pounding techno - everything pulses on the beat   ....   "
!scr "a real 3d cube spins and the star trench warps past in time with the kick   ....   "
!scr "feel the tension - ride the build - brace for the drop   ....   "
!scr "space pauses - plus and minus change speed   ....   "
!scr "greets to the crew  -  "
!scr "                " : !byte $ff : !scr "   stian   "
!scr "                " : !byte $ff : !scr "   runar   "
!scr "                " : !byte $ff : !scr "   svein   "
!scr "                " : !byte $ff : !scr "   magnus   "
!scr "                " : !byte $ff : !scr "   havard   "
!scr "                " : !byte $ff : !scr "   h   "
!scr "   respect to all who keep the scene alive   ....   stay cyber   -   "
!scr "                                        "
ScrollMsgEnd:
ScrollCore = ScrollMsgEnd - ScrollMsg - 40   ; (16-bit now; no 255 cap)

; ============================================================================
;  size guard
; ============================================================================
!if * > $c000 {
        !error "megademo overruns $c000! end = ", *
}
!warn "MEGADEMO end = ", *, "  (", * - $0801, " bytes)"
