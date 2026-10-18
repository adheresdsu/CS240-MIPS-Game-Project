# CS240 - 7 Up 7 Down (MARS MIPS)
# Bitmap Display: unit 16x16, display 256x256, base 0x10010000
# Connect the Bitmap Display and Keyboard and Display MMIO Simulator.
# Type in the MMIO keyboard (receiver control 0xffff0000, data 0xffff0004).
# Graphics: two white dice with dark pips; choice marker; green/red result bar.
# Run I/O contains the rules, dice values, scores, and error messages.

.data
framebuffer: .space 1024       # Must be first: 16 x 16 x 4 bytes
dice:        .space 8          # dice[0], dice[1]
history:     .space 40         # Last ten totals, circular array
rounds:      .word 0
wins:        .word 0
choice:      .word 0          # 1=down, 2=seven, 3=up

intro:       .asciiz "7 UP 7 DOWN: Two dice are rolled.\n"
rules:       .asciiz "D = total below 7, 7 = exactly 7, U = above 7. Q = quit.\n"
prompt:      .asciiz "Guess D, 7, or U in the MMIO keyboard (Q quits): "
invalid:     .asciiz "Invalid key. Choose D, 7, U, or Q.\n"
roll_text:   .asciiz "Dice: "
plus_text:   .asciiz " + "
total_text:  .asciiz " = "
win_text:    .asciiz "Correct! You win this round.\n"
lose_text:   .asciiz "Incorrect. You lose this round.\n"
score_text:  .asciiz "Score: "
of_text:     .asciiz " wins out of "
round_text:  .asciiz " rounds.\n"
again_text:  .asciiz "Press R for another round or Q to quit.\n"
bad_again:   .asciiz "Invalid key. Press R or Q.\n"
bye_text:    .asciiz "Thanks for playing!\n"

.text
.globl main
main:
    jal reset_game
    li $v0, 4
    la $a0, intro
    syscall
    li $v0, 4
    la $a0, rules
    syscall

new_round:
    jal draw_board
guess_loop:
    li $v0, 4
    la $a0, prompt
    syscall
    jal read_key
    li $t0, 113              # q
    beq $v0, $t0, quit_game
    li $t0, 81               # Q
    beq $v0, $t0, quit_game
    li $t0, 100              # d
    beq $v0, $t0, picked_down
    li $t0, 68               # D
    beq $v0, $t0, picked_down
    li $t0, 55               # 7
    beq $v0, $t0, picked_seven
    li $t0, 117              # u
    beq $v0, $t0, picked_up
    li $t0, 85               # U
    beq $v0, $t0, picked_up
    li $v0, 4
    la $a0, invalid
    syscall
    j guess_loop

picked_down:
    li $t0, 1
    j play_round
picked_seven:
    li $t0, 2
    j play_round
picked_up:
    li $t0, 3

play_round:
    sw $t0, choice
    jal show_choice_marker
    jal roll_dice           # v0 = sum (2..12)
    move $s0, $v0           # main owns s0; callees preserve it
    jal record_total
    jal show_roll
    li $a0, 2
    li $a1, 2
    lw $a2, dice
    jal draw_die
    li $a0, 9
    li $a1, 2
    la $t4, dice
    lw $a2, 4($t4)
    jal draw_die

    lw $t0, choice
    li $t1, 1
    beq $t0, $t1, check_down
    li $t1, 2
    beq $t0, $t1, check_seven
    bgt $s0, 7, won_round
    j lost_round
check_down:
    blt $s0, 7, won_round
    j lost_round
check_seven:
    beq $s0, 7, won_round
    j lost_round

won_round:
    lw $t0, wins
    addiu $t0, $t0, 1
    sw $t0, wins
    li $v0, 4
    la $a0, win_text
    syscall
    li $a0, 0x0000FF00     # Green result
    jal draw_result_bar
    j round_finished
lost_round:
    li $v0, 4
    la $a0, lose_text
    syscall
    li $a0, 0x00FF0000     # Red result
    jal draw_result_bar

round_finished:
    jal show_score
replay_loop:
    li $v0, 4
    la $a0, again_text
    syscall
    jal read_key
    li $t0, 114              # r
    beq $v0, $t0, new_round
    li $t0, 82               # R
    beq $v0, $t0, new_round
    li $t0, 113              # q
    beq $v0, $t0, quit_game
    li $t0, 81               # Q
    beq $v0, $t0, quit_game
    li $v0, 4
    la $a0, bad_again
    syscall
    j replay_loop

quit_game:
    li $v0, 4
    la $a0, bye_text
    syscall
    li $v0, 10
    syscall

# Initialize persistent scores and both arrays once at startup.
reset_game:
    sw $zero, rounds
    sw $zero, wins
    sw $zero, choice
    la $t0, dice
    li $t1, 12             # 2 dice + 10 history words
reset_loop:
    sw $zero, 0($t0)
    addiu $t0, $t0, 4
    addiu $t1, $t1, -1
    bnez $t1, reset_loop
    jr $ra

# MARS service 42: uniform integer in [0, 6), returned in a0.
# a0 is the random stream number; two consecutive rolls use stream 0.
roll_dice:
    li $v0, 42
    li $a0, 0
    li $a1, 6
    syscall
    addiu $t2, $a0, 1
    sw $t2, dice
    li $v0, 42
    li $a0, 0
    li $a1, 6
    syscall
    addiu $t3, $a0, 1
    la $t4, dice
    sw $t3, 4($t4)
    addu $v0, $t2, $t3
    jr $ra

