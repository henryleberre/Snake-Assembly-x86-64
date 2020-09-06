; "main" is exported since I use (for now) LIBC functions
global main

; Define Constants
%define WIDTH                     30
%define HEIGHT                    30
%define PIXEL_COUNT               (WIDTH * HEIGHT)
%define SNAKE_BUFFER_SIZE         (PIXEL_COUNT * 2)
%define SNAKE_BUFFER_SIZE_ALIGNED (SNAKE_BUFFER_SIZE & 0xFFFFFFFFF0)

%define O_RDONLY                  (0x0000)
%define O_NONBLOCK                (0x0004)
%define KEYBOARD_EVENT_FILE_FLAGS (O_RDONLY | O_NONBLOCK)

%define INPUT_EVENT_STRUCT_SIZE   (24)
%define INPUT_EVENT_BUFFER_LENGTH (100)
%define INPUT_EVENT_BUFFER_SIZE (INPUT_EVENT_STRUCT_SIZE * INPUT_EVENT_BUFFER_LENGTH)

%define POLLIN 0x001
%define EV_KEY 0x001

; External LIBC Functions (I try to use as less as possible here)
extern system
extern snprintf

section .text

; Function "hide_user_input":
; - No Arguments
hide_user_input:
    sub rsp, 8 ; Prepare RSP For Function Call

    mov rax, 1                    ; RAX (Argument 1): Syscall #1     : Write
    mov rdi, 1                    ; RDI (Argument 2): File Handle #1 : Stdout
    mov rsi, CLEAR_STDOUT_CMD     ; RSI (Argument 3): String Buffer
    mov rdx, CLEAR_STDOUT_CMD_LEN ; RDX (Argument 4): String Length
    syscall

    add rsp, 8  ; Restore RSP
    ret         ; Return

; Function "clear_terminal":
; - No Arguments
clear_terminal:
    sub rsp, 8 ; Prepare RSP For Function Call

    mov  rdi, STTY_HIDE_USER_INPUT_CMD
    call system

    add rsp, 8  ; Restore RSP
    ret         ; Return

; Function "show_user_input":
; - No Arguments
show_user_input:
    sub rsp, 8 ; Prepare RSP For Function Call

    mov  rdi, STTY_SHOW_USER_INPUT_CMD
    call system

    add rsp, 8  ; Restore RSP
    ret         ; Return

; Function "move_cursor_to_location"
; - Moves the text cursor the desired position
; - Arguments:
;   - RDI (Argument 1): X Position (Between 0 and 2^64 - 1) 
;   - RSI (Argument 2): Y Position (Between 0 and 2^64 - 1)
move_cursor_to_location:
    sub rsp, 24 ; Allocate Destination snprintf Buffer

    inc rdi
    inc rsi

    ; Create Format String To Move Cursor
    mov rcx, rsi             ; RCX (Argument 4): Y Position (For Format String)
    mov r8,  rdi             ; R8  (Argument 5): X Position (For Format String)
    mov rdi, rsp             ; RDI (Argument 1): Destination Buffer Pointer
    mov rsi, 24              ; RSI (Argument 2): Destination Buffer Length
    mov rdx, MOVE_CURSOR_CMD ; RDX (Argument 3): The C Format String
    call snprintf

    ; Print Move Cursor Commad
    mov rdx, rax ; RDX (Argument 4): Length
    mov rax, 1   ; RAX (Argument 1): Syscall #1     : Write
    mov rdi, 1   ; RDI (Argument 2): File Handle #1 : Stdout
    mov rsi, rsp ; RSI (Argument 3): char*
    syscall      ; Perform the syscall

    add rsp, 24 ; Free Temporary snprintf Destination Buffer
    ret         ; Return

; Function "print_string"
; - Prints the desired string
; - Arguments:
;   - RDI (Argument 1): The String Buffer
;   - RSI (Argument 2): The String Length
print_string:
    sub rsp, 8   ; Prepare The Stack

    mov rdx, rsi ; RDX (Argument 4): Length
    mov rsi, rdi ; RSI (Argument 3): char*
    mov rax, 1   ; RAX (Argument 1): Syscall #1     : Write
    mov rdi, 1   ; RDI (Argument 2): File Handle #1 : Stdout
    syscall      ; Perform the syscall

    add rsp, 8  ; Restore RSP
    ret         ; Return

