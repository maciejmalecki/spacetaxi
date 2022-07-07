#import "build/charpad/metadata.asm"

.label SCREEN = $0400
.label COLOUR_RAM = $D800
.label PLAYER_SHAPE_NEUTRAL = 0
.label PLAYER_SHAPE_LEFT = 1
.label PLAYER_SHAPE_RIGHT = 2
.label SURVIVOR_SHAPE = 3
.label SHAPES_COUNT = 4
.label PLAYER_SPRITE = 0
.label ANIMATION_DELAY_MAX = 10
.label GRAVITY_ACCELERATION = 5
.label UP_ACCELERATION = 5
.label VERTICAL_ACCELERATION = 5

.label LIVES = 5
.label START_LEVEL = 1

.label PLAYER_LEFT  = %00000100
.label PLAYER_RIGHT = %00000010
.label PLAYER_UP    = %00000001

*=$0801 "Basic Upstart"
BasicUpstart(start) // Basic start routine

// Main program
*=$080d "Program"

start: {
    jsr initIRQ
    jsr initIO
    jsr initScreen
    outerMainLoop:
        jsr drawTitleScreen
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
    levelLoop:
        jsr initLevel
        jsr enableIRQ
    mainLoop:
        lda gameState
        and #%00000001
        bne liveLost
        lda $D015
        and #%11111110
        beq nextLevel
        jmp mainLoop
    liveLost:
        jsr disableIRQ
        dec livesCounter
        lda livesCounter
        beq gameOver
        jmp levelLoop
    nextLevel:
        jsr disableIRQ
        inc levelCounter
        lda levelCounter
        cmp #MAX_LEVEL
        beq gameOver
        jmp levelLoop
    gameOver:
        lda #0
        sta $D015 // hide all sprites
    rts
}

