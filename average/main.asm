; ==============================================================================
; Программа: average
; Назначение: Вычисляет среднее арифметическое разностей x[i] - y[i] для двух
;             массивов чисел из входного текстового файла.
; Формат вызова: ./average <имя_файла>
; Формат вывода:
;   <имя_файла>: <среднее арифметическое>
;   или при ошибке:
;   <имя_файла>: файл испорчен
; ==============================================================================

default rel

section .rodata
    str_colon_space     db ": "
    str_colon_space_len equ $ - str_colon_space
    str_newline         db 10
    msg_corrupted       db "файл испорчен", 10
    msg_corrupted_len   equ $ - msg_corrupted
    msg_usage           db "Использование: ./average <имя_файла>", 10
    msg_usage_len       equ $ - msg_usage

section .bss
    BUFFER_SIZE  equ 4194304    ; 4 МБ для содержимого входного файла
    MAX_ELEMENTS equ 524288     ; До 524288 64-битных чисел в одном массиве

    file_buffer  resb BUFFER_SIZE
    count_x      resq 1
    count_y      resq 1
    arr_x        resq MAX_ELEMENTS
    arr_y        resq MAX_ELEMENTS

section .text
    global _start

_start:
    ; Аргументы командной строки на стеке Linux x86_64:
    ; [rsp] = argc
    ; [rsp + 8] = argv[0]
    ; [rsp + 16] = argv[1]
    mov r12, [rsp]              ; r12 = argc
    cmp r12, 2
    jl .no_args

    mov r13, 1                  ; r13 = текущий индекс аргумента argv

.arg_loop:
    cmp r13, r12
    jge .exit_ok

    mov rdi, [rsp + 8 + r13 * 8] ; rdi = argv[r13] (имя файла)
    call process_file

    inc r13
    jmp .arg_loop

.exit_ok:
    mov rax, 60                 ; sys_exit
    xor rdi, rdi                ; status 0
    syscall

.no_args:
    mov rax, 1                  ; sys_write
    mov rdi, 2                  ; stderr
    lea rsi, [msg_usage]
    mov rdx, msg_usage_len
    syscall

    mov rax, 60                 ; sys_exit
    mov rdi, 1                  ; status 1
    syscall

; ==============================================================================
; process_file
; Вход: rdi = указатель на имя файла (null-terminated string)
; Обрабатывает один файл: читает, валидирует, считает разности и среднее.
; ==============================================================================
process_file:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r15, rdi                ; r15 = имя файла
    mov r14, -1                 ; r14 = дескриптор файла (-1 = не открыт)

    ; 1. Выводим имя файла: write(1, filename, strlen)
    xor rdx, rdx
.fn_len_loop:
    cmp byte [r15 + rdx], 0
    je .fn_len_done
    inc rdx
    jmp .fn_len_loop
.fn_len_done:
    mov rax, 1                  ; sys_write
    mov rdi, 1                  ; stdout
    mov rsi, r15
    syscall

    ; 2. Выводим двоеточие и пробел ": "
    mov rax, 1                  ; sys_write
    mov rdi, 1
    lea rsi, [str_colon_space]
    mov rdx, str_colon_space_len
    syscall

    ; 3. Открываем файл: sys_open(filename, O_RDONLY, 0)
    mov rax, 2                  ; sys_open
    mov rdi, r15                ; filename
    xor rsi, rsi                ; O_RDONLY = 0
    xor rdx, rdx                ; mode = 0
    syscall

    test rax, rax
    js .file_error              ; ошибка открытия (файл не найден и др.)
    mov r14, rax                ; r14 = fd

    ; 4. Читаем всё содержимое файла в file_buffer
    xor r13, r13                ; r13 = общее число прочитанных байт

.read_loop:
    mov rax, 0                  ; sys_read
    mov rdi, r14                ; fd
    lea rsi, [file_buffer + r13]
    mov rdx, BUFFER_SIZE
    sub rdx, r13
    jz .file_error              ; файл превышает допустимый размер буфера
    syscall

    test rax, rax
    js .file_error              ; ошибка чтения
    jz .read_done               ; EOF достигнут

    add r13, rax
    jmp .read_loop

