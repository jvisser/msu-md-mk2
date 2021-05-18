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

; LABLES: ------------------------------------------------------------------------------------------

        org     $200                            ; Original ENTRY POINT
Game

; OVERWRITES: --------------------------------------------------------------------------------------

        ; M68000 Reset vector
        org $4
        dc.l    ENTRY_POINT                     ; Custom entry point for redirecting

        ; Sega ROM Header
        org     $100
        dc.b    'SEGA MEGASD     '              ; Make it compatible with MegaSD and GenesisPlusGX

        ; Original play_music_track sub routine
        org     $4013a                          ; Sound Hijack
        jmp     play_music_track

; ORIGINAL ROM SPACE: ------------------------------------------------------------------------------------

    org     $2ffebc

; TABLES: ------------------------------------------------------------------------------------------

AUDIO_TBL       ;trackId;cmd                    ; #Track Name
        dc.w    $0031                           ; 01 - Title Theme
        dc.w    $014f                           ; 02 - Character Select
        dc.w    $0257                           ; 03 - Selected
        dc.w    $0369                           ; 04 - Your Destiny
        dc.w    $0438                           ; 05 - The Dead Pool
        dc.w    $0540                           ; 06 - The Dead Pool ~ Critical
        dc.w    $0641                           ; 07 - The Dead Pool ~ Over
        dc.w    $0788                           ; 08 - The Tomb - Special Portal
        dc.w    $0890                           ; 09 - The Tomb ~ Critical
        dc.w    $0991                           ; 10 - The Tomb ~ Over
        dc.w    $0a02                           ; 11 - Wasteland - The Pit II - Kahn's Arena
        dc.w    $0b2e                           ; 12 - Wasteland ~ Critical
        dc.w    $0c0d                           ; 13 - Wasteland ~ Over
        dc.w    $0d42                           ; 14 - Cloud Room - Portal
        dc.w    $0e4d                           ; 15 - Cloud Room ~ Critical
        dc.w    $0f4e                           ; 16 - Cloud Room ~ Over
        dc.w    $100e                           ; 17 - Living Forest
        dc.w    $112f                           ; 18 - Living Forest ~ Critical
        dc.w    $1220                           ; 19 - Living Forest ~ Over
        dc.w    $1321                           ; 20 - Armoury
        dc.w    $1430                           ; 21 - Armoury ~ Critical
        dc.w    $152d                           ; 22 - Armoury ~ Over
        dc.w    $1673                           ; 23 - Finish Him!
        dc.w    $1752                           ; 24 - Fatality!
        dc.w    $1853                           ; 25 - Babality!
        dc.w    $1958                           ; 26 - Friendship!
        dc.w    $1a55                           ; 27 - Liu Kang's Friendship Dance
        dc.w    $1b72                           ; 28 - Shao Kahn Defeated
        dc.w    $1c92                           ; 29 - Ending Theme

TOTAL_TRACKS equ 29

; ENTRY POINT: -------------------------------------------------------------------------------------

        align   2
ENTRY_POINT
        bsr     audio_init
        jmp     Game

; MSU-MD Init: -------------------------------------------------------------------------------------

        align   2
audio_init
        jsr     msu_driver_init
        tst.b   d0                              ; if 1: no CD Hardware found
audio_init_fail
        bne     audio_init_fail                 ; Loop forever

        MCD_COMMAND CMD_NOSEEK, 1
        MCD_COMMAND CMD_VOL,    255
        rts

; Sound: -------------------------------------------------------------------------------------

        align   2
play_music_track
        tst.b   d0                              ; d0 = track number
        bne     play
            ; 0 = Stop
            MCD_COMMAND CMD_PAUSE, 0
            bra     orginal_code_4013a
play
        lea     AUDIO_TBL,a0
        moveq   #TOTAL_TRACKS-1,d1
find_track_loop
            move.w  d1,d2
            add.w   d2,d2
            move.w  (a0,d2),d2
            cmp.b   d2,d0
            bne     next_track

                ; Track found: Play
                lsr.w   #8,d2
                ori.w   #CMD_PLAY_LOOP,d2
                MCD_WAIT
                move.w  d2,MCD_CMD
                addq.b  #1,MCD_CMD_CK

                ; Run stop command for original driver
                moveq   #0,d0
                bra     orginal_code_4013a
next_track
        dbra    d1,find_track_loop

            ; If no track found run original track (unused tracks)

orginal_code_4013a
        addq.w  #1,d0
        move.w  d0,$ffffb176.w
        st      $ffffb208.w
        sf      $ffffb1da.w
        clr.b   $ffffb202.w
        clr.w   $ffffb172.w
        clr.w   $ffffb174.w
        sf      $ffffb196.w
        rts

; MSU-MD DRIVER: -----------------------------------------------------------------------------------

        align 2
msu_driver_init
        incbin  "msu-drv.bin"
