.data
# The Bitmap Display starts at 0x10010000, so keep this first.
framebuffer: .space 1024

# 0 = empty, 1 = X, 2 = O
board: .word 0:9

# Rows, columns, and diagonals.
win_lines: .word 0,1,2, 3,4,5, 6,7,8
           .word 0,3,6, 1,4,7, 2,5,8
           .word 0,4,8, 2,4,6

instructions: .asciiz "Tic-Tac-Toe: choose squares 1-9, left to right, top to bottom.\n"
x_prompt:     .asciiz "Player 1 (X): press 1-9 in the MMIO keyboard.\n"
o_prompt:     .asciiz "Player 2 (O): press 1-9 in the MMIO keyboard.\n"
invalid_msg:  .asciiz "Invalid key. Choose 1 through 9.\n"
occupied_msg: .asciiz "That square is occupied. Try another.\n"
x_win_msg:    .asciiz "Player 1 (X) wins!\n"
o_win_msg:    .asciiz "Player 2 (O) wins!\n"
draw_msg:     .asciiz "Draw! All nine squares are filled.\n"

.text
.globl main

main:
    li $s0, 1                  # Current player: 1 = X, 2 = O
    li $s1, 0                  # Number of valid moves

    jal clear_display
    jal draw_board

    li $v0, 4
    la $a0, instructions
    syscall

turn_loop:
    beq $s0, 1, prompt_x

    li $v0, 4
    la $a0, o_prompt
    syscall
    j read_move

prompt_x:
    li $v0, 4
    la $a0, x_prompt
    syscall

read_move:
    jal read_key

    # ASCII '1' is 49 and ASCII '9' is 57.
    blt $v0, 49, invalid_move
    bgt $v0, 57, invalid_move

    addiu $s2, $v0, -49        # Convert key to square index 0-8
    la $t0, board
    sll $t1, $s2, 2            # Word index: index * 4
    addu $t0, $t0, $t1
    lw $t2, 0($t0)
    bnez $t2, occupied_move

    sw $s0, 0($t0)             # Store this move in the board array
    move $a0, $s2

    beq $s0, 1, x_move
    jal draw_o
    j move_done

x_move:
    jal draw_x

move_done:
    addiu $s1, $s1, 1

    move $a0, $s0
    jal check_winner
    bnez $v0, player_wins

    beq $s1, 9, board_full

    li $t0, 3
    subu $s0, $t0, $s0         # Switch player 1 <-> player 2
    j turn_loop

invalid_move:
    li $v0, 4
    la $a0, invalid_msg
    syscall
    j turn_loop

occupied_move:
    li $v0, 4
    la $a0, occupied_msg
    syscall
    j turn_loop

player_wins:
    beq $s0, 1, x_wins

    li $v0, 4
    la $a0, o_win_msg
    syscall
    j end_game

x_wins:
    li $v0, 4
    la $a0, x_win_msg
    syscall
    j end_game

board_full:
    li $v0, 4
    la $a0, draw_msg
    syscall

end_game:
    li $v0, 10
    syscall

# Write black to every unit, removing marks from a previous run.
clear_display:
    la $t0, framebuffer
    li $t1, 256
    li $t2, 0

clear_loop:
    sw $zero, 0($t0)
    addiu $t0, $t0, 4
    addiu $t2, $t2, 1
    bne $t2, $t1, clear_loop
    jr $ra

# Draw white grid lines at rows and columns 5 and 10.
draw_board:
    la $t0, framebuffer
    li $t1, 0x00FFFFFF
    li $t2, 1

board_row:
    bgt $t2, 14, board_done
    li $t3, 1

board_column:
    bgt $t3, 14, next_row
    beq $t3, 5, draw_white
    beq $t3, 10, draw_white
    beq $t2, 5, draw_white
    beq $t2, 10, draw_white
    j next_column

draw_white:
    sll $t4, $t2, 4
    addu $t4, $t4, $t3
    sll $t4, $t4, 2
    addu $t4, $t4, $t0
    sw $t1, 0($t4)

next_column:
    addiu $t3, $t3, 1
    j board_column

next_row:
    addiu $t2, $t2, 1
    j board_row