; Function "print_string_at_position"
; - Prints the desired string at the desired location
; - Arguments:
;   - RDI (Argument 1): X Position (Between 0 and 2^64 - 1) 
;   - RSI (Argument 2): Y Position (Between 0 and 2^64 - 1)
;   - RDX (Argument 3): The String Buffer
;   - RCX (Argument 4): The String Length
print_string_at_position: ; x(0-->2^64-1), y0-2^64-1), char*, len
    ; Setup The Stack And Save Variables
    sub rsp, 24              ; Allocate Space (While Preparing The Stack)
    mov qword[rsp + 8],  rdx ; Save RDX
    mov qword[rsp],      rcx ; Save RCX

    call move_cursor_to_location      ; Move Terminal Cursor

    mov rdi, qword[rsp + 8] ; RDI (Argument 1): The String Buffer (From RDX)
    mov rsi, qword[rsp]     ; RSI (Argument 2): The String Length (From RCX)
    call print_string

    add rsp, 24 ; Restore RSP
    ret         ; Return

; Function "sleep_for"
; - Sleeps for the desired amount of time
; - Arguments:
;   - RDI (Argument 1): The amount of seconds     to sleep for
;   - RSI (Argument 2): The amount of nanoseconds to sleep for
sleep_for:
    ; Allocate the "timespec" structure (this also happens to prepare the stack)
    sub rsp, 8 ; (Room For 2 DWORDS)

    ; Fill the "timespec" structure
    mov dword[rsp],     edi ; The amount of seconds
    mov dword[rsp - 4], esi ; The amount of nanoseconds

    ; Call sys_nanosleep syscall
    mov rax, 35  ; RAX (Argument 1): Syscall #35: sys_nanosleep
    mov rdi, rsp ; RDI (Argument 2): req: pointer to struct timespec.
    xor rsi, rsi ; RSI (Argument 3): mem: struct timespec* (NULL here)
    syscall      ; Perform the syscall

    add rsp, 8 ; Restore RSP
    ret        ; Return

main:
main_prologue:
    push rbp
    mov  rbp, rsp

setup_terminal:
    call clear_terminal
    call hide_user_input

setup_initial_memory:
    ; Allocate Temporary Variables
    sub rsp, 64
    mov word [rbp - 2],  2 ; Snake Length
    mov byte [rbp - 3],  0 ; Apple X Position
    mov byte [rbp - 4],  0 ; Apple Y Position
    mov qword[rbp - 12], 0 ; Reserved For The Memory Address Of The Snake Buffer
    mov qword[rbp - 20], 0 ; Resorved For Saving A Register Value
    mov byte [rbp - 21], 1 ; Snake Head X Delta Position
    mov byte [rbp - 22], 0 ; Snake Head Y Delta Position
    ; --- unused bytes ---
    ; Allocate a struct pollfd
    mov word [rbp - 34], 0      ; (short) revents
    mov word [rbp - 36], POLLIN ; (short) events
    mov dword[rbp - 40], 0 ; (int) fd --> Reserved For The Keyboard File Descriptor

    ; Allocate Snake Buffer
    sub rsp, SNAKE_BUFFER_SIZE_ALIGNED
    mov byte[rsp + 0], 3 ; Head X Position
    mov byte[rsp + 1], 0 ; Head Y Position
    mov byte[rsp + 2], 0 ; Tail X Position
    mov byte[rsp + 3], 0 ; Tail Y Position

    mov qword[rbp - 12], rsp ; Save The Memory Address Of The Snake Buffer

open_keyboard_input_file:
    ; Open The Keyboard Event File
    mov rax, 2 ; sys_open
    mov rdi, KEYBOARD_EVENT_FILE_PATH  ; Filename ptr
    mov rsi, KEYBOARD_EVENT_FILE_FLAGS ; Flags
    mov rdx, 0
    syscall

    ; Save Keyboard File Descriptor
    mov dword[rbp - 40], eax

    ; TODO:: ERROR CHECKING

