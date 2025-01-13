	// using Atmel microchip studios 7.0 AVR assembler
	.DEF rZero				= r0
	.DEF rSREG				= r1	// used to store SREG during interrupt
	.DEF rSnake_len			= r2	// this could have been used to inc rSnake_len, but snake length never incereases
	.DEF rMatrix			= r3	// <- safe to use outside of interrupt
	.DEF rADCSRA_start		= r4
	.DEF rJoy_input			= r5
	.DEF rRead_y			= r6	// ADMUX settings to read y-axis of joystick
	.DEF rRead_x			= r7
	.DEF rJoy_y				= r8	// raw joystick y input
	.DEF rJoy_X				= r9
	.DEF rJoy_y_max			= r10	// converted joystick y input
	.DEF rJoy_x_max			= r11
	.DEF rJoy_y_set			= r12	// joystick y conversion information
	.DEF rJoy_x_set			= r13

    .DEF rTemp0				= r16
	.DEF rTemp1				= r17
	.DEF rSnake_dir			= r18	// snake byte= 0b01011101 ->
	.DEF rSnake_new			= r19	// bit 7-6: 01 = non-viable direction (01 = right, 10 = left, 11 = up, 00 = down), ->
	.DEF rSnake				= r20	// bit 5-3: 011 = bit in matrix row (bit 3) , bit 2-0: 101 = row of matrix (matrix[5])
	.DEF rIncrease_pointer	= r21
	.DEF rIterations		= r22
    .DEF rIterations2		= r23
	.DEF rRow				= r24	// used unsafely in interrupt
	.DEF rTimer				= r25	// used unsafely in interrupt

	.EQU Update_interval	= 130	// how often snake should be updated
	.EQU ADMUX_settings		= 0b01100101
	.EQU ADCSRA_settings	= 0b11000111
	.EQU Read_joystick_x	= 0b01100101
	.EQU Read_joystick_y	= 0b01100100
	.EQU TCCR0B_prescale	= 0b00000011 // if lower pre-scale is used another overflow for rTimer is needed 
										 // (put rTimer as r15, put new overflow in rTimers place, and increment new timer everytime rTimer overflows)
.DSEG
     matrix:		.BYTE 8
     snake:			.BYTE 4

.CSEG
	// Interrupt vector table
.ORG 0x0000
     jmp init // Reset/start
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp 0
     jmp timer // Timer 0 overflow

	 //////////////////////////////////////////////////////////////////////////////
	 // init initializes settings for timer, ADC, DDR, applyies values to registers, loads a snake, activates interrupts, and starts the game loop.
	 // Assumes snake and matrix not to be within 8 bytes of YL overflow. subroutines are not made with safety in mind, some of them rely on result of previous.
init:
	// Set the stack pointer to the highest memory adress
	ldi rTemp0, HIGH(RAMEND)
	out SPH, rTemp0
	ldi rTemp0, LOW(RAMEND)
	out SPL, rTemp0

	// Set input/output for PORT pins
	ldi rTemp0, 0b00111111	
	out DDRB, rTemp0		
	ldi rTemp0, 0b00001111	
	out DDRC, rTemp0			
	ldi rTemp0, 0b11111100	
	out DDRD, rTemp0	

	// Load a snake, set it's length, and load the head into rSnake
	ldi YH, HIGH(snake)
	ldi YL, LOW(snake)
	ldi rTemp0, 0b01011100
	st Y+, rTemp0
	mov rSnake, rTemp0
	ldi rTemp0, 0b00011011
	st Y+, rTemp0
	ldi rTemp0, 0b00010011
	st Y+, rTemp0
	ldi rTemp0, 0b00010010
	st Y, rTemp0
	ldi rTemp0, 4
	mov rSnake_len, rTemp0

	// load ADC for the josytick
	ldi rTemp0, ADMUX_settings	; start with reading X value
	sts ADMUX, rTemp0			
	ldi rTemp0, ADCSRA_settings		
	sts ADCSRA, rTemp0			

	// applying values to special registers
	mov rADCSRA_start, rTemp0	; saving ADCSRA config to register, config to start conversion
	ldi rTemp0, Read_joystick_x		
	mov rRead_x, rTemp0			; saving ADMUX configuration to read joystick x value
	ldi rTemp0, Read_joystick_y
	mov rRead_y, rTemp0			; saving ADMUX configuration to read joystick y value

	// setting up timer
	ldi rTemp0, TCCR0B_prescale	; pre-scaling, bits 011 looks the best
	out TCCR0B, rTemp0			
	lds rTemp0, TIMSK0			
	ori rTemp0, (1<<TOIE0)		; sets bit TOIE0, once set timer can interrupt
	sts	TIMSK0, rTemp0			

	rcall draw_snake			; draw first snake image
	sei							; enable interrupts
	rjmp loop					; start game loop

	/////////////////////////////////////////////////////////////////////////////////////
	// the game loop, fetches joystick values if possible, and updates snake when interval is reached
	// if snake updates, then draws snake, and reset the snake update interval
