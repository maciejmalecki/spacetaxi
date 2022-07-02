#import "build/charpad/metadata.asm"

.label SCREEN = $0400
.label COLOUR_RAM = $D800
.label PLAYER_SHAPE_NEUTRAL = 0
.label PLAYER_SHAPE_LEFT = 1
.label PLAYER_SHAPE_RIGHT = 2
.label SHAPES_COUNT = 3
.label PLAYER_SPRITE = 0

*=$0801 "Basic Upstart"
BasicUpstart(start) // Basic start routine

// Main program
*=$080d "Program"

start: {
    jsr initIRQ
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
    jsr enableIRQ
    mainLoop:
        jsr readJoy
        jmp mainLoop
    gameOver:
    jsr disableIRQ
    rts
}

doOnEachFrame: {
    jsr updatePositions
    jsr animate
    jsr checkCollision
    dec $D019 // clear interrupt flag
    jmp $EA31
}

// game initialization
initIRQ: {
    sei
    // disable CIA#1 interrupts
    lda #$7F
    sta $DC0D
    lda $DC0D
    // set new IRQ handler
    lda #<doOnEachFrame
    sta $0314
    lda #>doOnEachFrame
    sta $0315
    cli
    rts
}

enableIRQ: {
    lda #40
    sta $D012
    lda $D011
    and #%0111111
    sta $D011
    lda #%00000001
    sta $D01A
    rts
}

disableIRQ: {
    lda #%00000000
    sta $D01A
    rts
}

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
    setShapeForSprite(PLAYER_SHAPE_NEUTRAL, PLAYER_SPRITE)
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
    lda #SPEED_TABLE_HALF_SIZE
    sta verticalPosition
    sta horizontalPosition
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

// ==== Game physics ====
updatePositions: {
    lda joyState
    and #%00000100 // left
    bne !+
    jsr joyLeft
!:
    lda joyState
    and #%00001000 // right
    bne !+
    jsr joyRight
!:
    jmp checkUp
joyLeft:
    lda horizontalPosition
    beq checkUp
    dec horizontalPosition
    jmp checkUp
joyRight:
    lda horizontalPosition
    cmp #SPEED_TABLE_SIZE
    beq checkUp
    inc horizontalPosition
checkUp:
    lda joyState
    and #%00000001 // up
    bne !+
    jmp joyUp
!:
    lda verticalPosition
    cmp #SPEED_TABLE_SIZE
    beq end
    inc verticalPosition  // here gravity works
    jmp end
joyUp:
    lda verticalPosition
    beq end
    dec verticalPosition
    jmp end
end:
    rts
}

animate: {
    // move player
    lda $D000
    ldx horizontalPosition
    cpx #SPEED_TABLE_HALF_SIZE
    bcs !+
    jmp goLeft
!:
    bne goRight
    setShapeForSprite(PLAYER_SHAPE_NEUTRAL, PLAYER_SPRITE)
    jmp animateVertical
goLeft:
    sec
    sbc speedTable,x
    sta $D000
    setShapeForSprite(PLAYER_SHAPE_LEFT, PLAYER_SPRITE)
    jmp animateVertical
goRight:
    clc
    adc speedTable,x
    sta $D000
    setShapeForSprite(PLAYER_SHAPE_RIGHT, PLAYER_SPRITE)
animateVertical:
    lda $D001
    ldx verticalPosition
    cpx #SPEED_TABLE_HALF_SIZE
    bcs !+
    jmp goUp
!:
    bne goDown
goUp:
    sec
    sbc speedTable,x
    sta $D001
    rts
goDown:
    clc
    adc speedTable,x
    sta $D001
    rts
}

checkCollision: {
    rts
}

// ==== sprites routines ====
.macro setShapeForSprite(shapeNum, spriteNum) {
    lda #(256 - SHAPES_COUNT + shapeNum)
    sta SCREEN + 1024 - 8 + spriteNum
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
verticalPosition:   .byte 0 // signed
horizontalPosition:    .byte 0 // signed

// ==== data ====
.label SPEED_TABLE_HALF_SIZE = 8
.label SPEED_TABLE_SIZE = (SPEED_TABLE_HALF_SIZE - 1)*2 + 1
speedTable:     .fill SPEED_TABLE_HALF_SIZE - 1, ceil(0.05*(SPEED_TABLE_HALF_SIZE - i)*(SPEED_TABLE_HALF_SIZE - i))
                .byte 0
                .fill SPEED_TABLE_HALF_SIZE - 1, ceil(0.05*(i+1)*(i+1))

.for (var i = 0; i < SPEED_TABLE_HALF_SIZE; i++) {
    .print ceil(0.05*(SPEED_TABLE_HALF_SIZE - i)*(SPEED_TABLE_HALF_SIZE - i))
}
.for (var i = 0; i < SPEED_TABLE_HALF_SIZE; i++) {
    .print ceil(0.05*(i+1)*(i+1))
}

.print SPEED_TABLE_SIZE

colours:        .import binary "build/charpad/colours.bin"
titleScreen:    .import binary "build/charpad/title.bin"
dashboard:      .import binary "build/charpad/dashboard.bin"
level1:         .import binary "build/charpad/level1.bin"
level2:         .import binary "build/charpad/level2.bin"

/*
 * To save time and coding efforts charset and sprites are moved straight to the target location within VIC-II address space
 * thus it is probably a good idea to pack the game with i.e. Exomizer after compiling.
 */
*=($4000 - $0800) "Charset"
.import binary "build/charpad/charset.bin"
*=($4000 - 3*64) "Sprites"
.import binary "build/spritepad/player.bin"
