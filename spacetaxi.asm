
.label SCREEN = $1000
.label COLOUR_RAM = $D800


*=$0801 "Basic Upstart"
BasicUpstart(start) // Basic start routine

// Main program
*=$080d "Program"

start:
    lda #BLACK
    sta $D020
    sta $D021
    rts


// ==== screen drawing routines ====

/*
 * IN:
 *   A - source address lsb
 *   X - source address hsb
 * DESTROYS: A, X, Y
 */
.macro copyScreenBlock(width, screenTarget, colorSource, colorTarget) {
    sta sourceAddressStorage
    stx sourceAddressStorage + 1

    .for(var line = 0; line < 25; line++) {     // unroll outer loop
        ldx #width
        lda sourceAddressStorage
        sta sourceAddress
        lda sourceAddressStorage + 1
        sta sourceAddress + 1
        !:
            dex
            lda sourceAddress:$ffff,x          // load source char code
            tay                                 // keep char code in Y
            sta line*40 + screenTarget,x    // copy char code
            lda colorSource,y                   // decode color for given char code (now in Y)
            sta line*40 + colorTarget,x     // set given color RAM location
            cpx #0
        bne !-
    }
    rts
    sourceAddressStorage: .word $0000
}

copyFullScreen: copyScreenBlock(40, SCREEN, colours, COLOUR_RAM)
copyDashboard: copyScreenBlock(11, SCREEN + 29, colours, COLOUR_RAM + 29)
copyLevel: copyScreenBlock(29, SCREEN, colours, COLOUR_RAM)

// ==== data ====

colours:        .import binary "build/charpad/colours.bin"
titleScreen:    .import binary "build/charpad/title.bin"
dashboard:      .import binary "build/charpad/dashboard.bin"
level1:         .import binary "build/charpad/level1.bin"
level2:         .import binary "build/charpad/level2.bin"