loop:
	rcall get_input					; get joystick input
	cpi rTimer, Update_interval		; compare rTimer with Update_interval
	brbs 0, loop				; loop if Update_interval is greater than rTimer
	rcall update_snake				; if rTimer is equal or greater than Update_interval, update snake
	rcall draw_snake				; draw snake onto matrix
	clr rTimer						; reset the rTimer, for next snake update
	rjmp loop						; repeat loop

	////////////////////////////////////////////////////////////////////////////////////
	// gets input from joystick, and places the values in registers rJoy_y or rJoy_x
get_input: 
	lds rTemp0, ADCSRA		; Check if conversion is complete
	sbrc rTemp0, 6			; return if ADCSRA completion isn't set (not complete)
	ret

	lds rTemp0, ADCH			; load ADCH, this will have the 8 bit value for direction.
	sbrs rJoy_input, 0			; go to update_joy_x if the marker bit 0 is clear, otherwise update_joy_y
	rjmp update_joy_x
update_joy_y:
	mov rJoy_y, rTemp0			; copy joy value into register rJoy_y
	sts ADMUX, rRead_x			; load in config for ADC to read x value next
	inc rJoy_input				; increment register rJoy_input so that it'll contain a 1 in bit 0 next time
	rjmp input_finish
update_joy_x:
	mov rJoy_x, rTemp0			; same as joy_y, but for x axis
	sts ADMUX, rRead_y
	dec rJoy_input
input_finish:
	sts ADCSRA, rADCSRA_start	; load ADCSRA config to start a new conversion
	ret

	////////////////////////////////////////////////////////////////////////////////////
	// updates snake, fetches max values of jostick for x and y, and marks if the value is large enough
	// checks the highest joystick value, and attempts to move in the direction,
	// if it can't it'll try in 2nd highest joystick value, if still no match it'll move snake in previous direction
	// moves the snake bytes in array, and appends a new snake byte at the top (index 0)
update_snake:
	mov rTemp0, rJoy_y		; prepare to call get_joy_max
	rcall get_joy_max		; get joy max values
	mov rJoy_y_max, rTemp0	; copy data over to relevant registers
	mov rJoy_y_set, rTemp1
	
	mov rTemp0, rJoy_x		; repeat above, but for x value
	rcall get_joy_max		
	mov rJoy_x_max, rTemp0	
	mov rJoy_x_set, rTemp1

	push rSnake			; rSnake still has the previously updated rSnake value, no need to reload, but this one needs to be saved
		clr rSnake_dir	; clear rSnake_dir, compares byte value in future operations
		lsl rSnake
		rol rSnake_dir
		lsl rSnake
		rol rSnake_dir	; push the left 2 most bits, signifying previous direction, into register rSnake_dir
	pop rSnake			; restore rSnake

	cp rJoy_x_max, rJoy_y_max		; see if Y is higher than X
	brbs 0, y_highest			; if y is higher we'll go to set_y_highest, which will try to generate snake on Y axis
	rjmp x_highest				; if x is higer we'll go to set_x_highest, which will try to generate snake on X axis

movement_done:
	rcall snake_follow				; move all snake byte 1 step down in the array. Y will be set at the first of Snake array.
	st Y, rSnake_new					; store new snake byte into the snake array
	mov rSnake, rSnake_new
	ret

	////////////////////////////////////////////////////////////////////////////////////////////
	// translates the joystick value into a positive number, marks up/left or down/right and if min value exceeded
	// if value is too low, the joystick value is saved as 0, clears bit for min value exceeded (didn't exceed)
	// takes value from rTemp0, and outputs value in rTemp0 and rTemp1
