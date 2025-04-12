; Projeto da disciplina de Microcontroladores e Aplicações
; Relógio digital com display de 7 segmentos para minutos e segundos
; Data: 07/04/2025
; ===================== CONSTANTES DE HARDWARE =====================
.equ PORT_BCD       = PORTB       ; PB0-PB3: Linhas BCD
.equ DDR_BCD        = DDRB
.equ PORT_CTRL      = PORTD       ; PD0-PD3: Controle dos displays
.equ DDR_CTRL       = DDRD

.equ DDRC_ADDR      = 0x27        ; Endereço do registrador DDRC
.equ PINC_ADDR      = 0x26        ; Endereço do registrador PINC
.equ PORTC_ADDR     = 0x28        ; Endereço do registrador PORTC

; ===================== CONSTANTES DE BOTÕES =======================
.equ BOTAO_MODE     = 2           ; PC2
.equ BOTAO_START    = 1           ; PC1
.equ BUZZER_BIT     = 3           ; PC3

; ===================== CONSTANTES DE MODOS ========================
.equ MODO_RELOGIO   = 0
.equ MODO_CRONOMETRO = 1

; ===================== CONSTANTES DE TEMPORIZAÇÃO =================
.equ VALOR_INICIAL_TIMER = 256 - 160
.equ NUMERO_OVERFLOWS    = 100

; ===================== NOMES DE REGISTRADORES =====================
.def reg_temp       = r16
.def reg_dezenas    = r17
.def reg_unidades   = r18
.def reg_aux        = r19
.def reg_status     = r20
.def reg_display    = r21

; ===================== VARIÁVEIS EM MEMÓRIA =======================
.dseg
segundos_relogio:       .byte 1
minutos_relogio:        .byte 1
segundos_cronometro:    .byte 1
minutos_cronometro:     .byte 1
contador_overflow:      .byte 1
modo_atual:             .byte 1
cronometro_ativo:       .byte 1

; ===================== VETORES DE INTERRUPÇÃO =====================
.cseg
.org 0x0000
    jmp inicio
.org OVF0addr
    jmp trata_overflow

; ===================== PROGRAMA PRINCIPAL =========================
.org 0x0034
inicio:
    ; Inicializa pilha
    ldi reg_temp, high(RAMEND)
    out SPH, reg_temp
    ldi reg_temp, low(RAMEND)
    out SPL, reg_temp

    ; Inicializa portas
    ldi reg_temp, 0x0F
    out DDR_BCD, reg_temp
    out DDR_CTRL, reg_temp

    ; Configura PC1 como entrada, PC2 como entrada, PC3 como saída (buzzer)
    lds reg_temp, DDRC_ADDR
    andi reg_temp, ~(1 << BOTAO_MODE)
    andi reg_temp, ~(1 << BOTAO_START)
    ori reg_temp, (1 << BUZZER_BIT)
    sts DDRC_ADDR, reg_temp

    ; Habilita pull-up para botões
    lds reg_temp, PORTC_ADDR
    ori reg_temp, (1 << BOTAO_MODE) | (1 << BOTAO_START)
    sts PORTC_ADDR, reg_temp

    ; Zera contadores e modo
    clr reg_temp
    sts segundos_relogio, reg_temp
    sts minutos_relogio, reg_temp
    sts segundos_cronometro, reg_temp
    sts minutos_cronometro, reg_temp
    sts contador_overflow, reg_temp
    sts modo_atual, reg_temp
    sts cronometro_ativo, reg_temp

    ; Configura timer
    ldi reg_temp, (1<<CS02)|(1<<CS00)
    out TCCR0B, reg_temp
    ldi reg_temp, VALOR_INICIAL_TIMER
    out TCNT0, reg_temp
    ldi reg_temp, (1<<TOIE0)
    sts TIMSK0, reg_temp

    sei

loop_principal:
    rcall verifica_botoes
    rcall atualiza_displays
    rjmp loop_principal

; ===================== VERIFICAÇÃO DE BOTÕES ======================
verifica_botoes:
    push reg_temp
    push reg_aux

    ; Lê PINC
	;rcall debounce
    lds reg_temp, PINC_ADDR

    ; Verifica botão MODE (PC2)
    sbrs reg_temp, BOTAO_MODE
    rcall alternar_modo

    ; Verifica botão START (PC1)
    sbrs reg_temp, BOTAO_START
    rcall iniciar_cronometro

    pop reg_aux
    pop reg_temp
    ret

alternar_modo:
	rcall debounce
    lds reg_temp, modo_atual
	ldi reg_aux, 0x01
	eor reg_temp, reg_aux
    sts modo_atual, reg_temp

    ; Zera cronômetro ao entrar
    cpi reg_temp, MODO_CRONOMETRO
    brne modo_relogio_voltar

    clr reg_aux
    sts segundos_cronometro, reg_aux
    sts minutos_cronometro, reg_aux
    sts cronometro_ativo, reg_aux

modo_relogio_voltar:
    rcall apitar_buzzer
    ret

