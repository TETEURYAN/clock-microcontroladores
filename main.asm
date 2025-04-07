;
; Projeto da disciplina de Microcontroladores e Aplia��es
; Aplica��o de um rel�gio que conta com minutos e segundos usando display de 7 segmentos
;
; Created: 07/04/2025 10:58:51
; Author : Matheus
;


; Defini��es para ATmega328P
.include "m328pdef.inc"

; Constantes
.equ DISPLAY_DEZENAS_PORT = PORTC
.equ DISPLAY_DEZENAS_DDR = DDRC
.equ DISPLAY_UNIDADES_PORT = PORTD
.equ DISPLAY_UNIDADES_DDR = DDRD

; Vari�veis na SRAM
.dseg
count: .byte 1          ; Contador de segundos (0-59)

; Vetor de interrup��o
.cseg
.org 0x0000
    jmp main            ; Reset Vector
.org OVF0addr          ; Timer0 Overflow Address
    jmp timer0_ovf_isr

; Tabela de convers�o para display de 7 segmentos (c�todo comum)
.org 0x0100            ; Posiciona a tabela ap�s os vetores de interrup��o
segment_table:
    ; 0    1    2    3    4    5    6    7    8    9
    .db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

; In�cio do programa principal
.cseg
.org 0x0034            ; Posi��o ap�s vetores de interrup��o + espa�o extra
main:
    ; Inicializa a pilha
    ldi r16, high(RAMEND)
    out SPH, r16
    ldi r16, low(RAMEND)
    out SPL, r16

    ; Configura portas como sa�da
    ldi r16, 0xFF
    out DISPLAY_DEZENAS_DDR, r16    ; PORTC toda como sa�da
    out DISPLAY_UNIDADES_DDR, r16   ; PORTD toda como sa�da

    ; Inicializa contador
    clr r16
    sts count, r16
    call update_displays

    ; Configura Timer0 para interrup��o a cada 1s
    ldi r16, (1<<CS02)|(1<<CS00)  ; Prescaler 1024
    out TCCR0B, r16

    ldi r16, 100          ; 256 - (16MHz/1024/100Hz) ? 100
    out TCNT0, r16

    ldi r16, (1<<TOIE0)   ; Habilita interrup��o por overflow
    sts TIMSK0, r16

    ; Habilita interrup��es globais
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
    
    ; Calcula dezenas
    ldi r17, 10
    clr r18            ; r18 ser� as dezenas

calc_dezenas:
    subi r16, 10
    brmi show_dezenas
    inc r18
    rjmp calc_dezenas

show_dezenas:
    ; Carrega padr�o para display de dezenas
    ldi r30, low(segment_table<<1)
    ldi r31, high(segment_table<<1)
    add r30, r18
    adc r31, r1
    lpm r16, Z
    out DISPLAY_DEZENAS_PORT, r16

    ; Calcula unidades (valor corrigido est� em r16 + 10)
    subi r16, -10

show_unidades:
    ; Carrega padr�o para display de unidades
    ldi r30, low(segment_table<<1)
    ldi r31, high(segment_table<<1)
    add r30, r16
    adc r31, r1
    lpm r16, Z
    out DISPLAY_UNIDADES_PORT, r16

    pop r31
    pop r30
    pop r18
    pop r17
    pop r16
    ret

; Interrup��o do Timer0
timer0_ovf_isr:
    push r16
    push r17
    in r16, SREG
    push r16

    ; Reinicia o Timer0
    ldi r16, 100
    out TCNT0, r16

    ; Incrementa contador
    lds r16, count
    inc r16
    cpi r16, 60
    brlo save_count
    clr r16

save_count:
    sts count, r16
    call update_displays

    pop r16
    out SREG, r16
    pop r17
    pop r16
    reti