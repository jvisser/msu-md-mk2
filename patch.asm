; Mega CD MMIO addresses (mode 1)
MCD_CMD             equ $a12010                 ; Comm command 0
MCD_ARG             equ $a12011                 ; Comm command 1
MCD_CMD_CK          equ $a1201f                 ; MSU only!?
MCD_STAT            equ $a12020                 ; Comm status 0 (0-ready, 1-init, 2-cmd busy)

; MCD_CMD commands (lower byte = param)
CMD_PLAY            equ $1100                   ; PLAY      decimal no. of track (1-99) playback will be stopped in the end of track
CMD_PLAY_LOOP       equ $1200                   ; PLAY LOOP decimal no. of track (1-99) playback will restart the track when end is reached
CMD_PAUSE           equ $1300                   ; PAUSE     vol fading time. 1/75 of sec. (75 equal to 1 sec) instant stop if 0 pause playback
CMD_RESUME          equ $1400                   ; RESUME    none. resume playback
CMD_VOL             equ $1500                   ; VOL       volume 0-255. set cdda volume
CMD_NOSEEK          equ $1600                   ; NOSEEK    0-on(default state), 1-off(no seek delays)  seek time emulation switch
CMD_PLAYOF          equ $1a00                   ; PLAYOF    #1 = decimal no. of track (1-99) #2 = offset in sectors from the start of the track to apply when looping   play cdda track and loop from specified sector offset

; 32X registers
REG_32X_BANK        equ $a15104                 ; Controls ROM bank visible in $900000 - $9FFFFF

; 32X memory addresses
ROM_BASE_32X        equ $880000
ROM_BANK_BASE_32X   equ $900000

; Where to put the code
ROM_END             equ $3facd0                 ; High to be compatible with all supported versions (Needs 4MB padded input ROMS for all versions)

; CONFIG: ------------------------------------------------------------------------------------------

SEGA_32X = 0                                    ; Create 32X patch?
SEGA_32X_PAL = 0                                ; Patch PAL version, NTSC otherwise

; MACROS: ------------------------------------------------------------------------------------------

    macro MCD_WAIT
.\@
        tst.b   MCD_STAT
        bne.s   .\@
    endm

    macro MCD_COMMAND cmd, param
        MCD_WAIT
        move.w  #(\1|\2),MCD_CMD                ; Send msu cmd
        addq.b  #1,MCD_CMD_CK                   ; Increment command clock
    endm

    macro JMP_32X routine
        jmp     \1+ROM_BASE_32X
    endm

    macro CALL_32X_BANKED routine
        move.w  REG_32X_BANK,-(sp)
        move.w  #3,REG_32X_BANK
        jsr     ((\1-$300000)+ROM_BANK_BASE_32X)
        move.w  (sp)+,REG_32X_BANK
    endm

    if SEGA_32X
; 32X OVERRIDES : ------------------------------------------------------------------------------------------

        org     $800                            ; $880800
ENTRY_POINT
        JMP_32X audio_init_32x

        ; Use the reserved/unused 68000 vector space to place code in non bankable ROM
        org     $000000c0
audio_init_32x
        CALL_32X_BANKED audio_init

        ; Jump to the original starting code
    if SEGA_32X_PAL
        jmp $908794     ; eu
    else
        jmp $90878c     ; us/jp
    endif

play_music_track_32x
        CALL_32X_BANKED play_music_track
        rts

        ; Original play_music_track sub routine
        org     $4013a
        JMP_32X play_music_track_32x

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

        org     ROM_END
ENTRY_POINT
        bsr     audio_init
        jmp     Game

    endif

; MSU-MD Init: -------------------------------------------------------------------------------------

        align   2
audio_init
        jsr     msu_driver_init
        tst.b   d0                              ; if 1: no CD Hardware found
.audio_init_fail
        bne     .audio_init_fail                ; Loop forever

        MCD_COMMAND CMD_NOSEEK, 1
        MCD_COMMAND CMD_VOL,    255
        rts

; Sound: -------------------------------------------------------------------------------------

        align   2
play_music_track
        tst.b   d0                              ; d0 = track number
        bne     .play
            ; 0 = Stop
            MCD_COMMAND CMD_PAUSE, 0
            bra     .original_code_4013a
.play
        ; Save used registers to prevent graphics corruption at the main menu screen in MKII Unlimited. (Only a0 is really required but save all to be on the save side)
        movem.l d1-d2/a0,-(sp)

        lea     AUDIO_TBL,a0
        moveq   #((AUDIO_TBL_END-AUDIO_TBL)/2)-1,d1