iniciar_cronometro:
	rcall debounce
    lds reg_temp, modo_atual
    cpi reg_temp, MODO_CRONOMETRO
    brne sair_start

    ; Ativa contagem do cronômetro
	lds reg_temp, cronometro_ativo 
    ldi reg_aux, 1
	eor reg_temp, reg_aux
    sts cronometro_ativo, reg_temp
    rcall apitar_buzzer

sair_start:
    ret

apitar_buzzer:
    push reg_temp
    lds reg_temp, PORTC_ADDR
    ori reg_temp, (1 << BUZZER_BIT)
    sts PORTC_ADDR, reg_temp

    ldi reg_temp, 50
espera_buzzer:
    dec reg_temp
    brne espera_buzzer

    lds reg_temp, PORTC_ADDR
    andi reg_temp, ~(1 << BUZZER_BIT)
    sts PORTC_ADDR, reg_temp
    pop reg_temp
    ret

debounce:
  ;           clock(MHz)   delay(ms)
  ;               v           v
  ldi r31, byte3(16 * 1000 * 150 / 5)
  ldi r30, high (16 * 1000 * 150 / 5)
  ldi r29, low  (16 * 1000 * 150 / 5)

  subi r29, 1
  sbci r30, 0
  sbci r31, 0
  brcc pc-3

  ret
; ===================== ATUALIZAÇÃO DOS DISPLAYS ===================
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

    ; Escolhe entre relógio ou cronômetro
    lds reg_temp, modo_atual
    cpi reg_temp, MODO_RELOGIO
    breq usa_relogio

    ; Cronômetro
    lds reg_temp, segundos_cronometro
    rcall dividir_por_10
    mov r22, reg_unidades
    mov r23, reg_dezenas

    lds reg_temp, minutos_cronometro
    rcall dividir_por_10
    mov r24, reg_unidades
    mov r25, reg_dezenas
    rjmp mostra

usa_relogio:
    lds reg_temp, segundos_relogio
    rcall dividir_por_10
    mov r22, reg_unidades
    mov r23, reg_dezenas

    lds reg_temp, minutos_relogio
    rcall dividir_por_10
    mov r24, reg_unidades
    mov r25, reg_dezenas

mostra:
    ; Mostra os 4 displays (unidade/decimal seg e min)
    mov reg_temp, r22
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000001
    out PORT_CTRL, reg_temp
    rcall atraso_display

    mov reg_temp, r23
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000010
    out PORT_CTRL, reg_temp
    rcall atraso_display

    mov reg_temp, r24
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000100
    out PORT_CTRL, reg_temp
    rcall atraso_display

    mov reg_temp, r25
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00001000
    out PORT_CTRL, reg_temp
    rcall atraso_display

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

; ===================== DIVISÃO POR 10 ============================
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
    mov reg_unidades, reg_temp
    pop reg_aux
    ret

; ===================== ATRASO DE DISPLAY ========================
atraso_display:
    ldi reg_aux, 20
loop_externo:
    ldi reg_display, 60
loop_interno:
    dec reg_display
    brne loop_interno
    dec reg_aux
    brne loop_externo
    ret

; ===================== TRATAMENTO DE OVERFLOW ===================
trata_overflow:
    push reg_temp
    push reg_dezenas
    in reg_status, SREG
    push reg_status

    ldi reg_temp, VALOR_INICIAL_TIMER
    out TCNT0, reg_temp

    lds reg_temp, contador_overflow
    inc reg_temp
    sts contador_overflow, reg_temp
    cpi reg_temp, NUMERO_OVERFLOWS
    brne fim_overflow

    clr reg_temp
    sts contador_overflow, reg_temp

    ; Incrementa relógio
    lds reg_dezenas, segundos_relogio
    inc reg_dezenas
    cpi reg_dezenas, 60
    brlo salva_segundos_relogio
    clr reg_dezenas
    lds reg_unidades, minutos_relogio
    inc reg_unidades
    cpi reg_unidades, 60
    brlo salva_minutos_relogio
    clr reg_unidades

salva_minutos_relogio:
    sts minutos_relogio, reg_unidades

salva_segundos_relogio:
    sts segundos_relogio, reg_dezenas

    ; Incrementa cronômetro se ativo
    lds reg_temp, cronometro_ativo
    cpi reg_temp, 1
    brne fim_overflow

    lds reg_dezenas, segundos_cronometro
    inc reg_dezenas
    cpi reg_dezenas, 60
    brlo salva_segundos_cronometro
    clr reg_dezenas
    lds reg_unidades, minutos_cronometro
    inc reg_unidades
    cpi reg_unidades, 60
    brlo salva_minutos_cronometro
    clr reg_unidades

salva_minutos_cronometro:
    sts minutos_cronometro, reg_unidades

salva_segundos_cronometro:
    sts segundos_cronometro, reg_dezenas

fim_overflow:
    pop reg_status
    out SREG, reg_status
    pop reg_dezenas
    pop reg_temp
    reti
