;
; Projeto da disciplina de Microcontroladores e Aplicações
; Aplicação de um relógio que conta com minutos e segundos usando display de 7 segmentos
; 07/04/2025 - Matheus Ryan, Lucas Heron, Rafael Luciano
;

; Definições para ATmega328P
.include "m328pdef.inc"

; Constantes
.equ DISPLAY_DEZENAS_PORT = PORTC
.equ DISPLAY_DEZENAS_DDR = DDRC
.equ DISPLAY_UNIDADES_PORT = PORTD
.equ DISPLAY_UNIDADES_DDR = DDRD

; Variáveis na SRAM
.dseg
count: .byte 1          ; Contador de segundos (0-59)
overflow_count: .byte 1 ; Contador de overflows para precisão

; Vetor de interrupção
.cseg
.org 0x0000
    jmp main            ; Reset Vector
.org OVF0addr          ; Timer0 Overflow Address
    jmp timer0_ovf_isr

; Tabela de conversão para display de 7 segmentos (cátodo comum)
.org 0x0100            ; Posiciona a tabela após os vetores de interrupção
segment_table:
    ; 0    1    2    3    4    5    6    7    8    9
    .db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

; Início do programa principal
.cseg
.org 0x0034            ; Posição após vetores de interrupção + espaço extra
main:
    ; Inicializa a pilha
    ldi r16, high(RAMEND)
    out SPH, r16
    ldi r16, low(RAMEND)
    out SPL, r16

    ; Configura portas como saída
    ldi r16, 0xFF
    out DISPLAY_DEZENAS_DDR, r16    ; PORTC toda como saída
    out DISPLAY_UNIDADES_DDR, r16   ; PORTD toda como saída

    ; Inicializa contadores
    clr r16
    sts count, r16
    sts overflow_count, r16
    call update_displays

    ; Configura Timer0 para interrupção a cada ~1/15s (para precisão de 1s)
    ldi r16, (1<<CS02)|(1<<CS00)  ; Prescaler 1024
    out TCCR0B, r16

    ldi r16, 0x06      ; Valor inicial para overflow em ~1/15s (256 - (16000000/1024/15))
    out TCNT0, r16

    ldi r16, (1<<TOIE0)   ; Habilita interrupção por overflow
    sts TIMSK0, r16

    ; Habilita interrupções globais
    sei

main_loop:
    rjmp main_loop

; Atualiza ambos os displays
update_displays:
    push r16
    push r17
    push r18
    push r30
    push r31

    lds r16, count
    
    ; Calcula dezenas (divide por 10)
    ldi r17, 10
    clr r18            ; r18 será as dezenas

calc_dezenas:
    cp r16, r17
    brlo show_dezenas   ; Se count < 10, vai mostrar
    sub r16, r17       ; Subtrai 10
    inc r18            ; Incrementa dezenas
    rjmp calc_dezenas

show_dezenas:
    ; Mostra dezenas (valor em r18)
    ldi ZL, low(segment_table<<1)
    ldi ZH, high(segment_table<<1)
    add ZL, r18
    adc ZH, r1
    lpm r17, Z
    out DISPLAY_DEZENAS_PORT, r17

    ; Mostra unidades (valor em r16)
    ldi ZL, low(segment_table<<1)
    ldi ZH, high(segment_table<<1)
    add ZL, r16
    adc ZH, r1
    lpm r17, Z
    out DISPLAY_UNIDADES_PORT, r17

    pop r31
    pop r30
    pop r18
    pop r17
    pop r16
    ret

; Interrupção do Timer0
timer0_ovf_isr:
    push r16
    push r17
    in r16, SREG
    push r16

    ; Reinicia o Timer0 com valor para ~1/15s
    ldi r16, 0x06
    out TCNT0, r16

    ; Incrementa contador de overflows
    lds r16, overflow_count
    inc r16
    cpi r16, 60    ; 15 overflows = 1 segundo
    brne no_second
    
    ; A cada 1 segundo real:
    clr r16            ; Zera contador de overflows
    lds r17, count     ; Incrementa contador de segundos
    inc r17
    cpi r17, 60
    brlo save_count
    clr r17            ; Reinicia após 59 segundos

save_count:
    sts count, r17
    call update_displays

no_second:
    sts overflow_count, r16

    pop r16
    out SREG, r16
    pop r17
    pop r16
    reti