.read_done:
    ; Закрываем дескриптор файла
    mov rax, 3                  ; sys_close
    mov rdi, r14
    syscall
    mov r14, -1

    ; Пустой файл считается испорченным
    test r13, r13
    jz .file_error

    ; 5. Разбираем строки массива
    lea rsi, [file_buffer]
    lea r8, [file_buffer + r13] ; r8 = конец прочитанных данных

    ; Разбор строки 1 (массив x)
    lea rdi, [arr_x]
    call parse_line
    cmp rax, 0
    jle .file_error
    mov [count_x], rax

    ; Разбор строки 2 (массив y)
    lea rdi, [arr_y]
    call parse_line
    cmp rax, 0
    jle .file_error
    mov [count_y], rax

    ; Проверяем равенство количества элементов в строках
    mov rax, [count_x]
    cmp rax, [count_y]
    jne .file_error

    ; Проверяем остаток файла: допускаются только пробельные символы и переносы
.check_trailing:
    cmp rsi, r8
    jge .calculate
    movzx eax, byte [rsi]
    cmp al, ' '
    je .skip_trailing
    cmp al, 9                   ; \t
    je .skip_trailing
    cmp al, 10                  ; \n
    je .skip_trailing
    cmp al, 13                  ; \r
    je .skip_trailing
    ; Наличие непустой 3-й строки или лишних символов -> ошибка
    jmp .file_error

.skip_trailing:
    inc rsi
    jmp .check_trailing

.calculate:
    ; 6. Вычисляем сумму разностей: sum += (x[i] - y[i])
    mov rcx, [count_x]          ; N элементов
    xor rbx, rbx                ; i = 0
    xor r12, r12                ; sum = 0

.calc_loop:
    cmp rbx, rcx
    jge .calc_done
    mov rax, [arr_x + rbx * 8]
    sub rax, [arr_y + rbx * 8]
    add r12, rax
    inc rbx
    jmp .calc_loop

.calc_done:
    ; 7. Среднее арифметическое: sum / N (целочисленное деление)
    mov rax, r12
    cqo
    idiv rcx                    ; rax = результат деления

    ; Выводим полученное число
    call print_int64

    ; Выводим символ переноса строки
    mov rax, 1
    mov rdi, 1
    lea rsi, [str_newline]
    mov rdx, 1
    syscall

    jmp .process_ret

.file_error:
    ; Если файл остался открытым, закрываем его
    cmp r14, -1
    je .print_corrupted
    mov rax, 3                  ; sys_close
    mov rdi, r14
    syscall
    mov r14, -1

.print_corrupted:
    ; Выводим "файл испорчен\n"
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_corrupted]
    mov rdx, msg_corrupted_len
    syscall

.process_ret:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ==============================================================================
; parse_line
; Вход:
;   rsi = текущий указатель в буфере
;   r8  = конец буфера
;   rdi = указатель на массив int64_t
; Выход:
;   rax = количество прочитанных чисел (> 0) или -1 при ошибке
;   rsi = обновленный указатель буфера
; ==============================================================================
parse_line:
    push rbx
    push r12
    push r13
    push r14
    push r15

    xor r9, r9                  ; r9 = count = 0

.skip_leading_spaces:
    cmp rsi, r8
    jge .error_empty

    movzx eax, byte [rsi]
    cmp al, ' '
    je .adv_leading
    cmp al, 9                   ; tab
    je .adv_leading
    jmp .check_start

.adv_leading:
    inc rsi
    jmp .skip_leading_spaces

.check_start:
    cmp al, 10                  ; LF
    je .error_empty
    cmp al, 13                  ; CR
    je .error_empty

.number_loop:
    cmp r9, MAX_ELEMENTS
    jge .error

    ; Парсим число со знаком (+ или -)
    xor r11, r11                ; r11 = sign (0 = pos, 1 = neg)
    cmp rsi, r8
    jge .error

    movzx eax, byte [rsi]
    cmp al, '-'
    jne .check_plus
    mov r11, 1
    inc rsi
    jmp .after_sign

.check_plus:
    cmp al, '+'
    jne .after_sign
    inc rsi

.after_sign:
    ; После знака обязательно должна быть цифра '0'..'9'
    cmp rsi, r8
    jge .error
    movzx eax, byte [rsi]
    cmp al, '0'
    jb .error
    cmp al, '9'
    ja .error

    xor r12, r12                ; r12 = аккумулятор числа

