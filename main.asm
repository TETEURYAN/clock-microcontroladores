; Projeto da disciplina de Microcontroladores e Aplicações
; Relógio digital com display de 7 segmentos para minutos e segundos
; Data: 07/04/2025


; ===================== CONSTANTES DE HARDWARE =====================
.equ PORT_BCD      = PORTB       ; PB0-PB3: Linhas de BCD para os 4 displays
.equ DDR_BCD       = DDRB
.equ PORT_CTRL     = PORTD       ; PD0-PD3: Controle de cada display (1 por vez)
.equ DDR_CTRL      = DDRD

; ===================== CONSTANTES DE TEMPORIZAÇÃO =================
.equ VALOR_INICIAL_TIMER = 256 - (160)  ; 100 interrupções/segundo
.equ NUMERO_OVERFLOWS    = 100          ; 100 interrupções = 1 segundo

; ===================== NOMES DE REGISTRADORES =====================
.def reg_temp      = r16
.def reg_dezenas   = r17
.def reg_unidades  = r18
.def reg_aux       = r19
.def reg_status    = r20
.def reg_display   = r21

; ===================== ALOCAÇÃO DE VARIÁVEIS ======================
.dseg
segundos:            .byte 1
minutos:             .byte 1
contador_overflow:   .byte 1

; ===================== VETORES DE INTERRUPÇÃO =====================
.cseg
.org 0x0000
    jmp inicio
.org OVF0addr
    jmp trata_overflow

; ===================== PROGRAMA PRINCIPAL =========================
.cseg
.org 0x0034
inicio:
    ; Inicializa pilha
    ldi reg_temp, high(RAMEND)
    out SPH, reg_temp
    ldi reg_temp, low(RAMEND)
    out SPL, reg_temp

    ; Configura portas como saída
    ldi reg_temp, 0x0F
    out DDR_BCD, reg_temp        ; PB0-PB3 como saída (BCD)
    out DDR_CTRL, reg_temp       ; PD0-PD3 como saída (controle de displays)

	; Configura PC0, PC1 e PC2 como entrada (botões) e PC3 como saída (buzzer)
    ldi reg_temp, 0b00001000     ; PC3 saída (buzzer)
    out DDRC, reg_temp           ; PC0-PC2 são entradas por padrão (0)

	; Ativa resistores de pull-up nos botões (PC0-PC2)
    ldi reg_temp, 0b00000111     ; PC0-PC2
    out PORTC, reg_temp

    ; Zera contadores
    clr reg_temp
    sts segundos, reg_temp
    sts minutos, reg_temp
    sts contador_overflow, reg_temp

    ; Configura Timer0
    ldi reg_temp, (1<<CS02)|(1<<CS00)  ; Prescaler de 1024
    out TCCR0B, reg_temp
    ldi reg_temp, VALOR_INICIAL_TIMER
    out TCNT0, reg_temp
    ldi reg_temp, (1<<TOIE0)           ; Habilita interrupção por overflow
    sts TIMSK0, reg_temp

    sei  ; Habilita interrupções globais

loop_principal:
    rcall atualiza_displays
    rjmp loop_principal

; ================= ROTINA: DIVISÃO POR 10 ========================
; Entrada: reg_temp = valor de 0 a 99
; Saída:  reg_dezenas = dezenas, reg_unidades = unidades
dividir_por_10:
    push reg_aux
    ldi reg_unidades, 10
    clr reg_dezenas
div_loop:
    cp reg_temp, reg_unidades
    brlo div_pronto
    sub reg_temp, reg_unidades
    inc reg_dezenas
    rjmp div_loop
div_pronto:
    mov reg_unidades, reg_temp  ; unidades
    pop reg_aux
    ret

; =============== ATUALIZAÇÃO DOS DISPLAYS ======================
atualiza_displays:
    push reg_temp
    push reg_dezenas
    push reg_unidades
    push reg_aux
    push reg_display
    push r22
    push r23
    push r24
    push r25

    ; ------ Lê minutos e segundos uma vez ------
    lds reg_temp, segundos
    rcall dividir_por_10
    mov r22, reg_unidades     ; Segundos unidade
    mov r23, reg_dezenas      ; Segundos dezena

    lds reg_temp, minutos
    rcall dividir_por_10
    mov r24, reg_unidades     ; Minutos unidade
    mov r25, reg_dezenas      ; Minutos dezena

    ; Display 0 - Segundo unidade (PD0)
    mov reg_temp, r22
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000001
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Display 1 - Segundo dezena (PD1)
    mov reg_temp, r23
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000010
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Display 2 - Minuto unidade (PD2)
    mov reg_temp, r24
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000100
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Display 3 - Minuto dezena (PD3)
    mov reg_temp, r25
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00001000
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Apaga todos os displays ao final
    clr reg_temp
    out PORT_CTRL, reg_temp

    pop r25
    pop r24
    pop r23
    pop r22
    pop reg_display
    pop reg_aux
    pop reg_unidades
    pop reg_dezenas
    pop reg_temp
    ret

; ============ ATRASO ENTRE TROCAS DE DISPLAY ============
atraso_display:
    ldi reg_aux, 40           ; Laço externo reduzido
loop_externo:
    ldi reg_display, 50       ; Laço interno reduzido
loop_interno:
    dec reg_display
    brne loop_interno
    dec reg_aux
    brne loop_externo
    ret

; ============ TRATAMENTO DE OVERFLOW ====================
trata_overflow:
    push reg_temp
    push reg_dezenas
    in reg_status, SREG
    push reg_status

    ; Reinicializa Timer
    ldi reg_temp, VALOR_INICIAL_TIMER
    out TCNT0, reg_temp

    ; Incrementa contador de overflow
    lds reg_temp, contador_overflow
    inc reg_temp
    sts contador_overflow, reg_temp
    cpi reg_temp, NUMERO_OVERFLOWS
    brne fim_overflow

    ; Zera contador de overflow
    clr reg_temp
    sts contador_overflow, reg_temp

    ; Incrementa segundos
    lds reg_dezenas, segundos
    inc reg_dezenas
    cpi reg_dezenas, 60
    brlo salva_seg

    ; Se passou de 59, zera segundos e incrementa minutos
    clr reg_dezenas
    lds reg_unidades, minutos
    inc reg_unidades
    cpi reg_unidades, 60
    brlo salva_min
    clr reg_unidades

salva_min:
    sts minutos, reg_unidades

salva_seg:
    sts segundos, reg_dezenas

fim_overflow:
    pop reg_status
    out SREG, reg_status
    pop reg_dezenas
    pop reg_temp
    reti