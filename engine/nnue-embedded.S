/*
 * Android-specific NNUE embedding object.
 * Kept separate from C++ so Clang ThinLTO cannot discard the assembler labels.
 * Build from engine/ so the .incbin path resolves to onechess.nnue.
 */
.section .rodata.onechess_network,"a",%progbits
.balign 64
.global one_reseau_debut
.type one_reseau_debut, %object
one_reseau_debut:
.incbin "onechess.nnue"
.global one_reseau_fin
.type one_reseau_fin, %object
one_reseau_fin:
.size one_reseau_debut, one_reseau_fin-one_reseau_debut
.text
