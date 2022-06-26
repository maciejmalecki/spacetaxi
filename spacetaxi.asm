*=$0801 "Basic Upstart"
BasicUpstart(start) // Basic start routine

// Main program
*=$080d "Program"

start:
    lda #BLACK
    sta $D020
    sta $D021
    rts