get_joy_max:
	cpi rTemp0, 192
	brbc 0, joy_greater		; if joystick value is greater than 192, set bits to mark it as up/left
	cpi rTemp0, 64
	brbc 0, joy_return		; if joystick value is greater than 64, mark it as being in the dead zone, go to joy_return
joy_smaller:				; if joystick value is smaller than 64, set bits to mark it as down/right value, and make them positive
	ldi rTemp1, 255			
	sub rTemp1, rTemp0		; set a new value as 255, and then remove the joystick value, this will yield a positive value
	mov rTemp0, rTemp1
	ldi rTemp1, 0b00000010	; set bits signifying direction of down/right and josytick is active
	ret
joy_greater:
	ldi rTemp1, 0b00000011	; set bits signifying direction of up/left and josytick is active
	ret
joy_return:					; min value wasn't exceeded, give josytick value 0, and mark it as inactive
	ldi rTemp0, 0
	ldi rTemp1, 0
	ret

	////////////////////////////////////////////////////////////////////////////////////////////
	// test which direction for the specified axis the player wants to move, and tests if it's possible
	// the result will be either the most prefered direction, 2nd most prefered direction, or the previous if no input is given
y_highest:
	sbrs rJoy_y_set, 1		; check if joystick is marked as active, if it's not active use previous direction
	rjmp use_prev
	sbrc rJoy_y_set, 0		; checks if joystick is pointed up or down, it must be either or.
	rjmp check_up
	sbrs rJoy_y_set, 0
	rjmp check_down

x_highest:
	sbrs rJoy_x_set, 1		; this does the same as previous, but for the x axis
	rjmp use_prev
	sbrc rJoy_x_set, 0
	rjmp check_left
	sbrs rJoy_x_set, 0
	rjmp check_right

	///////////////////////////////////////////////////////////////////////////////////////////////
	// tests the prefered directions, if prefered direction isn't possible, it'll go to test 2nd most prefered direction