game_loop_body:
    read_keyboard_input:
        mov rax, 7        ; sys_poll
        lea rdi, [rbp - 40] ; Pointer To The pollfd structure
        mov rsi, 1        ; Number Of File Descriptors
        mov rdx, 100      ; Timeout (ms)
        syscall 

        cmp rax, 0
        je  game_loop_body_continue

        ; Read File
        sub rsp, INPUT_EVENT_BUFFER_SIZE ;

        mov   rax, 0 ; sys_read
        mov   edi, dword[rbp - 40]
        mov   rsi, rsp ; buffer
        mov   rdx, INPUT_EVENT_BUFFER_SIZE ; buffer length
        syscall

        ; Loop Through Every Single Input Event
        mov rdi, 0 ; current offset

        read_keyboard_input_loop_body:
            cmp rdi, rax
            jge read_keyboard_input_loop_end

            movzx rdx, word[rsp + 16] ; struct input_event -> type
            cmp   rdx, EV_KEY
            jne read_keyboard_input_loop_next

            movzx rdx, word[rsp + 18] ; struct input_event -> code
            cmp   rdx, 108
            jne read_keyboard_input_loop_next

            mov byte[rbp - 21], 0
            mov byte[rbp - 22], 1

            read_keyboard_input_loop_next:
                add rdi, INPUT_EVENT_STRUCT_SIZE

        read_keyboard_input_loop_end:        
            add rsp, INPUT_EVENT_BUFFER_SIZE

    game_loop_body_continue:
        ; Unrender tail
        mov   r8,  qword[rbp - 12] ; Snake Buffer Pointer
        movzx r9, word[rbp - 2]
        shl r9, 1
        movzx rdi, byte[r8 + r9 - 2] ; Cell X Position
        movzx rsi, byte[r8 + r9 - 1] ; Cell Y Position
        mov   rdx, EMPTY_CHAR
        mov   rcx, 1
        call  print_string_at_position
        
        ; Setup Loop Index
        movzx rax, word[rbp - 2] ; Snake Length
        sub   rax, 1             ; Snake Length - 1 (i.e the tail's index)

        snake_loop_body:
            ; Setup R8 To Point To The Memory Location Of The Current Cell's X Position
            mov r8, qword[rbp - 12] ; Snake Buffer Pointer
            shl rax, 1
            add r8, rax
            shr rax, 1

            ; Move Cell
            cmp rax, 0
            je move_snake_head_cell

            move_snake_generic_cell: ; Move Non Head Cell
                mov cl, byte[r8 - 2] ; New Cell X Position
                mov byte[r8], cl     ; Store New X

                mov cl, byte[r8 - 1] ; New Cell Y Position
                mov byte[r8 + 1], cl ; Store New Y

            jmp snake_loop_body_continue

            move_snake_head_cell: ; Move Head Cell
                mov cl, byte[r8]       ; Fetch Cell X Position
                add cl, byte[rbp - 21] ; Snake Head X Delta Movement
                mov byte[r8], cl       ; Store New X

                mov cl, byte[r8 + 1]   ; Fetch Cell Y Position
                add cl, byte[rbp - 22] ; Snake Head Y Delta Movement
                mov byte[r8 + 1], cl   ; Store New Y

            snake_loop_body_continue:
                ; Save RAX
                mov qword[rbp - 20], rax

                ; Print The Snake Cell
                movzx rdi, byte[r8]     ; Cell X Position
                movzx rsi, byte[r8 + 1] ; Cell Y Position
                mov   rdx, SNAKE_CHAR
                mov   rcx, 1
                call  print_string_at_position

                ; Restore RAX
                mov rax, qword[rbp - 20]

                ; End the loop if this was the last cell's index (i.e the head's)
                cmp rax, 0
                je  snake_loop_end

                ; Otherwise, continue to loop backwards through the snake
                sub rax, 1
                jmp snake_loop_body

        snake_loop_end:
            ; Sleep Until Next Iteration
            mov rdi, 1 ; s
            mov rsi, 0 ; ns
            call sleep_for

            jmp game_loop_body

game_loop_end:


restore_terminal:
    call clear_terminal
    call show_user_input

main_epilogue:
    mov rsp, rbp
    pop rbp

    mov rax, 0 ; Set Exit Code 0
    ret        ; Return

section .data

EMPTY_CHAR:               db  ' '
SNAKE_CHAR:               db  'O'
CLEAR_STDOUT_CMD:         db  27,"[H",27,"[2J"
CLEAR_STDOUT_CMD_LEN:     equ $-CLEAR_STDOUT_CMD
MOVE_CURSOR_CMD:          db  0x1B, "[%d;%df", 0
STTY_HIDE_USER_INPUT_CMD: db  "stty -echo", 0
STTY_SHOW_USER_INPUT_CMD: db  "stty echo",  0
KEYBOARD_EVENT_FILE_PATH: db  "/dev/input/event7", 0 ; Can Vary