board_done:
    jr $ra

# Poll the Keyboard and Display MMIO Simulator.
# Return the key's ASCII value in $v0.
read_key:
    li $t0, 0xffff0000

wait_for_key:
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beqz $t1, wait_for_key

    lw $v0, 4($t0)
    jr $ra

# Draw a red X. $a0 = square index 0-8.
draw_x:
    li $t6, 3
    div $a0, $t6
    mflo $t0                    # Board row
    mfhi $t1                    # Board column

    li $t6, 5
    mul $t0, $t0, $t6
    mul $t1, $t1, $t6
    addiu $t0, $t0, 2           # First display row
    addiu $t1, $t1, 2           # First display column

    la $t6, framebuffer
    li $t7, 0x00FF0000          # Red
    li $t2, 0

x_pixel_loop:
    # First diagonal: (row + i, column + i)
    addu $t3, $t0, $t2
    sll $t3, $t3, 4
    addu $t3, $t3, $t1
    addu $t3, $t3, $t2
    sll $t3, $t3, 2
    addu $t3, $t3, $t6
    sw $t7, 0($t3)

    # Second diagonal: (row + i, column + 2 - i)
    addu $t3, $t0, $t2
    sll $t3, $t3, 4
    addu $t3, $t3, $t1
    addiu $t3, $t3, 2
    subu $t3, $t3, $t2
    sll $t3, $t3, 2
    addu $t3, $t3, $t6
    sw $t7, 0($t3)

    addiu $t2, $t2, 1
    blt $t2, 3, x_pixel_loop
    jr $ra

# Draw a cyan O. $a0 = square index 0-8.
draw_o:
    li $t6, 3
    div $a0, $t6
    mflo $t0                    # Board row
    mfhi $t1                    # Board column

    li $t6, 5
    mul $t0, $t0, $t6
    mul $t1, $t1, $t6
    addiu $t0, $t0, 2
    addiu $t1, $t1, 2

    la $t6, framebuffer
    li $t7, 0x0000FFFF          # Cyan
    li $t2, 0

o_row_loop:
    li $t3, 0

o_column_loop:
    # Paint a 3-by-3 outline but leave the center black.
    bne $t2, 1, paint_o
    beq $t3, 1, skip_o

paint_o:
    addu $t4, $t0, $t2
    sll $t4, $t4, 4
    addu $t4, $t4, $t1
    addu $t4, $t4, $t3
    sll $t4, $t4, 2
    addu $t4, $t4, $t6
    sw $t7, 0($t4)

skip_o:
    addiu $t3, $t3, 1
    blt $t3, 3, o_column_loop

    addiu $t2, $t2, 1
    blt $t2, 3, o_row_loop
    jr $ra

# Check all eight winning lines for the player in $a0.
# Return 1 in $v0 for a win; otherwise return 0.
# This procedure calls another procedure, so it saves $ra and $s registers.
check_winner:
    addiu $sp, $sp, -16
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)

    move $s2, $a0
    la $s0, win_lines
    li $s1, 8

check_next_line:
    lw $a0, 0($s0)
    lw $a1, 4($s0)
    lw $a2, 8($s0)
    move $a3, $s2
    jal check_line

    bnez $v0, found_winner
    addiu $s0, $s0, 12
    addiu $s1, $s1, -1
    bnez $s1, check_next_line

    li $v0, 0
    j winner_check_done

found_winner:
    li $v0, 1

winner_check_done:
    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addiu $sp, $sp, 16
    jr $ra

# $a0, $a1, $a2 = square indexes; $a3 = player.
# Return 1 only if that player owns all three squares.
check_line:
    la $t0, board

    sll $t1, $a0, 2
    addu $t1, $t1, $t0
    lw $t2, 0($t1)
    bne $t2, $a3, line_not_won

    sll $t1, $a1, 2
    addu $t1, $t1, $t0
    lw $t2, 0($t1)
    bne $t2, $a3, line_not_won

    sll $t1, $a2, 2
    addu $t1, $t1, $t0
    lw $t2, 0($t1)
    bne $t2, $a3, line_not_won

    li $v0, 1
    jr $ra

line_not_won:
    li $v0, 0
    jr $ra