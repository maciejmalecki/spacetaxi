#import "build/charpad/metadata.asm"

.label SCREEN = $0400
.label COLOUR_RAM = $D800


*=$0801 "Basic Upstart"
BasicUpstart(start) // Basic start routine

// Main program
*=$080d "Program"

start: {
    jsr initScreen
    jsr drawTitleScreen
    rts
}

// game initialization
initScreen: {
    lda #backgroundColour0
    sta $D020
    sta $D021
    lda #backgroundColour1
    sta $D022
    lda #backgroundColour2
    sta $D023
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

// ==== data ====

colours:        .import binary "build/charpad/colours.bin"
charset:        .import binary "build/charpad/charset.bin"
titleScreen:    .import binary "build/charpad/title.bin"
dashboard:      .import binary "build/charpad/dashboard.bin"
level1:         .import binary "build/charpad/level1.bin"
level2:         .import binary "build/charpad/level2.bin"

end:
.print "Program size = " + (end - start + 1)