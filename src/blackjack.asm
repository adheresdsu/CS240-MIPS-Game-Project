.data
framebuffer:   .space 1024          # First: Bitmap Display at 0x10010000
deck:          .space 208           # 52 card IDs, 0..51
player_cards:  .space 52            # 13 word slots
dealer_cards:  .space 52
deck_index:    .word 0
player_count:  .word 0
dealer_count:  .word 0
player_total:  .word 0
dealer_total:  .word 0
player_aces:   .word 0             # Aces still worth 11
dealer_aces:   .word 0

intro:         .asciiz "BLACKJACK - H=hit, S=stand. Dealer stands on 17.\n"
legend:        .asciiz "Cards: S=spades H=hearts D=diamonds C=clubs.\n"
up_label:      .asciiz "Dealer shows: "
player_label:  .asciiz "Your cards: "
dealer_label:  .asciiz "Dealer cards: "
player_score:  .asciiz "Your total: "
dealer_score:  .asciiz "Dealer total: "
turn_prompt:   .asciiz "Press H to hit or S to stand in the MMIO keyboard.\n"
invalid_turn:  .asciiz "Invalid key. Press H or S.\n"
natural_win:   .asciiz "Natural Blackjack! You win.\n"
natural_lose:  .asciiz "Dealer has natural Blackjack. Dealer wins.\n"
bust_text:     .asciiz "Bust! Dealer wins.\n"
win_text:      .asciiz "You win!\n"
lose_text:     .asciiz "Dealer wins.\n"
tie_text:      .asciiz "Push: tie game.\n"
replay_prompt: .asciiz "Press R for a new round or Q to quit.\n"
invalid_end:   .asciiz "Invalid key. Press R or Q.\n"
blank:         .asciiz " "
newline:       .asciiz "\n"

.text
.globl main

main:
new_round:
    jal reset_round
    jal draw_table
    jal initialize_deck
    jal shuffle_deck

    li $a0, 0                  # 0 = player, 1 = dealer
    jal deal_card
    li $a0, 1
    jal deal_card
    li $a0, 0
    jal deal_card
    li $a0, 1
    jal deal_card

    li $v0, 4
    la $a0, intro
    syscall
    li $v0, 4
    la $a0, legend
    syscall
    jal show_upcard
    li $a0, 0
    jal show_hand

    # A two-card 21 is a natural. Check both before player input.
    lw $t0, player_total
    lw $t1, dealer_total
    bne $t0, 21, check_dealer_natural
    beq $t1, 21, double_natural
    jal reveal_hole_card
    li $a0, 1
    jal show_hand
    li $v0, 4
    la $a0, natural_win
    syscall
    li $a0, 0x0000FF00
    jal paint_result
    j round_over

check_dealer_natural:
    bne $t1, 21, player_turn
    jal reveal_hole_card
    li $a0, 1
    jal show_hand
    li $v0, 4
    la $a0, natural_lose
    syscall
    li $a0, 0x00FF0000
    jal paint_result
    j round_over

double_natural:
    jal reveal_hole_card
    li $a0, 1
    jal show_hand
    j push_result

player_turn:
    li $v0, 4
    la $a0, turn_prompt
    syscall
    jal read_key
    li $t0, 104                # h
    beq $v0, $t0, player_hit
    li $t0, 72                 # H
    beq $v0, $t0, player_hit
    li $t0, 115                # s
    beq $v0, $t0, dealer_turn
    li $t0, 83                 # S
    beq $v0, $t0, dealer_turn
    li $v0, 4
    la $a0, invalid_turn
    syscall
    j player_turn

player_hit:
    li $a0, 0
    jal deal_card
    li $a0, 0
    jal show_hand
    lw $t0, player_total
    bgt $t0, 21, player_bust
    beq $t0, 21, dealer_turn
    j player_turn

player_bust:
    jal reveal_hole_card
    li $a0, 1
    jal show_hand
    li $v0, 4
    la $a0, bust_text
    syscall
    li $a0, 0x00FF0000
    jal paint_result
    j round_over

dealer_turn:
    jal reveal_hole_card
dealer_draw_loop:
    lw $t0, dealer_total
    bge $t0, 17, compare_scores
    li $a0, 1
    jal deal_card
    j dealer_draw_loop