.digit_loop:
    cmp rsi, r8
    jge .digit_done
    movzx eax, byte [rsi]
    cmp al, '0'
    jb .digit_done
    cmp al, '9'
    ja .digit_done

    sub al, '0'
    movzx r10, al

    ; r12 = r12 * 10 + r10
    mov rax, r12
    mov rcx, 10
    mul rcx
    test rdx, rdx
    jnz .error                  ; переполнение
    add rax, r10
    jc .error                   ; переполнение
    test rax, rax
    js .check_sign_bit
    jmp .digit_ok

.check_sign_bit:
    mov r14, 0x8000000000000000
    cmp rax, r14
    jne .error
    test r11, r11
    jz .error

.digit_ok:
    mov r12, rax
    inc rsi
    jmp .digit_loop

.digit_done:
    test r11, r11
    jz .store_num
    neg r12

.store_num:
    mov [rdi + r9 * 8], r12
    inc r9

    ; Проверяем символ после числа
    cmp rsi, r8
    jge .at_eol

    movzx eax, byte [rsi]
    cmp al, ' '
    je .skip_spaces_after_num
    cmp al, 9
    je .skip_spaces_after_num
    cmp al, ','
    je .handle_comma
    cmp al, 10
    je .handle_lf
    cmp al, 13
    je .handle_cr
    jmp .error

.skip_spaces_after_num:
    inc rsi
    cmp rsi, r8
    jge .at_eol
    movzx eax, byte [rsi]
    cmp al, ' '
    je .skip_spaces_after_num
    cmp al, 9
    je .skip_spaces_after_num

    cmp al, ','
    je .handle_comma
    cmp al, 10
    je .handle_lf
    cmp al, 13
    je .handle_cr
    jmp .error

.handle_comma:
    inc rsi                     ; пропускаем запятую

.skip_spaces_after_comma:
    cmp rsi, r8
    jge .error                  ; висячая запятая перед EOF -> ошибка
    movzx eax, byte [rsi]
    cmp al, ' '
    je .adv_comma_space
    cmp al, 9
    je .adv_comma_space
    jmp .check_after_comma

.adv_comma_space:
    inc rsi
    jmp .skip_spaces_after_comma

.check_after_comma:
    cmp al, ','
    je .error                   ; две запятые подряд -> ошибка
    cmp al, 10
    je .error                   ; запятая перед концом строки -> ошибка
    cmp al, 13
    je .error
    jmp .number_loop

.handle_cr:
    inc rsi
    cmp rsi, r8
    jge .at_eol
    cmp byte [rsi], 10          ; если \r\n, пропускаем \n
    jne .at_eol
    inc rsi
    jmp .at_eol

.handle_lf:
    inc rsi
    jmp .at_eol

.at_eol:
    test r9, r9
    jz .error_empty
    mov rax, r9
    jmp .parse_ret

.error_empty:
.error:
    mov rax, -1

.parse_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ==============================================================================
; print_int64
; Вход: rax = знаковое 64-битное целое число
; Выводит его строковое представление в stdout.
; ==============================================================================
print_int64:
    push rbx
    push r12
    push r13
    push rbp

    sub rsp, 48                 ; локальный стек-буфер
    lea rsi, [rsp + 40]
    xor rcx, rcx                ; счетчик длины

    mov r12, rax
    test r12, r12
    jns .is_positive

    neg r12
    mov r13, 1                  ; флаг знака минус
    jmp .check_zero

.is_positive:
    xor r13, r13

.check_zero:
    test r12, r12
    jnz .digit_loop
    dec rsi
    mov byte [rsi], '0'
    inc rcx
    jmp .check_sign

.digit_loop:
    test r12, r12
    jz .check_sign

    xor rdx, rdx
    mov rax, r12
    mov rbx, 10
    div rbx                     ; rax = r12 / 10, rdx = r12 % 10
    mov r12, rax

    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc rcx
    jmp .digit_loop

.check_sign:
    test r13, r13
    jz .do_write
    dec rsi
    mov byte [rsi], '-'
    inc rcx

.do_write:
    mov rax, 1                  ; sys_write
    mov rdi, 1                  ; stdout
    mov rdx, rcx                ; длина строки
    syscall

    add rsp, 48
    pop rbp
    pop r13
    pop r12
    pop rbx
    ret
