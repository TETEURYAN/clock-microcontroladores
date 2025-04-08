; Projeto da disciplina de Microcontroladores e Aplicações
; Relógio digital com display de 7 segmentos para minutos e segundos
; Autores: Matheus Ryan, Lucas Heron, Rafael Luciano
; Data: 07/04/2025
;


; ===================== CONSTANTES DE HARDWARE =====================
.equ PORT_MINUTOS = PORTB       ; PB0-PB3: Minutos dezenas, PB4-PB7: Minutos unidades
.equ PORT_SEGUNDOS = PORTD      ; PD0-PD3: Segundos dezenas, PD4-PD7: Segundos unidades

; ===================== CONSTANTES DE TEMPORIZAÇÃO =================
.equ VALOR_INICIAL_TIMER = 256 - (16000000/1024/100)  ; 100 interrupções/segundo
.equ NUMERO_OVERFLOWS = 100       ; 100 interrupções = 1 segundo

; ===================== NOMES DE REGISTRADORES =====================
.def reg_temp      = r16
.def reg_dezenas   = r17
.def reg_unidades  = r18
.def reg_aux       = r19
.def reg_status    = r20

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
    ldi reg_temp, 0xFF
    out DDRB, reg_temp
    out DDRD, reg_temp

    ; Zera contadores
    clr reg_temp
    sts segundos, reg_temp
    sts minutos, reg_temp
    sts contador_overflow, reg_temp
    call atualiza_displays

    ; Configura Timer0
    ldi reg_temp, (1<<CS02)|(1<<CS00)
    out TCCR0B, reg_temp
    ldi reg_temp, VALOR_INICIAL_TIMER
    out TCNT0, reg_temp
    ldi reg_temp, (1<<TOIE0)
    sts TIMSK0, reg_temp

    sei  ; Habilita interrupções globais

loop_principal:
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

; =============== ATUALIZAÇÃO DOS DISPLAYS ===============
atualiza_displays:
    push reg_temp
    push reg_dezenas
    push reg_unidades
    push reg_aux

    ; ----- Minutos -----
    lds reg_temp, minutos
    rcall dividir_por_10
    swap reg_unidades
    or reg_unidades, reg_dezenas
    out PORT_MINUTOS, reg_unidades

    ; ----- Segundos -----
    lds reg_temp, segundos
    rcall dividir_por_10
    swap reg_unidades
    or reg_unidades, reg_dezenas
    out PORT_SEGUNDOS, reg_unidades

    pop reg_aux
    pop reg_unidades
    pop reg_dezenas
    pop reg_temp
    ret

; ============ TIMERS ==================
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
    call atualiza_displays

fim_overflow:
    pop reg_status
    out SREG, reg_status
    pop reg_dezenas
    pop reg_temp
    reti