compare_scores:
    li $a0, 1
    jal show_hand
    lw $t0, dealer_total
    lw $t1, player_total
    bgt $t0, 21, player_wins
    bgt $t1, $t0, player_wins
    beq $t1, $t0, push_result

    li $v0, 4
    la $a0, lose_text
    syscall
    li $a0, 0x00FF0000
    jal paint_result
    j round_over

player_wins:
    li $v0, 4
    la $a0, win_text
    syscall
    li $a0, 0x0000FF00
    jal paint_result
    j round_over

push_result:
    li $v0, 4
    la $a0, tie_text
    syscall
    li $a0, 0x00FFFF00
    jal paint_result

round_over:
    li $v0, 4
    la $a0, replay_prompt
    syscall
    jal read_key
    li $t0, 114                # r
    beq $v0, $t0, new_round
    li $t0, 82                 # R
    beq $v0, $t0, new_round
    li $t0, 113                # q
    beq $v0, $t0, exit_game
    li $t0, 81                 # Q
    beq $v0, $t0, exit_game
    li $v0, 4
    la $a0, invalid_end
    syscall
    j round_over

exit_game:
    li $v0, 10
    syscall

# Reset all round state. Graphics are overwritten by draw_table.
reset_round:
    la $t0, deck_index
    li $t1, 7
reset_word_loop:
    sw $zero, 0($t0)
    addiu $t0, $t0, 4
    addiu $t1, $t1, -1
    bnez $t1, reset_word_loop
    jr $ra

# deck[i] = i for 0 <= i < 52.
initialize_deck:
    la $t0, deck
    li $t1, 0
initialize_loop:
    sw $t1, 0($t0)
    addiu $t0, $t0, 4
    addiu $t1, $t1, 1
    blt $t1, 52, initialize_loop
    jr $ra

# In-place Fisher-Yates shuffle using MARS random-range syscall 42.
shuffle_deck:
    addiu $sp, $sp, -16
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)
    la $s1, deck
    li $s0, 51
shuffle_loop:
    li $v0, 42
    li $a0, 0
    addiu $a1, $s0, 1
    syscall
    move $s2, $a0
    sll $t0, $s0, 2
    addu $t0, $t0, $s1
    sll $t1, $s2, 2
    addu $t1, $t1, $s1
    lw $t2, 0($t0)
    lw $t3, 0($t1)
    sw $t3, 0($t0)
    sw $t2, 0($t1)
    addiu $s0, $s0, -1
    bgtz $s0, shuffle_loop
    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addiu $sp, $sp, 16
    jr $ra

# Return the next unique card ID in $v0 (rank = ID % 13 + 1).
draw_card_id:
    la $t0, deck_index
    lw $t1, 0($t0)
    sll $t2, $t1, 2
    la $t3, deck
    addu $t3, $t3, $t2
    lw $v0, 0($t3)
    addiu $t1, $t1, 1
    sw $t1, 0($t0)
    jr $ra

# $a0 is seat 0=player/1=dealer. Append one card, score it, draw it.
deal_card:
    addiu $sp, $sp, -40
    sw $ra, 36($sp)
    sw $s0, 32($sp)
    sw $s1, 28($sp)
    sw $s2, 24($sp)
    sw $s3, 20($sp)
    sw $s4, 16($sp)
    sw $s5, 12($sp)
    sw $s6, 8($sp)
    sw $s7, 4($sp)
    move $s0, $a0
    jal draw_card_id
    move $s1, $v0             # Card ID
    li $t0, 13
    div $s1, $t0
    mfhi $s2
    addiu $s2, $s2, 1         # Rank 1..13
    beqz $s0, deal_player
    la $s4, dealer_total
    la $s5, dealer_aces
    la $s6, dealer_count
    la $s7, dealer_cards
    j append_card
deal_player:
    la $s4, player_total
    la $s5, player_aces
    la $s6, player_count
    la $s7, player_cards
append_card:
    lw $s3, 0($s6)            # Old hand size
    sll $t0, $s3, 2
    addu $t0, $t0, $s7
    sw $s1, 0($t0)
    addiu $s3, $s3, 1
    sw $s3, 0($s6)
    move $t1, $s2
    bne $s2, 1, check_face
    li $t1, 11
    lw $t2, 0($s5)
    addiu $t2, $t2, 1
    sw $t2, 0($s5)
    j add_score