.find_track_loop
            move.w  d1,d2
            add.w   d2,d2
            move.w  (a0,d2),d2
            cmp.b   d2,d0
            bne     .next_track

                ; Track found: Determine command type
                lsr.w   #8,d2
                bclr    #7,d2
                bne     .loop_play
                    ; Single repetition
                    ori.w   #CMD_PLAY,d2
                bra     .cmd_type_select_done
.loop_play
                    ; Play in infinite loop
                    ori.w   #CMD_PLAY_LOOP,d2
.cmd_type_select_done

                ; Send play command
                MCD_WAIT
                move.w  d2,MCD_CMD
                addq.b  #1,MCD_CMD_CK

                ; Run stop command for original driver
                moveq   #0,d0
                bra     .play_done
.next_track
        dbra    d1,.find_track_loop

        ; If no matching cd track found run original track

        ; First stop any still playing cd track
        MCD_COMMAND CMD_PAUSE, 0

.play_done
        ; Restore used registers. Required for MKII Unlimited.
        movem.l  (sp)+,d1-d2/a0

.original_code_4013a
        addq.w  #1,d0
    if SEGA_32X
        move.w  d0,$ffffb4f4.w
        st      $ffffb586.w
        sf      $ffffb558.w
        clr.b   $ffffb580.w
        clr.w   $ffffb4f0.w
        clr.w   $ffffb4f2.w
        sf      $ffffb514.w
    else
        move.w  d0,$ffffb176.w
        st      $ffffb208.w
        sf      $ffffb1da.w
        clr.b   $ffffb202.w
        clr.w   $ffffb172.w
        clr.w   $ffffb174.w
        sf      $ffffb196.w
    endif
        rts

; TABLES: ------------------------------------------------------------------------------------------

AUDIO_TBL       ;%rtttttttcccccccc (r=repeat, t=cd track number, c=original music id)
                                                ; #Track Name
        dc.w    $0131                           ; 01 - Title Theme
        dc.w    $824f                           ; 02 - Character Select
        dc.w    $0357                           ; 03 - Selected
        dc.w    $8469                           ; 04 - Your Destiny
        dc.w    $8538                           ; 05 - The Dead Pool
        dc.w    $8640                           ; 06 - The Dead Pool ~ Critical
        dc.w    $0741                           ; 07 - The Dead Pool ~ Over
        dc.w    $8888                           ; 08 - The Tomb - Special Portal
        dc.w    $8990                           ; 09 - The Tomb ~ Critical
        dc.w    $0a91                           ; 10 - The Tomb ~ Over
        dc.w    $8b02                           ; 11 - Wasteland - The Pit II - Kahn's Arena
        dc.w    $8c2e                           ; 12 - Wasteland ~ Critical
        dc.w    $0d0d                           ; 13 - Wasteland ~ Over
        dc.w    $8e42                           ; 14 - Cloud Room - Portal
        dc.w    $8f4d                           ; 15 - Cloud Room ~ Critical
        dc.w    $104e                           ; 16 - Cloud Room ~ Over
        dc.w    $910e                           ; 17 - Living Forest
        dc.w    $922f                           ; 18 - Living Forest ~ Critical
        dc.w    $1320                           ; 19 - Living Forest ~ Over
        dc.w    $9421                           ; 20 - Armoury
        dc.w    $9530                           ; 21 - Armoury ~ Critical
        dc.w    $162d                           ; 22 - Armoury ~ Over
        dc.w    $1773                           ; 23 - Finish Him!
        dc.w    $1852                           ; 24 - Fatality!
        dc.w    $1953                           ; 25 - Babality!
        dc.w    $1a58                           ; 26 - Friendship!
        dc.w    $1b55                           ; 27 - Liu Kang's Friendship Dance
        dc.w    $1c72                           ; 28 - Shao Kahn Defeated
        dc.w    $9d92                           ; 29 - Ending Theme
        ; Mortal Kombat tracks included in Mortal Kombat II Unlimited (Hack)
        dc.w    $9e96                           ; 30 - Warrior's Shrine
        dc.w    $1fe9                           ; 31 - Warrior's Shrine Victory
        dc.w    $a0b3                           ; 32 - The Pit
        dc.w    $21ea                           ; 33 - The Pit Victory
        dc.w    $a2cf                           ; 34 - Hall
        dc.w    $23e7                           ; 35 - Hall Victory
        dc.w    $a4c1                           ; 36 - Goro's Lair
        dc.w    $25eb                           ; 37 - Goro's Lair Victory
        dc.w    $a6a8                           ; 38 - Entrance
        dc.w    $27e8                           ; 39 - Entrance Victory
AUDIO_TBL_END

; MSU-MD DRIVER: -----------------------------------------------------------------------------------

        align 2
msu_driver_init
        incbin  "msu-drv.bin"
