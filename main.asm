;
; Projeto da disciplina de Microcontroladores e Aplicações
; Relógio digital com display de 7 segmentos para minutos e segundos
; Autores: Matheus Ryan, Lucas Heron, Rafael Luciano
; Data: 07/04/2025
;

; ===================== CONSTANTES DE HARDWARE =====================
.equ PORTA_DEZENAS = PORTC       ; Porta para display das dezenas
.equ DDR_DEZENAS = DDRC          ; Registro de direção das dezenas
.equ PORTA_UNIDADES = PORTD      ; Porta para display das unidades
.equ DDR_UNIDADES = DDRD         ; Registro de direção das unidades

; ===================== CONSTANTES DE TEMPORIZAÇÃO =================
.equ VALOR_INICIAL_TIMER = 256 - (16000000/1024/100)  ; 100 interrupções/segundo
.equ NUMERO_OVERFLOWS = 100       ; 100 interrupções = 1 segundo exato

; ===================== ALOCAÇÃO DE VARIÁVEIS ======================
.dseg
segundos: .byte 1          ; Contador principal de segundos (0-59)
contador_overflow: .byte 1 ; Contador auxiliar de overflows

; ===================== VETORES DE INTERRUPÇÃO =====================
.cseg
.org 0x0000
    jmp inicio             ; Vetor de reset
.org OVF0addr             ; Endereço do overflow do Timer0
    jmp trata_overflow     ; Rotina de tratamento

; ================== TABELA DE CONVERSÃO DOS DISPLAYS ==============
; Padrões para display de 7 segmentos (cátodo comum)
.org 0x0100
tabela_segmentos:
    ; Dígitos: 0    1    2    3    4    5    6    7    8    9
    .db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

; ===================== PROGRAMA PRINCIPAL =========================
.cseg
.org 0x0034
inicio:
    ; ----- Inicialização da pilha -----
    ldi r16, high(RAMEND)
    out SPH, r16
    ldi r16, low(RAMEND)
    out SPL, r16

    ; ----- Configura portas como saída -----
    ldi r16, 0xFF
    out DDR_DEZENAS, r16     ; Configura PORTC como saída
    out DDR_UNIDADES, r16    ; Configura PORTD como saída

    ; ----- Inicialização dos contadores -----
    clr r16
    sts segundos, r16
    sts contador_overflow, r16
    call atualiza_display

    ; ----- Configuração do Timer0 -----
    ldi r16, (1<<CS02)|(1<<CS00)  ; Prescaler de 1024
    out TCCR0B, r16
    
    ldi r16, VALOR_INICIAL_TIMER   ; Valor inicial calculado
    out TCNT0, r16
    
    ldi r16, (1<<TOIE0)            ; Habilita interrupção por overflow
    sts TIMSK0, r16

    ; ----- Habilita interrupções globais -----
    sei

loop_principal:
    rjmp loop_principal          ; Loop infinito

; ================== ROTINA DE ATUALIZAÇÃO DOS DISPLAYS ============
atualiza_display:
    push r16                     ; Preserva registradores
    push r17
    push r18
    push r30
    push r31

    lds r16, segundos           ; Carrega valor dos segundos
    
    ; ----- Cálculo das dezenas (divisão por 10) -----
    ldi r17, 10                 ; Divisor
    clr r18                     ; r18 armazenará as dezenas

calcula_dezenas:
    cp r16, r17                 ; Compara com 10
    brlo mostra_dezenas         ; Se menor que 10, vai mostrar
    sub r16, r17                ; Subtrai 10
    inc r18                     ; Incrementa contador de dezenas
    rjmp calcula_dezenas        ; Repete

mostra_dezenas:
    ; ----- Mostra dígito das dezenas -----
    ldi ZL, low(tabela_segmentos<<1)  ; Configura ponteiro Z
    ldi ZH, high(tabela_segmentos<<1)
    add ZL, r18                      ; Ajusta para o dígito correto
    adc ZH, r1
    lpm r17, Z                       ; Lê padrão do display
    out PORTA_DEZENAS, r17           ; Envia para o display

    ; ----- Mostra dígito das unidades -----
    ldi ZL, low(tabela_segmentos<<1)  ; Reconfigura ponteiro Z
    ldi ZH, high(tabela_segmentos<<1)
    add ZL, r16                       ; Usa o resto como índice
    adc ZH, r1
    lpm r17, Z                        ; Lê padrão do display
    out PORTA_UNIDADES, r17           ; Envia para o display

    pop r31                      ; Restaura registradores
    pop r30
    pop r18
    pop r17
    pop r16
    ret

; ============== ROTINA DE TRATAMENTO DE OVERFLOW ==================
trata_overflow:
    push r16                     ; Preserva registradores
    push r17
    in r16, SREG
    push r16

    ; ----- Reinicializa o Timer0 -----
    ldi r16, VALOR_INICIAL_TIMER
    out TCNT0, r16

    ; ----- Incrementa contador de overflows -----
    lds r16, contador_overflow
    inc r16
    cpi r16, NUMERO_OVERFLOWS    ; Verifica se atingiu o limite
    brne nao_atualiza
    
    ; ----- Atualização do tempo (1 segundo) -----
    clr r16                      ; Zera contador de overflows
    lds r17, segundos            ; Incrementa contador de segundos
    inc r17
    cpi r17, 60                  ; Verifica se passou de 59
    brlo salva_contador
    clr r17                      ; Reinicia após 59 segundos

salva_contador:
    sts segundos, r17            ; Salva novo valor
    call atualiza_display        ; Atualiza displays

nao_atualiza:
    sts contador_overflow, r16   ; Salva contador de overflows

    pop r16                      ; Restaura registradores
    out SREG, r16
    pop r17
    pop r16
    reti