# Store this total at history[rounds % 10], then increment rounds.
record_total:
    lw $t0, rounds
    li $t1, 10
    div $t0, $t1
    mfhi $t2
    sll $t2, $t2, 2
    la $t3, history
    addu $t3, $t3, $t2
    sw $s0, 0($t3)
    addiu $t0, $t0, 1
    sw $t0, rounds
    jr $ra

show_roll:
    li $v0, 4
    la $a0, roll_text
    syscall
    li $v0, 1
    lw $a0, dice
    syscall
    li $v0, 4
    la $a0, plus_text
    syscall
    li $v0, 1
    la $t4, dice
    lw $a0, 4($t4)
    syscall
    li $v0, 4
    la $a0, total_text
    syscall
    li $v0, 1
    move $a0, $s0
    syscall
    li $v0, 11
    li $a0, 10
    syscall
    jr $ra

show_score:
    li $v0, 4
    la $a0, score_text
    syscall
    li $v0, 1
    lw $a0, wins
    syscall
    li $v0, 4
    la $a0, of_text
    syscall
    li $v0, 1
    lw $a0, rounds
    syscall
    li $v0, 4
    la $a0, round_text
    syscall
    jr $ra

# Busy-wait on the MARS MMIO keyboard ready bit. Return ASCII in v0.
read_key:
    li $t0, 0xffff0000
wait_key:
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beqz $t1, wait_key
    lw $v0, 4($t0)
    jr $ra

# Fill 16x16 background. The white line separates dice from indicators.
draw_board:
    la $t0, framebuffer
    li $t1, 0x00002222
    li $t2, 256
board_fill:
    sw $t1, 0($t0)
    addiu $t0, $t0, 4
    addiu $t2, $t2, -1
    bnez $t2, board_fill
    la $t0, framebuffer
    li $t1, 0x00FFFFFF
    li $t2, 1
board_line:
    addiu $t3, $t2, 144     # row 9
    sll $t3, $t3, 2
    addu $t3, $t3, $t0
    sw $t1, 0($t3)
    addiu $t2, $t2, 1
    ble $t2, 14, board_line
    jr $ra

# The colored row-10 marker shows the selected category.
# Left yellow = down; center magenta = seven; right blue = up.
show_choice_marker:
    lw $t0, choice
    li $t1, 1
    beq $t0, $t1, marker_down
    li $t1, 2
    beq $t0, $t1, marker_seven
    li $t2, 10
    li $t3, 14
    li $t4, 0x000066FF
    j marker_loop
marker_down:
    li $t2, 1
    li $t3, 5
    li $t4, 0x00FFFF00
    j marker_loop
marker_seven:
    li $t2, 6
    li $t3, 9
    li $t4, 0x00FF00FF
marker_loop:
    la $t5, framebuffer
    addiu $t6, $t2, 160     # row 10
    sll $t6, $t6, 2
    addu $t6, $t6, $t5
    sw $t4, 0($t6)
    addiu $t2, $t2, 1
    ble $t2, $t3, marker_loop
    jr $ra

# Color row 12 for win/loss; color arrives in a0.
draw_result_bar:
    la $t0, framebuffer
    li $t1, 1
result_loop:
    addiu $t2, $t1, 192     # row 12
    sll $t2, $t2, 2
    addu $t2, $t2, $t0
    sw $a0, 0($t2)
    addiu $t1, $t1, 1
    ble $t1, 14, result_loop
    jr $ra

# a0=x, a1=y, a2=color; framebuffer[y * 16 + x] = color.
plot_pixel:
    sll $t0, $a1, 4
    addu $t0, $t0, $a0
    sll $t0, $t0, 2
    la $t1, framebuffer
    addu $t0, $t0, $t1
    sw $a2, 0($t0)
    jr $ra

# Draw a 5x5 white die face at a0,a1 with a2 pips (1..6).
# Nested calls save ra; saved registers retain origin and die value.
draw_die:
    addiu $sp, $sp, -32
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)
    move $s0, $a0
    move $s1, $a1
    move $s2, $a2
    li $s3, 0
die_fill_row:
    li $s4, 0
die_fill_col:
    addu $a0, $s0, $s4
    addu $a1, $s1, $s3
    li $a2, 0x00FFFFFF
    jal plot_pixel
    addiu $s4, $s4, 1
    blt $s4, 5, die_fill_col
    addiu $s3, $s3, 1
    blt $s3, 5, die_fill_row

    beq $s2, 1, pip_center_only
    beq $s2, 6, pip_six
    # For 2,3,4,5: opposite corners.
    li $a0, 1
    li $a1, 1
    jal die_pip
    li $a0, 3
    li $a1, 3
    jal die_pip
    beq $s2, 2, die_done
    beq $s2, 3, pip_center_only
    li $a0, 3
    li $a1, 1
    jal die_pip
    li $a0, 1
    li $a1, 3
    jal die_pip
    beq $s2, 4, die_done
pip_center_only:
    li $a0, 2
    li $a1, 2
    jal die_pip
    j die_done
pip_six:
    li $s3, 1
six_loop:
    li $a0, 1
    move $a1, $s3
    jal die_pip
    li $a0, 3
    move $a1, $s3
    jal die_pip
    addiu $s3, $s3, 1
    ble $s3, 3, six_loop
die_done:
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addiu $sp, $sp, 32
    jr $ra

# a0,a1 = pip's offsets within the current die face.
die_pip:
    addu $a0, $a0, $s0
    addu $a1, $a1, $s1
    li $a2, 0x00000000
    j plot_pixel             # Tail call; plot_pixel returns to draw_die.