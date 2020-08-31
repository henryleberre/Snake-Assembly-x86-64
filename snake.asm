global main

%define WIDTH       30
%define HEIGHT      30
%define PIXEL_COUNT (WIDTH * HEIGHT)

extern system
extern snprintf

section .text

; Function "clear_terminal":
; - No Arguments
clear_terminal:
    sub rsp, 8 ; Prepare RSP For Function Call

    mov  rdi, SSTY_HIDE_USER_INPUT_CMD
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
    mov qword[rsp - 8],  rdx ; Save RDX
    mov qword[rsp],      rcx ; Save RCX

    call move_cursor_to_location      ; Move Terminal Cursor

    mov rdx, qword[rsp - 8] ; RDX (Argument 3): The String Buffer
    mov rcx, qword[rsp]     ; RCX (Argument 4): The String Length
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
    ; Main Prologue
    push rbp
    mov  rbp, rsp

    

    ; Main Epilogue
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
SSTY_HIDE_USER_INPUT_CMD: db  "stty -echo", 0
SSTY_SHOW_USER_INPUT_CMD: db  "ssty echo",  0
KEYBOARD_EVENT_FILE_PATH: db  "/dev/input/event10" ; Can Vary