check_face:
    ble $s2, 10, add_score
    li $t1, 10
add_score:
    lw $t2, 0($s4)
    addu $t2, $t2, $t1
    sw $t2, 0($s4)
adjust_aces:
    lw $t2, 0($s4)
    ble $t2, 21, draw_dealt_card
    lw $t3, 0($s5)
    beqz $t3, draw_dealt_card
    addiu $t2, $t2, -10
    sw $t2, 0($s4)
    addiu $t3, $t3, -1
    sw $t3, 0($s5)
    j adjust_aces
draw_dealt_card:
    move $a0, $s0
    addiu $a1, $s3, -1
    move $a2, $s1
    li $a3, 0
    bne $s0, 1, draw_dealt_now
    bne $s3, 2, draw_dealt_now
    li $a3, 1                 # Hide dealer's second card
draw_dealt_now:
    jal paint_card_icon
    lw $s7, 4($sp)
    lw $s6, 8($sp)
    lw $s5, 12($sp)
    lw $s4, 16($sp)
    lw $s3, 20($sp)
    lw $s2, 24($sp)
    lw $s1, 28($sp)
    lw $s0, 32($sp)
    lw $ra, 36($sp)
    addiu $sp, $sp, 40
    jr $ra

# Bitmap: 10 small icons per hand in two rows of five.
# $a0 seat, $a1 zero-based card position, $a2 card ID, $a3 hidden.
paint_card_icon:
    addiu $sp, $sp, -8
    sw $ra, 4($sp)
    blt $a1, 10, icon_in_range
    move $t0, $a0             # Rare overflow marker for 11th card
    li $a0, 0
    li $a1, 0                 # Dealer: upper-left
    bnez $t0, overflow_icon
    li $a1, 15                # Player: lower-left
overflow_icon:
    li $a2, 0x00FF00FF
    jal plot_pixel
    j icon_done
icon_in_range:
    li $t0, 5
    div $a1, $t0
    mflo $t1                   # Graphic row 0 or 1
    mfhi $t2                   # Column 0..4
    li $t3, 3
    mul $t2, $t2, $t3
    addiu $t2, $t2, 1
    beqz $a0, icon_player
    li $t3, 1
    j icon_position
icon_player:
    li $t3, 9
icon_position:
    li $t4, 3
    mul $t1, $t1, $t4
    addu $t3, $t3, $t1
    move $t5, $a3             # Hidden flag
    li $t4, 13
    div $a2, $t4
    mflo $t4                   # Suit 0=S, 1=H, 2=D, 3=C
    li $a2, 0x00FFFFFF
    beq $t4, 1, red_suit
    beq $t4, 2, red_suit
    j check_hidden
red_suit:
    li $a2, 0x00FF5555
check_hidden:
    beqz $t5, icon_draw
    li $a2, 0x000044AA
icon_draw:
    move $a0, $t2
    move $a1, $t3
    jal draw_icon
icon_done:
    lw $ra, 4($sp)
    addiu $sp, $sp, 8
    jr $ra

# Restore the dealer hole card's actual suit color.
reveal_hole_card:
    addiu $sp, $sp, -8
    sw $ra, 4($sp)
    li $a0, 1
    li $a1, 1
    la $t0, dealer_cards
    lw $a2, 4($t0)
    li $a3, 0
    jal paint_card_icon
    lw $ra, 4($sp)
    addiu $sp, $sp, 8
    jr $ra

# Display upcard, full hands, and results in Run I/O.
show_upcard:
    addiu $sp, $sp, -8
    sw $ra, 4($sp)
    li $v0, 4
    la $a0, up_label
    syscall
    lw $a0, dealer_cards
    jal print_card
    li $v0, 4
    la $a0, newline
    syscall
    lw $ra, 4($sp)
    addiu $sp, $sp, 8
    jr $ra

