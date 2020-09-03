; "main" is exported since I use (for now) LIBC functions
global main

; Define Constants
%define WIDTH                     30
%define HEIGHT                    30
%define PIXEL_COUNT               (WIDTH * HEIGHT)
%define SNAKE_BUFFER_SIZE         (PIXEL_COUNT * 2)
%define SNAKE_BUFFER_SIZE_ALIGNED (SNAKE_BUFFER_SIZE & 0xFFFFFFFFF0)

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

    ; Allocate Snake Buffer
    sub rsp, SNAKE_BUFFER_SIZE_ALIGNED
    mov byte[rsp + 0], 1 ; Head X Position
    mov byte[rsp + 1], 0 ; Head Y Position
    mov byte[rsp + 2], 0 ; Tail X Position
    mov byte[rsp + 3], 0 ; Tail Y Position

    mov qword[rbp - 12], rsp ; Save The Memory Address Of The Snake Buffer

game_loop_body:
    ; Sleep Until Next Iteration
    mov rdi, 1 ; s
    mov rsi, 0 ; ns
    call sleep_for

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
    shl   rax, 1             ; Double Snake Length (2 Bytes Per Snake Cell)
    snake_loop_body:
        ; Loop Backwards Through Snake
        cmp rax, 0
        jle snake_loop_end

        mov r8, qword[rbp - 12] ; Snake Buffer Pointer
        add r8, rax
;
        ;; Move Cell
        cmp rax, 2
        je move_snake_head_cell

        move_snake_generic_cell: ; Move Non Head Cell
            mov cl, byte[r8 - 4] ; New Cell X Position
            mov byte[r8 - 2], cl ; Store New X

            mov cl, byte[r8 - 3] ; New Cell Y Position
            mov byte[r8 - 1], cl ; Store New Y

        jmp snake_loop_body_continue

        move_snake_head_cell:    ; Move Head Cell
            mov cl, byte[r8 - 2] ; Fetch Cell X Position
            add cl, byte[rbp - 21]     ; Snake Head X Delta Movement
            mov byte[r8 - 2], cl ; Store New X

            mov cl, byte[r8 - 1] ; Fetch Cell Y Position
            add cl, byte[rbp - 22]     ; Snake Head Y Delta Movement
            mov byte[r8 - 1], cl ; Store New Y

        snake_loop_body_continue:
            ; Save RAX
            mov qword[rbp - 20], rax

            ; Print The Snake Cell
            movzx rdi, byte[r8 - 2] ; Cell X Position
            movzx rsi, byte[r8 - 1] ; Cell Y Position
            mov   rdx, SNAKE_CHAR
            mov   rcx, 1
            call  print_string_at_position

            ; Restore RAX
            mov rax, qword[rbp - 20]

            ; Loop Backwards Through Snake
            sub rax, 2 ; Remove 2 Bytes From RAX (One Snake Cell)
            jmp snake_loop_body

    snake_loop_end:
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
KEYBOARD_EVENT_FILE_PATH: db  "/dev/input/event10" ; Can Vary