check_up:
	cpi rSnake_dir, 3		; value up direction is 3, if the direction flag (direction we CAN'T go in) ->
	brbs 1, x_highest		; is 3 that means we can't go up, and we'll have to go to x_value instead

	// shifting bits to generate a new snake byte for the qualified prefered direction
	clr rSnake_new				; clear register rSnake_new
	ldi rIterations, 3			; shift 3 bits into new snake
	rcall shift_snake_bits

	dec rSnake_new				; decrement, down is up, modifying the NEW snake
	ldi rIterations, 3			; shift the modified 3 bits into new snake, but setting rIterations to 3 for 3 iterations
	rcall shift_snake_bits

	ldi rSnake, 0				; 0 is down (we CAN'T go DOWN next time, since we WENT UP)
	ldi rIterations, 2			; shift 2 modified direction bits into new snake
	rcall shift_snake_bits
	rjmp movement_done

check_down:
	cpi rSnake_dir, 0		; same as previous, but for the down direction
	brbs 1, x_highest

	ori rSnake_new, 0xFF		
	ldi rIterations, 3			
	rcall shift_snake_bits

	inc rSnake_new				; decrement, up is down
	ldi rIterations, 3			; shift 3 bits into new snake
	rcall shift_snake_bits

	ldi rSnake, 3		
	ldi rIterations, 2		
	rcall shift_snake_bits
	rjmp movement_done

check_right:
	cpi rSnake_dir, 1		; same as previous, but for the right direction
	brbs 1, y_highest

	ldi rIterations, 3	
	rcall shift_snake_bits

	andi rSnake, 0b00000111		; mask the row bits so that decrment yields desired value
	dec rSnake					; decrement, right is lower value, modifying OLD snake
	ldi rIterations, 3			
	rcall shift_snake_bits

	ldi rSnake, 2
	ldi rIterations, 2
	rcall shift_snake_bits
	rjmp movement_done

check_left:
	cpi rSnake_dir, 2		; same as previous, but for the right direction
	brbs 1, y_highest

	ldi rIterations, 3			
	rcall shift_snake_bits

	andi rSnake, 0b00000111		; mask the row bits so that increment yields desired value
	inc rSnake					; increment, left is higher value
	ldi rIterations, 3			
	rcall shift_snake_bits

	ldi rSnake, 1
	ldi rIterations, 2	
	rcall shift_snake_bits
	rjmp movement_done

use_prev:	// if no qualified input was given, the previus direction is chosen for the new snake byte
prev_up:
	cpi rSnake_dir, 0			; check if direction is 0, if it is go to check_up (will complete)
	brbc 1, prev_down
	rjmp check_up
prev_down:
	cpi rSnake_dir, 3			; check if direction is 3, if it is go to check_down (will complete)
	brbc 1, prev_right
	rjmp check_down
prev_right:
	cpi rSnake_dir, 2			; check if direction is 2, if it is go to check_right (will complete)
	brbc 1, prev_left
	rjmp check_right
prev_left:
	rjmp check_left				; only possible remaining direction is left

	////////////////////////////////////////////////////////////////////////////////////////
	// shifts the bits from register rSnake, into register rSnake_new. rIterations has to be set to a unsigned postive value.
shift_snake_bits:
	lsr rSnake				; shift rSnake to the right, the lost LSB goes into carry
	ror rSnake_new			; shift rSnake_new to the right, and insert the previous carry MSB
	dec rIterations		; decrement rIterations
	brne shift_snake_bits	; if rIterations2 is not 0, loop again
	ret

	////////////////////////////////////////////////////////////////////////////////////////
	// pushes all elements of snake array down 1 step (increases in index), the last one is overwritten. Assumes 2 or more snake bytes
snake_follow:
	ldi YH, HIGH(snake)			; load address of snake into Y
	ldi YL, LOW(snake)
	mov rIterations, rSnake_len	; copy rSnake_len into rIterations; keeps track of iterations
	dec rIterations				; decrement rIterations, since we don't want to move the last snake byte
	add YL, rIterations			; increase address of snake array by number of iterations (2nd last value)

	// this will go one step back (closer to first) in array, copy value, and paste it into the next element (closer to the end)
snake_follow_loop:
	dec YL						; decrease snake pointer (risk of overflow)
	ld rSnake, Y+				; load value of snake pointer (this is "up" one in array) into rTemp0, and increment snake pointer (goes closer to the end)
	st Y, rSnake				; store rTemp0 (snake body 1 closer to head) into snake pointer
	dec YL						; decrement snake pointer, after last iteration pointer will be at snake[0]
	dec rIterations				; decrement rIterations by 1
	brne snake_follow_loop		; if rIterations is not 0, repeat process
	ret

	/////////////////////////////////////////////////////////////////////////////////////////
	// sets correct bit in correct matrix from a snake byte (this one is hard to follow) 
	// e.g 0b10110010 - bit 7-6 past direction, bit 5-3 row position in matrix, bit 2-0 which matrix row
draw_snake:
	rcall clear_matrix		; clearing display
	mov rIterations, rSnake_len	; rIterations is how many times this needs to iterate, once for each snake byte

draw_snake_piece_loop:
	ld rIncrease_pointer, Y+		; Loading top snake byte into rIncrease_pointer and moves pointer up. Y is already set to the top snake byte (snake_follow) 
	mov rIterations2, rIncrease_pointer ; copying snake byte to rIterations2 , will be used to find the specified bit in matrix row

	lsr rIterations2				; rIterations2 contains the byte value of how many steps to the left the snake is at
	lsr rIterations2				; right shifting to remove the first 3 bits (matrix row), the resulting 3 bits tells where snake byte is on X axis
	lsr rIterations2
	andi rIterations2, 0b00000111	; masking to only keep the right most 3 bits, this byte now equals the bit position in matrix row, the X axis

	// rIncrease_pointer contains how many rows down from the top the snake byte is located at, the snake byte Y axis position
	andi rIncrease_pointer, 0b00000111		; rIncrease_pointer contains full snake byte, need to reset all bits but the first 3 bits to get matrix row count
	ldi ZH, HIGH(matrix)					; the lost 2 bits (non-viable direction bits) do not matter
	ldi ZL, LOW(matrix)
	add ZL, rIncrease_pointer		; add the number of bytes to increase address of matrix (further down on the screen). slight chance of YL going out of bounds

	ld rMatrix, Z				; already existing matrix row is copied and preserved in rMatrix
	ldi rTemp0, 0b00000001		; preparing a mask to set bit in rTemp0, this bit will later be inserted into the matrix row
snake_set_bit_loop:
	cpi rIterations2, 0			; rIterations2 contains how many steps to the left the bit in rTemp0 has to be shifted to the left
	breq snake_set				; stop iterating if rIterations2 is 0, meaning the bit in rTemp0 is in the correct position
	lsl rTemp0					; shift mask once to left
	dec rIterations2			
	rjmp snake_set_bit_loop		; decrement rIterations2 and loop
snake_set:
	or rMatrix, rTemp0			; or new snake bit into the preserved matrix row
	st Z, rMatrix				; store the new matrix row
	dec rIterations
	brne draw_snake_piece_loop		; iterate if there are more snake bytes to draw
	ret

	//////////////////////////////////////////////////////////////////////////////////////
	// clears the matrix, fills every matrix byte with 0
clear_matrix:
	ldi YH, HIGH(matrix)	; load matrix to Y
	ldi YL, LOW(matrix)	
	st Y+, rZero			; store 0 into matrix, increase matrix address
	st Y+, rZero
	st Y+, rZero
	st Y+, rZero
	st Y+, rZero
	st Y+, rZero
	st Y+, rZero
	st Y+, rZero
	ret

	///////////////////////////////////////////////////////////////////
	// runs on timer_overflow interrupt.
	// increases register rTimer, keeping track of how many overflow's have occured, used to know when to update snake
	// draws the matrix on the LED display. uses rjmp to save on a few cycles, since this is an interrupt.
timer:					
	in rSREG, SREG				; save the status register, since it'll otherwise cause issues with ongoing operations
	push YH
	push YL
	push rMatrix
		inc rTimer				; increment register rTimer
		rjmp draw_display		; draw the LED display
display_drawn:
	pop rMatrix
	pop YL
	pop YH
	out SREG, rSREG //*/		; restore status register
	reti						; return from interrupt, and set interrupt flag

	/////////////////////////////////////////////////////////////////////////////
	// handles the logic to draw the display, draws one line of the LED display at a time
	// translates a row in the matrix corresponding to the row in the LED display to be drawn
draw_display:
	inc rRow					; increment row
	sbrc rRow, 3				; skip the next instruction if rRow isn't 8
	clr rRow					; if it is, set rRow to 0
				
	ldi YH, HIGH(matrix)		; load matrix row into rMatrix
	ldi YL, LOW(matrix)			; load the corresponding matrix row, by adding rRow to address, into rMatrix register
	add YL, rRow				; slight risk of going out of bounds, causing a missread
	ld rMatrix, Y
	
	out PORTD, rZero			; clear PORT pins responsible for columns, some pins for rows are also reset
	out PORTB, rZero			; clear the whole of PORTB and PORTD

	// find which row PORT pins that should be turned off and on
	cpi rRow, 1					; checks if current row to draw is 1
	breq row_1					; if it is go to row_1, otherwise try next
	cpi rRow, 2					; repeat
	breq row_2	
	cpi rRow, 3
	breq row_3
	cpi rRow, 4
	breq row_4
	cpi rRow, 5
	breq row_5
	cpi rRow, 6
	breq row_6
	cpi rRow, 7
	breq row_7

row_0:							; if rRow was not 7, that means it must be 0
	sbi PORTC, 0				; set bit for current rRow PORT pin
	rjmp set_col				; row is done, jump to set column
row_1:
	cbi PORTC, 0				; turn off previous pin in PORTC
	sbi PORTC, 1				; turn on the row in PORTC
	rjmp set_col
row_2:
	cbi PORTC, 1				; repeat
	sbi PORTC, 2
	rjmp set_col
row_3:
	cbi PORTC, 2
	sbi PORTC, 3
	rjmp set_col
row_4:
	cbi PORTC, 3
	sbi PORTD, 2
	rjmp set_col
row_5:
	sbi PORTD, 3				; does not need to turn off prevoius port, because PORTD was already cleared
	rjmp set_col
row_6:
	sbi PORTD, 4
	rjmp set_col
row_7:
	sbi PORTD, 5

set_col: // translate matrix row to pins/bits of respective PORT
	sbrc rMatrix, 7			; skip if bit 7 in rMatrix is clear
	sbi PORTD, 6			; if bit 7 in rMatrix is set, set pin/bit 6 in PORTD
	sbrc rMatrix, 6			; repeat
	sbi PORTD, 7
	sbrc rMatrix, 5
	sbi PORTB, 0
	sbrc rMatrix, 4
	sbi PORTB, 1
	sbrc rMatrix, 3
	sbi PORTB, 2
	sbrc rMatrix, 2
	sbi PORTB, 3
	sbrc rMatrix, 1
	sbi PORTB, 4
	sbrc rMatrix, 0
	sbi PORTB, 5
	rjmp display_drawn