# $a0 seat 0=player/1=dealer.
show_hand:
    addiu $sp, $sp, -24
    sw $ra, 20($sp)
    sw $s0, 16($sp)
    sw $s1, 12($sp)
    sw $s2, 8($sp)
    sw $s3, 4($sp)
    beqz $a0, show_player
    la $s1, dealer_cards
    lw $s2, dealer_count
    lw $s3, dealer_total
    la $a0, dealer_label
    j show_label
show_player:
    la $s1, player_cards
    lw $s2, player_count
    lw $s3, player_total
    la $a0, player_label
show_label:
    li $v0, 4
    syscall
    li $s0, 0
show_card_loop:
    sll $t0, $s0, 2
    addu $t0, $t0, $s1
    lw $a0, 0($t0)
    jal print_card
    li $v0, 4
    la $a0, blank
    syscall
    addiu $s0, $s0, 1
    blt $s0, $s2, show_card_loop
    li $v0, 4
    la $a0, newline
    syscall
    # Select total label from the original hand array pointer.
    la $t0, dealer_cards
    beq $s1, $t0, show_dealer_total
    la $a0, player_score
    j show_total
show_dealer_total:
    la $a0, dealer_score
show_total:
    li $v0, 4
    syscall
    move $a0, $s3
    li $v0, 1
    syscall
    li $v0, 4
    la $a0, newline
    syscall
    lw $s3, 4($sp)
    lw $s2, 8($sp)
    lw $s1, 12($sp)
    lw $s0, 16($sp)
    lw $ra, 20($sp)
    addiu $sp, $sp, 24
    jr $ra

# $a0 card ID; print rank and suit, e.g. A-H or 10-S.
print_card:
    li $t7, 13
    div $a0, $t7
    mflo $t6                   # Suit
    mfhi $t5
    addiu $t5, $t5, 1         # Rank
    beq $t5, 1, print_ace
    beq $t5, 11, print_jack
    beq $t5, 12, print_queen
    beq $t5, 13, print_king
    move $a0, $t5
    li $v0, 1
    syscall
    j print_suit
print_ace:
    li $a0, 65
    j print_face
print_jack:
    li $a0, 74
    j print_face
print_queen:
    li $a0, 81
    j print_face
print_king:
    li $a0, 75
print_face:
    li $v0, 11
    syscall
print_suit:
    li $v0, 11
    li $a0, 45                 # Hyphen
    syscall
    li $a0, 83                 # S
    beqz $t6, print_suit_char
    li $a0, 72                 # H
    beq $t6, 1, print_suit_char
    li $a0, 68                 # D
    beq $t6, 2, print_suit_char
    li $a0, 67                 # C
print_suit_char:
    li $v0, 11
    syscall
    jr $ra

read_key:
    li $t0, 0xffff0000
wait_key:
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beqz $t1, wait_key
    lw $v0, 4($t0)
    jr $ra

# Clear all 16x16 pixels green, then draw separator white.
draw_table:
    la $t0, framebuffer
    li $t1, 0x00003300
    li $t2, 256
fill_table:
    sw $t1, 0($t0)
    addiu $t0, $t0, 4
    addiu $t2, $t2, -1
    bnez $t2, fill_table
    li $a0, 0x00FFFFFF
    j paint_result

# $a0 is color; draw row 7, columns 1..14.
paint_result:
    la $t0, framebuffer
    li $t1, 1
result_line:
    li $t2, 112
    addu $t2, $t2, $t1
    sll $t2, $t2, 2
    addu $t2, $t2, $t0
    sw $a0, 0($t2)
    addiu $t1, $t1, 1
    ble $t1, 14, result_line
    jr $ra

# $a0=x, $a1=y, $a2=color; one display unit.
plot_pixel:
    sll $t0, $a1, 4
    addu $t0, $t0, $a0
    sll $t0, $t0, 2
    la $t1, framebuffer
    addu $t0, $t0, $t1
    sw $a2, 0($t0)
    jr $ra

# $a0=x, $a1=y, $a2=color; 2x2 display-unit card icon.
draw_icon:
    la $t0, framebuffer
    sll $t1, $a1, 4
    addu $t1, $t1, $a0
    sll $t1, $t1, 2
    addu $t1, $t1, $t0
    sw $a2, 0($t1)
    sw $a2, 4($t1)
    sw $a2, 64($t1)
    sw $a2, 68($t1)
    jr $ra