doOnEachFrame: {
    jsr handleControls
    jsr updatePosition
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

initGame: {
    lda #START_LEVEL
    sta levelCounter
    lda #LIVES
    sta livesCounter
    // init player sprite
    lda #15
    sta $D027
    lda $D01C
    ora #%00011111
    sta $D01C       // sprite 0 multicolor
    setShapeForSprite(PLAYER_SHAPE_NEUTRAL, PLAYER_SPRITE)
    lda #10
    sta $D028
    sta $D029
    sta $D02A
    sta $D02B
    rts
}

/*
 * IN: A sprites lo, X sprites hi
 */
initSpritesForLevel: {
    sta spritesAddr
    stx spritesAddr + 1

    ldx #0
    jsr loadSpriteByte
    sta hPosition + 1
    sta $D000,x
    lda #0
    sta hPosition
    inx
    jsr loadSpriteByte
    sta vPosition + 1
    sta $D000,x
    lda #0
    sta vPosition
    inx
!:
    jsr loadSpriteByte
    beq endOfSprites
    sta $D000,x
    inx
    jsr loadSpriteByte
    sta $D000,x
    inx
    jmp !-
endOfSprites:
    .for (var i = 0; i < 4; i++) {
        setShapeForSprite(SURVIVOR_SHAPE, i + 1)
    }
    lda $D015
    ora #%00011111
    sta $D015       // show sprite
    rts
loadSpriteByte:
    lda spritesAddr:$FFFF,x
    rts
}

initLevel: {
    // set up player
    zeroWord(vAcceleration)
    zeroWord(hAcceleration)
    zeroWord(vSpeed)
    zeroWord(hSpeed)
    // set up state
    lda #0
    sta gameState
    sta playerState
    // set up level
    jsr drawDashboard
    ldy levelCounter
    dey
    lda spritesLo, y
    ldx spritesHi, y
    jsr initSpritesForLevel
    lda caveLo, y
    ldx caveHi, y
    jsr copyLevel
    // clear collision detection
    lda $D01F
    lda $D01E
    // set up delay
    lda #ANIMATION_DELAY_MAX
    sta animationDelay
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
handleControls: {
    ldx animationDelay
    dex
    beq !+
    stx animationDelay
    rts
!:
    ldx #ANIMATION_DELAY_MAX
    stx animationDelay

    jsr readJoy

    lda joyState
    and #%00000100 // left
    bne !+
    jmp joyLeft
!:
    lda joyState
    and #%00001000 // right
    bne !+
    jmp joyRight
!:
    zeroWord(hAcceleration)
    jmp checkUp
joyLeft:
    lda playerState
    and #PLAYER_RIGHT
    beq !+
        lda playerState
        and #(PLAYER_RIGHT ^ $FF)
        sta playerState
        zeroWord(hAcceleration)
        zeroWord(hSpeed)
        jmp checkUp
!:
    lda playerState
    ora #PLAYER_LEFT
    sta playerState
    setWord(hAcceleration, VERTICAL_ACCELERATION)
    jmp checkUp
joyRight:
    lda playerState
    and #PLAYER_LEFT
    beq !+
        lda playerState
        and #(PLAYER_LEFT ^ $FF)
        sta playerState
        zeroWord(hAcceleration)
        zeroWord(hSpeed)
        jmp checkUp
!:
    lda playerState
    ora #PLAYER_RIGHT
    sta playerState
    setWord(hAcceleration, VERTICAL_ACCELERATION)
checkUp:
    lda joyState
    and #%00000001 // up
    bne !+
    jmp joyUp
!:
    lda playerState
    and #PLAYER_UP
    beq !+
        lda playerState
        and #(PLAYER_UP ^ $FF)
        sta playerState
        setWord(vAcceleration, GRAVITY_ACCELERATION)
        zeroWord(vSpeed)
!:
    setWord(vAcceleration, GRAVITY_ACCELERATION)
    rts
joyUp:
    lda playerState
    and #PLAYER_UP
    bne !+
        lda playerState
        ora #PLAYER_UP
        sta playerState
        setWord(vAcceleration, UP_ACCELERATION)
        zeroWord(vSpeed)
!:
    rts
}

updatePosition: {
    // vertical
    lda playerState
    and #PLAYER_LEFT
    beq !+
        adcWord(hAcceleration, hSpeed, hSpeed)
        sbcWord(hPosition, hSpeed, hPosition)
        jmp vertical
!:
    lda playerState
    and #PLAYER_RIGHT
    beq !+
        adcWord(hAcceleration, hSpeed, hSpeed)
        adcWord(hSpeed, hPosition, hPosition)
!:
vertical:
    lda playerState
    and #PLAYER_UP
    beq !+
        adcWord(vAcceleration, vSpeed, vSpeed)
        sbcWord(vPosition, vSpeed, vPosition)
        rts
!:
        adcWord(vAcceleration, vSpeed, vSpeed)
        adcWord(vPosition, vSpeed, vPosition)
    rts
}

animate: {
    // move player
    lda hPosition + 1
    sta $D000
    lda vPosition + 1
    sta $D001

    lda playerState
    and #PLAYER_LEFT
    beq !+
        setShapeForSprite(PLAYER_SHAPE_LEFT, PLAYER_SPRITE)
        rts
!:
    lda playerState
    and #PLAYER_RIGHT
    beq !+
        setShapeForSprite(PLAYER_SHAPE_RIGHT, PLAYER_SPRITE)
        rts
!:
    setShapeForSprite(PLAYER_SHAPE_NEUTRAL, PLAYER_SPRITE)
    rts
}

checkCollision: {
    lda $D01F
    and #%00000001
    beq !+
        lda gameState
        ora #%00000001
        sta gameState
!:
    lda $D01E
    and #%00011110
    beq !+
        eor $D015
        and #%00011111
        ora #%00000001
        sta $D015
!:
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

    .for(var line = 0; line < 25; line++) { // unroll outer loop
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
    clc
    lda levelCounter
    adc #48
    sta SCREEN + 40*9 + 34
    clc
    lda livesCounter
    adc #48
    sta SCREEN + 40*13 + 34
    rts
}

// ==== aux routines ====
.macro zeroWord(address) {
    lda #0
    sta address
    sta address + 1
}
.macro setWord(address, value) {
    lda #<value
    sta address
    lda #>value
    sta address + 1
}
.macro adcWord(left, right, store) {
    clc
    lda left
    adc right
    sta store
    lda left + 1
    adc right + 1
    sta store + 1
}
.macro sbcWord(left, right, store) {
    sec
    lda left
    sbc right
    sta store
    lda left + 1
    sbc right + 1
    sta store + 1
}

// ==== variables ====
levelCounter:       .byte 0
livesCounter:       .byte 0
joyState:           .byte 0
vAcceleration:      .word 0
hAcceleration:      .word 0
vSpeed:             .word 0
hSpeed:             .word 0
vPosition:          .word 0
hPosition:          .word 0
animationDelay:     .byte 0
gameState:          .byte 0 // %0000000a
playerState:        .byte 0 // %00000abc a: left, b: right, c: up

// ==== data ====
.label MAX_LEVEL = 4
caveLo:         .byte <level1, <level2, <level3
caveHi:         .byte >level1, >level2, >level3
spritesLo:      .byte <sprites1, <sprites2, <sprites3
spritesHi:      .byte >sprites1, >sprites2, >sprites3

sprites1:       .byte 150, 100, 60, 85, 90, 221, 210, 221, 200, 141, 0
sprites2:       .byte 55, 70, 80, 221, 85, 140, 190, 221, 220, 133, 0
sprites3:       .byte 45, 70, 80, 93, 85, 149, 170, 221, 180, 149, 0

colours:        .import binary "build/charpad/colours.bin"
titleScreen:    .import binary "build/charpad/title.bin"
dashboard:      .import binary "build/charpad/dashboard.bin"
level1:         .import binary "build/charpad/level1.bin"
level2:         .import binary "build/charpad/level2.bin"
level3:         .import binary "build/charpad/level3.bin"
/*
 * To save time and coding efforts charset and sprites are moved straight to the target location within VIC-II address space
 * thus it is probably a good idea to pack the game with i.e. Exomizer after compiling.
 */
*=($4000 - $0800) "Charset"
.import binary "build/charpad/charset.bin"
*=($4000 - SHAPES_COUNT*64) "Sprites"
.import binary "build/spritepad/player.bin"
.import binary "build/spritepad/survivor.bin"
