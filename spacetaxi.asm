#import "build/charpad/metadata.asm"

.label SCREEN = $0400
.label COLOUR_RAM = $D800


*=$0801 "Basic Upstart"
BasicUpstart(start) // Basic start routine

// Main program
*=$080d "Program"

start: {
    jsr initIO
    jsr initScreen
    jsr drawTitleScreen
    outerMainLoop:
        jsr readJoy
        lda joyState
        and #%00010000
        bne !+
            jsr startGame
        !:
    jmp outerMainLoop
}

startGame: {
    jsr initGame
    jsr initLevel
    mainLoop:
        jmp mainLoop
    gameOver:
    rts
}

// game initialization

initIO: {
    // set IO pins for joy 2 to input
    lda $DC02
    and #%11100000
    sta $DC02
    rts
}

initScreen: {
    // init colours
    lda #backgroundColour0
    sta $D020
    sta $D021
    lda #backgroundColour1
    sta $D022
    lda #backgroundColour2
    sta $D023

    // init sprite colours
    lda #12
    sta $D025
    lda #11
    sta $D026

    // set charset mem bank to the last one (we'll use default screen location)
    lda $D018
    ora #%00001110
    sta $D018

    // set screen mode to multicolor
    lda $D016
    ora #%00010000
    sta $D016

    rts
}

initSprites: {
    // init player sprite
    lda #15
    sta $D027
    lda $D01C
    ora #%00000001
    sta $D01C       // sprite 0 multicolor
    lda #(256-3)
    sta SCREEN + 1024 - 8
    lda $D015
    ora #%00000001
    sta $D015       // show sprite
    rts
}

initGame: {
    lda #1
    sta levelCounter
    lda #3
    sta livesCounter
    jsr initSprites
    rts
}

initLevel: {
    jsr drawDashboard
    lda levelCounter
    cmp #1
    bne !+
        lda #150
        sta $D000
        lda #100
        sta $D001
        jsr initLevel1
        jmp continue
    !:
    cmp #2
    bne !+
        jsr initLevel2
        jmp continue
    !:
    continue:
        jsr copyLevel

    // set up player
    lda #0
    sta verticalSpeed
    sta horizontalSpeed
    rts
}

initLevel1: {
    lda #<level1
    ldx #>level1
    rts
}

initLevel2: {
    lda #<level2
    ldx #>level2
    rts
}

// ==== IO handling ====
readJoy: {
    lda $DC00
    and #%00011111
    sta joyState
    rts
}

// ==== screen drawing routines ====

/*
 * IN:
 *   A - source address lsb
 *   X - source address hsb
 * DESTROYS: A, X, Y
 */
.macro copyScreenBlock(width, screenTarget, colorSource, colorTarget) {
    sta sourceAddress
    stx sourceAddress + 1

    .for(var line = 0; line < 25; line++) {     // unroll outer loop
        ldx #width
        !:
            dex
            jsr loadSource                  // load source char code
            tay                             // keep char code in Y
            sta line*40 + screenTarget,x    // copy char code
            lda colorSource,y               // decode color for given char code (now in Y)
            sta line*40 + colorTarget,x     // set given color RAM location
            cpx #0
        bne !-
    }
    rts

    loadSource:
        lda sourceAddress:$ffff,x
        cpx #0
        bne !+
            pha
            clc
            lda #width
            adc sourceAddress
            sta sourceAddress
            lda #0
            adc sourceAddress + 1
            sta sourceAddress + 1
            pla
        !:
    rts
}

copyFullScreen: copyScreenBlock(40, SCREEN, colours, COLOUR_RAM)
copyDashboard: copyScreenBlock(11, SCREEN + 29, colours, COLOUR_RAM + 29)
copyLevel: copyScreenBlock(29, SCREEN, colours, COLOUR_RAM)

drawTitleScreen: {
    lda #<titleScreen
    ldx #>titleScreen
    jsr copyFullScreen
    rts
}

drawDashboard: {
    lda #<dashboard
    ldx #>dashboard
    jsr copyDashboard
    rts
}

// ==== variables ====
levelCounter:       .byte 0
livesCounter:       .byte 0
joyState:           .byte 0
verticalSpeed:      .byte 0 // signed
horizontalSpeed:    .byte 0 // signed

// ==== data ====
.label SPEED_TABLE_HALF_SIZE = 8
.label SPEED_TABLE_SIZE = (SPEED_TABLE_HALF_SIZE - 1)*2 + 1
speedTable:     .fill SPEED_TABLE_HALF_SIZE - 1, -(SPEED_TABLE_HALF_SIZE - i)*(SPEED_TABLE_HALF_SIZE - i)
                .byte 0
                .fill SPEED_TABLE_HALF_SIZE - 1, (i+1)*(i+1)




colours:        .import binary "build/charpad/colours.bin"
titleScreen:    .import binary "build/charpad/title.bin"
dashboard:      .import binary "build/charpad/dashboard.bin"
level1:         .import binary "build/charpad/level1.bin"
level2:         .import binary "build/charpad/level2.bin"

// to save time and coding efforts charset and sprites are moved streight to the target location within VIC-II address space
*=($4000 - $0800) "Charset"
.import binary "build/charpad/charset.bin"
*=($4000 - 3*64) "Sprites"
.import binary "build/spritepad/player.bin"
