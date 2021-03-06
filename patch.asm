; CONFIG: ------------------------------------------------------------------------------------------

SEGA_32X = 0                                    ; Create 32X patch?

; MEMORY: ------------------------------------------------------------------------------------------

; Mega CD MMIO addresses used for communicating with msu-md driver on the mega cd (mode 1)
MSU_COMM_CMD        equ $a12010                 ; Comm command 0 (high byte)
MSU_COMM_ARG        equ $a12011                 ; Comm command 0 (low byte)
MSU_COMM_CMD_CK     equ $a1201f                 ; Comm command 7 (low byte)
MSU_COMM_STATUS     equ $a12020                 ; Comm status 0 (0-ready, 1-init, 2-cmd busy)

; 32X registers (68000 address space)
REG_32X_BANK        equ $a15104                 ; Controls 1MB ROM bank visible in $900000 - $9FFFFF range on the mega drive 68000

; 32X memory addresses (68000 address space)
ROM_BASE_32X        equ $880000
ROM_BANK_BASE_32X   equ $900000

; Where to put the code
ROM_END             equ $3facd0                 ; High to be compatible with all supported versions (Needs 4MB padded input ROMS for all versions)

; Krisalis sound driver variables
    if SEGA_32X
KRISALIS_VAR_BASE   equ $ffffb4f0
    else
KRISALIS_VAR_BASE   equ $ffffb172
    endif

; MSU COMMANDS: ------------------------------------------------------------------------------------------

MSU_PLAY            equ $1100                   ; PLAY      decimal no. of track (1-99) playback will be stopped in the end of track
MSU_PLAY_LOOP       equ $1200                   ; PLAY LOOP decimal no. of track (1-99) playback will restart the track when end is reached
MSU_PAUSE           equ $1300                   ; PAUSE     vol fading time. 1/75 of sec. (75 equal to 1 sec) instant stop if 0 pause playback
MSU_RESUME          equ $1400                   ; RESUME    none. resume playback
MSU_VOL             equ $1500                   ; VOL       volume 0-255. set cdda volume
MSU_NOSEEK          equ $1600                   ; NOSEEK    0-on(default state), 1-off(no seek delays)  seek time emulation switch
MSU_PLAYOF          equ $1a00                   ; PLAYOF    #1 = decimal no. of track (1-99) #2 = offset in sectors from the start of the track to apply when looping play cdda track and loop from specified sector offset

; MACROS: ------------------------------------------------------------------------------------------

    macro MSU_WAIT
.\@
        tst.b   MSU_COMM_STATUS
        bne.s   .\@
    endm

    macro MSU_COMMAND cmd, param
        MSU_WAIT
        move.w  #(\1|\2),MSU_COMM_CMD           ; Send msu cmd
        addq.b  #1,MSU_COMM_CMD_CK              ; Increment command clock
    endm

    macro JMP_32X routine
        jmp     \1+ROM_BASE_32X
    endm

    macro JSR_32X_BANKED subroutine
        move.w  REG_32X_BANK,-(sp)
        move.w  #3,REG_32X_BANK
        jsr     ((\1-$300000)+ROM_BANK_BASE_32X)
        move.w  (sp)+,REG_32X_BANK
    endm

; 32X OVERRIDES : ------------------------------------------------------------------------------------------
    if SEGA_32X

        org     $800                            ; $880800
        jmp     ENTRY_POINT(pc)

        org     $804
GameAddrLow

        ; Use the 32x "new" 68000 exception jumb table reserved space to place the redirect code in non bankable ROM (72 bytes available)
        ; Redirect code must be in non bankable ROM as JSR_32X_BANKED could change the current bank and so mess up the current execution if called directly from the banked ROM area
        org     $242                            ; $880242
ENTRY_POINT
        JSR_32X_BANKED audio_init

        ; Jump to the original starting code
        move.w  #$90,d0
        swap    d0
        move.w  GameAddrLow(pc),d0
        movea.l d0,a0
        jmp     (a0)                            ; 38 bytes

play_music_track_32x
        JSR_32X_BANKED play_music_track
        rts                                     ; 26 bytes
                                                ; 64 bytes total

        ; Original play_music_track sub routine (30 bytes available)
        org     $4013a                          ; $8c013a/$94013a
        JMP_32X play_music_track_32x            ; 6 bytes total

        org     ROM_END

; MEGA DRIVE OVERRIDES : ------------------------------------------------------------------------------------------
    else

        ; M68000 Reset vector
        org     $4
        dc.l    ENTRY_POINT                     ; Custom entry point for redirecting

        org     $200                            ; Original ENTRY POINT
Game

        ; Original play_music_track sub routine
        org     $4013a
        jmp     play_music_track

        ; Mortal Kombat 2 Unlimited specific patches (Have no effect on base game)
        ; Remap intro song to ending track
        org     $3ef5f0
        dc.w    $0092                           ; WM4X-6AHT

        ; Remap bio screen to ending track
        org     $3cdbb0
        dc.w    $0092                           ; WMPX-2AFT

        org     ROM_END
ENTRY_POINT
        bsr     audio_init
        jmp     Game

    endif

; MSU-MD Init: -------------------------------------------------------------------------------------

        align   2
audio_init
        bsr     msu_driver_init
        tst.b   d0                              ; if 1: no CD Hardware found
.audio_init_fail
        bne     .audio_init_fail                ; Loop forever

        MSU_COMMAND MSU_NOSEEK, 1
        MSU_COMMAND MSU_VOL,    255
        rts

; Sound: -------------------------------------------------------------------------------------

        align   2
play_music_track
        tst.b   d0                              ; d0 = track number
        bne     .play
            ; 0 = Stop
            MSU_COMMAND MSU_PAUSE, 0
        bra     .original_code_4013a
.play
        ; Save used registers to prevent graphics corruption at the main menu screen in MKII Unlimited. (Only a0 is really required but save all to be on the save side)
        movem.l d1-d2/a0,-(sp)

        lea     AUDIO_TBL(pc),a0
        moveq   #((AUDIO_TBL_END-AUDIO_TBL)/2)-1,d1
.find_track_loop
            move.w  d1,d2
            add.w   d2,d2
            move.w  (a0,d2),d2
            cmp.b   d2,d0
            bne     .next_track

                ; Set cd track number
                move.b  d1,d2
                addq.b  #1,d2

                ; Send play command
                MSU_WAIT
                move.w  d2,MSU_COMM_CMD
                addq.b  #1,MSU_COMM_CMD_CK

                ; Run stop command for original driver
                moveq   #0,d0
                bra     .play_done
.next_track
        dbra    d1,.find_track_loop

        ; If no matching cd track found run original track

        ; First stop any still playing cd track
        MSU_COMMAND MSU_PAUSE, 0

.play_done
        ; Restore used registers
        movem.l  (sp)+,d1-d2/a0

.original_code_4013a
        addq.w  #1,d0
        move.w  d0,(KRISALIS_VAR_BASE+$04).w
        st      (KRISALIS_VAR_BASE+$96).w
        sf      (KRISALIS_VAR_BASE+$68).w
        clr.b   (KRISALIS_VAR_BASE+$90).w
        clr.w   (KRISALIS_VAR_BASE+$00).w
        clr.w   (KRISALIS_VAR_BASE+$02).w
        sf      (KRISALIS_VAR_BASE+$24).w
        rts

; TABLES: ------------------------------------------------------------------------------------------

        align 2
AUDIO_TBL
        ;       #Command|id                     #Track Name
        dc.w    MSU_PLAY|$31                    ; 01 - Title Theme
        dc.w    MSU_PLAY_LOOP|$4f               ; 02 - Character Select
        dc.w    MSU_PLAY|$57                    ; 03 - Selected
        dc.w    MSU_PLAY_LOOP|$69               ; 04 - Your Destiny
        dc.w    MSU_PLAY_LOOP|$38               ; 05 - The Dead Pool
        dc.w    MSU_PLAY_LOOP|$40               ; 06 - The Dead Pool ~ Critical
        dc.w    MSU_PLAY|$41                    ; 07 - The Dead Pool ~ Over
        dc.w    MSU_PLAY_LOOP|$88               ; 08 - The Tomb - Special Portal
        dc.w    MSU_PLAY_LOOP|$90               ; 09 - The Tomb ~ Critical
        dc.w    MSU_PLAY|$91                    ; 10 - The Tomb ~ Over
        dc.w    MSU_PLAY_LOOP|$02               ; 11 - Wasteland - The Pit II - Kahn's Arena
        dc.w    MSU_PLAY_LOOP|$2e               ; 12 - Wasteland ~ Critical
        dc.w    MSU_PLAY|$0d                    ; 13 - Wasteland ~ Over
        dc.w    MSU_PLAY_LOOP|$42               ; 14 - Cloud Room - Portal
        dc.w    MSU_PLAY_LOOP|$4d               ; 15 - Cloud Room ~ Critical
        dc.w    MSU_PLAY|$4e                    ; 16 - Cloud Room ~ Over
        dc.w    MSU_PLAY_LOOP|$0e               ; 17 - Living Forest
        dc.w    MSU_PLAY_LOOP|$2f               ; 18 - Living Forest ~ Critical
        dc.w    MSU_PLAY|$20                    ; 19 - Living Forest ~ Over
        dc.w    MSU_PLAY_LOOP|$21               ; 20 - Armoury
        dc.w    MSU_PLAY_LOOP|$30               ; 21 - Armoury ~ Critical
        dc.w    MSU_PLAY|$2d                    ; 22 - Armoury ~ Over
        dc.w    MSU_PLAY|$73                    ; 23 - Finish Him!
        dc.w    MSU_PLAY|$52                    ; 24 - Fatality!
        dc.w    MSU_PLAY|$53                    ; 25 - Babality!
        dc.w    MSU_PLAY|$58                    ; 26 - Friendship!
        dc.w    MSU_PLAY|$55                    ; 27 - Liu Kang's Friendship Dance
        dc.w    MSU_PLAY|$72                    ; 28 - Shao Kahn Defeated
        dc.w    MSU_PLAY_LOOP|$92               ; 29 - Ending Theme
        ; Mortal Kombat tracks included in Mortal Kombat II Unlimited (Hack)
        dc.w    MSU_PLAY_LOOP|$96               ; 30 - Warrior's Shrine
        dc.w    MSU_PLAY|$e9                    ; 31 - Warrior's Shrine Victory
        dc.w    MSU_PLAY_LOOP|$b3               ; 32 - The Pit
        dc.w    MSU_PLAY|$ea                    ; 33 - The Pit Victory
        dc.w    MSU_PLAY_LOOP|$cf               ; 34 - Hall
        dc.w    MSU_PLAY|$e7                    ; 35 - Hall Victory
        dc.w    MSU_PLAY_LOOP|$c1               ; 36 - Goro's Lair
        dc.w    MSU_PLAY|$eb                    ; 37 - Goro's Lair Victory
        dc.w    MSU_PLAY_LOOP|$a8               ; 38 - Entrance
        dc.w    MSU_PLAY|$e8                    ; 39 - Entrance Victory
AUDIO_TBL_END

; MSU-MD DRIVER: -----------------------------------------------------------------------------------

        align 2
msu_driver_init
        incbin  "msu-drv.bin"
