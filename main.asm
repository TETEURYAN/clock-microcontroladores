; Relógio Digital Completo para ATmega328P
;Projeto da disciplina de Microcontroladores e Aplicações do semestre 2024.2
; Matheus Ryan, Lucas Heron e Rafael Luciano
; 07/04/2025
; ================================================================

; ===================== CONSTANTES DE HARDWARE =====================
.equ PORT_BCD       = PORTB       ; PB0-PB3: Saída BCD para os displays
.equ DDR_BCD        = DDRB        ; Registrador de direção do PORTB
.equ PORT_CTRL      = PORTD       ; PD0-PD3: Controle dos displays
.equ DDR_CTRL       = DDRD        ; Registrador de direção do PORTD

.equ DDRC_ADDR      = 0x27        ; Endereço do registrador DDRC
.equ PINC_ADDR      = 0x26        ; Endereço do registrador PINC
.equ PORTC_ADDR     = 0x28        ; Endereço do registrador PORTC

; ===================== CONSTANTES DE BOTÕES =======================
.equ BOTAO_MODE     = 2           ; PC2 - Botão para alternar modos
.equ BOTAO_START    = 1           ; PC1 - Botão Start/Stop
.equ BOTAO_RESET    = 0           ; PC0 - Botão Reset/Ajuste
.equ BUZZER_BIT     = 3           ; PC3 - Saída para o buzzer

; ===================== CONSTANTES DE MODOS ========================
.equ MODO_RELOGIO    = 0          ; Modo relógio normal
.equ MODO_CRONOMETRO = 1          ; Modo cronômetro
.equ MODO_AJUSTE     = 2          ; Modo ajuste de hora

; ===================== CONSTANTES DE TEMPORIZAÇÃO =================
.equ VALOR_INICIAL_TIMER = 256 - 160 ; Valor inicial para timer0 (10ms)
.equ NUMERO_OVERFLOWS    = 100       ; 100 overflows = 1 segundo
.equ INTERVALO_PISCA     = 50        ; 0.3s para piscar dígitos no ajuste

; ===================== DEFINIÇÃO DE REGISTRADORES =================
.def reg_temp       = r16         ; Registrador temporário
.def reg_dezenas    = r17         ; Armazena dezenas em divisões
.def reg_unidades   = r18         ; Armazena unidades em divisões
.def reg_aux        = r19         ; Registrador auxiliar
.def reg_status     = r20         ; Armazena SREG durante interrupções
.def reg_display    = r21         ; Controle de exibição

; ===================== VARIÁVEIS EM MEMÓRIA =======================
.dseg
segundos_relogio:       .byte 1   ; Segundos do relógio (0-59)
minutos_relogio:        .byte 1   ; Minutos do relógio (0-59)
segundos_cronometro:    .byte 1   ; Segundos do cronômetro (0-59)
minutos_cronometro:     .byte 1   ; Minutos do cronômetro (0-59)
contador_overflow:      .byte 1   ; Contador de overflows do timer0
modo_atual:             .byte 1   ; Modo atual (0,1 ou 2)
cronometro_ativo:       .byte 1   ; Estado do cronômetro (0=parado, 1=rodando)
display_piscando:       .byte 1   ; Estado do display piscante
posicao_ajuste:         .byte 1   ; Posição atual no modo ajuste (0-3)
contador_pisca:         .byte 1   ; Contador para piscar display
start_pressionado:      .byte 1   ; Estado do botão START

; ===================== VETORES DE INTERRUPÇÃO =====================
.cseg
.org 0x0000
    jmp inicio                   ; Reset vector
.org OVF0addr
    jmp trata_overflow           ; Timer0 overflow interrupt

; ===================== PROGRAMA PRINCIPAL =========================
.org 0x0034
inicio:
    ; Inicialização da pilha
    ldi reg_temp, high(RAMEND)
    out SPH, reg_temp
    ldi reg_temp, low(RAMEND)
    out SPL, reg_temp

    ; Configuração das portas de saída
    ldi reg_temp, 0x0F           ; PB0-PB3 como saída (BCD)
    out DDR_BCD, reg_temp
    out DDR_CTRL, reg_temp       ; PD0-PD3 como saída (controle displays)
    
    ; Configuração dos botões e buzzer
    lds reg_temp, DDRC_ADDR
    andi reg_temp, ~((1<<BOTAO_MODE)|(1<<BOTAO_START)|(1<<BOTAO_RESET))
    ori reg_temp, (1<<BUZZER_BIT)
    sts DDRC_ADDR, reg_temp
    
    ; Ativa pull-ups para os botões
    ldi reg_temp, (1<<BOTAO_MODE)|(1<<BOTAO_START)|(1<<BOTAO_RESET)
    sts PORTC_ADDR, reg_temp
    
    ; Inicialização das variáveis
    clr reg_temp
    sts segundos_relogio, reg_temp
    sts minutos_relogio, reg_temp
    sts segundos_cronometro, reg_temp
    sts minutos_cronometro, reg_temp
    sts contador_overflow, reg_temp
    sts modo_atual, reg_temp
    sts cronometro_ativo, reg_temp
    sts display_piscando, reg_temp
    sts posicao_ajuste, reg_temp
    sts contador_pisca, reg_temp
    sts start_pressionado, reg_temp

    ; Configuração do Timer0 (prescaler 1024, overflow interrupt)
    ldi reg_temp, (1<<CS02)|(1<<CS00)
    out TCCR0B, reg_temp
    ldi reg_temp, VALOR_INICIAL_TIMER
    out TCNT0, reg_temp
    ldi reg_temp, (1<<TOIE0)
    sts TIMSK0, reg_temp

    sei                           ; Habilita interrupções globais

; ===================== LOOP PRINCIPAL =============================
loop_principal:
    rcall atualiza_displays       ; Atualiza os displays
    rcall verifica_botoes         ; Verifica entrada dos botões
    rjmp loop_principal           ; Repete indefinidamente

; ===================== ROTINA DE VERIFICAÇÃO DE BOTÕES ============
verifica_botoes:
    push reg_temp
    push reg_aux
    
    ; Lê o estado atual dos botões
    lds reg_temp, PINC_ADDR
    mov reg_aux, reg_temp         ; Guarda cópia do estado

    ; Verifica cada botão individualmente
    sbrs reg_aux, BOTAO_MODE      ; Botão MODE pressionado?
    rcall alternar_modo           ; Sim, alterna modo

    sbrs reg_aux, BOTAO_START     ; Botão START pressionado?
    rcall tratar_start            ; Sim, trata ação do START

    sbrs reg_aux, BOTAO_RESET     ; Botão RESET pressionado?
    rcall tratar_reset            ; Sim, trata ação do RESET

    pop reg_aux
    pop reg_temp
    ret

; ===================== ROTINA PARA ALTERNAR MODOS =================
alternar_modo:
    rcall debounce                ; Espera debounce
    lds reg_temp, modo_atual      ; Carrega modo atual
    
    inc reg_temp                  ; Avança para próximo modo
    cpi reg_temp, 3               ; Verifica se passou do último modo
    brlt salvar_modo              ; Se não, salva o novo modo
    clr reg_temp                  ; Se sim, volta ao modo 0
    
salvar_modo:
    sts modo_atual, reg_temp      ; Armazena novo modo
    
    ; Configurações específicas para cada modo
    cpi reg_temp, MODO_RELOGIO
    breq config_modo_relogio
    cpi reg_temp, MODO_CRONOMETRO
    breq config_modo_cronometro
    cpi reg_temp, MODO_AJUSTE
    breq config_modo_ajuste
    
config_modo_relogio:
    rjmp fim_alternar_modo        ; Nada especial a configurar
    
config_modo_cronometro:
    clr reg_aux                   ; Zera contadores do cronômetro
    sts segundos_cronometro, reg_aux
    sts minutos_cronometro, reg_aux
    sts cronometro_ativo, reg_aux
    rjmp fim_alternar_modo
    
config_modo_ajuste:
    clr reg_aux                   ; Inicia ajuste na posição 0
    sts posicao_ajuste, reg_aux
    sts contador_pisca, reg_aux
    
fim_alternar_modo:
    rcall apitar_buzzer           ; Feedback audível
    ret

; ===================== ROTINA PARA TRATAR BOTÃO START =============
tratar_start:
    rcall debounce2               ; Debounce rápido
    
    lds reg_temp, modo_atual      ; Verifica modo atual
    cpi reg_temp, MODO_CRONOMETRO
    breq start_cronometro         ; Modo cronômetro
    cpi reg_temp, MODO_AJUSTE
    breq start_ajuste             ; Modo ajuste
    
    ret                           ; Nada a fazer em outros modos
    
start_cronometro:
    ; Verifica se o botão está pressionado
    lds reg_temp, PINC_ADDR
    sbrs reg_temp, BOTAO_START
    rjmp start_botao_pressionado
    
    rjmp start_sair
    
start_botao_pressionado:
    ; Espera um tempo mínimo para confirmar o pressionamento
    ldi reg_temp, 20
start_aguarda_confirma:
    dec reg_temp
    brne start_aguarda_confirma

    ; Verifica se ainda está pressionado
    lds reg_temp, PINC_ADDR
    sbrs reg_temp, BOTAO_START
    rjmp start_confirma_pressionado
    
    rjmp start_sair
    
start_confirma_pressionado:
    ; Alterna estado do cronômetro (start/stop)
    lds reg_temp, cronometro_ativo
    ldi reg_aux, 1
    eor reg_temp, reg_aux
    sts cronometro_ativo, reg_temp
    
    rcall apitar_buzzer           ; Feedback audível

    ; Espera soltar o botão
start_aguarda_soltar:
    rcall debounce2
    lds reg_temp, PINC_ADDR
    sbrs reg_temp, BOTAO_START
    rjmp start_aguarda_soltar
    
start_sair:
    ret
    
start_ajuste:
    ; Avança para próxima posição de ajuste
    lds reg_temp, posicao_ajuste
    inc reg_temp
    cpi reg_temp, 4               ; Verifica se passou da última posição
    brlt salvar_posicao_ajuste
    clr reg_temp                  ; Volta para primeira posição
    
salvar_posicao_ajuste:
    sts posicao_ajuste, reg_temp
    rcall apitar_buzzer           ; Feedback audível
    ret

; ===================== ROTINA PARA TRATAR BOTÃO RESET =============
tratar_reset:
    rcall debounce                ; Espera debounce
    
    lds reg_temp, modo_atual      ; Verifica modo atual
    cpi reg_temp, MODO_CRONOMETRO
    breq reset_cronometro         ; Modo cronômetro
    cpi reg_temp, MODO_AJUSTE
    breq reset_ajuste             ; Modo ajuste
    
    ret                           ; Nada a fazer em outros modos
    
reset_cronometro:
    ; Só reseta se o cronômetro estiver parado
    lds reg_temp, cronometro_ativo
    cpi reg_temp, 0
    brne fim_reset
    
    clr reg_temp                  ; Zera contadores
    sts segundos_cronometro, reg_temp
    sts minutos_cronometro, reg_temp
    rcall apitar_buzzer           ; Feedback audível
    
fim_reset:
    ret
    
reset_ajuste:
    ; Ajusta o dígito correspondente à posição atual
    lds reg_temp, posicao_ajuste
    cpi reg_temp, 0
    breq ajustar_unidade_seg
    cpi reg_temp, 1
    breq ajustar_dezena_seg
    cpi reg_temp, 2
    breq ajustar_unidade_min
    cpi reg_temp, 3
    breq ajustar_dezena_min
    ret
    
ajustar_unidade_seg:
    ; Incrementa unidade de segundos (0-9)
    lds reg_temp, segundos_relogio
    inc reg_temp
    cpi reg_temp, 10
    brlt salvar_segundos
    ldi reg_temp, 0
salvar_segundos:
    sts segundos_relogio, reg_temp
    rcall apitar_buzzer
    ret
    
ajustar_dezena_seg:
    ; Incrementa dezena de segundos (+10)
    lds reg_temp, segundos_relogio
    ldi reg_aux, 10
    add reg_temp, reg_aux
    cpi reg_temp, 60
    brlt salvar_segundos
    subi reg_temp, 60
    rjmp salvar_segundos
    
ajustar_unidade_min:
    ; Incrementa unidade de minutos (0-9)
    lds reg_temp, minutos_relogio
    inc reg_temp
    cpi reg_temp, 10
    brlt salvar_minutos
    ldi reg_temp, 0
salvar_minutos:
    sts minutos_relogio, reg_temp
    rcall apitar_buzzer
    ret
    
ajustar_dezena_min:
    ; Incrementa dezena de minutos (+10)
    lds reg_temp, minutos_relogio
    ldi reg_aux, 10
    add reg_temp, reg_aux
    cpi reg_temp, 60
    brlt salvar_minutos
    subi reg_temp, 60
    rjmp salvar_minutos

; ===================== ROTINA DO BUZZER ===========================
apitar_buzzer:
    push reg_temp
    ; Ativa o buzzer
    lds reg_temp, PORTC_ADDR
    ori reg_temp, (1 << BUZZER_BIT)
    sts PORTC_ADDR, reg_temp

    ; Pequeno delay para o bip
    ldi reg_temp, 50
espera_buzzer:
    dec reg_temp
    brne espera_buzzer

    ; Desativa o buzzer
    lds reg_temp, PORTC_ADDR
    andi reg_temp, ~(1 << BUZZER_BIT)
    sts PORTC_ADDR, reg_temp
    pop reg_temp
    ret

; ===================== ROTINAS DE DEBOUNCE ========================
debounce:
    ; Debounce de ~300ms
    ldi r31, byte3(16 * 1000 * 300 / 5)
    ldi r30, high(16 * 1000 * 300 / 5)
    ldi r29, low(16 * 1000 * 300 / 5)

debounce_loop:
    subi r29, 1
    sbci r30, 0
    sbci r31, 0
    brcc debounce_loop
    ret

debounce2:
    ; Debounce rápido de ~10ms (para botão START)
    ldi r31, byte3(16 * 1000 * 10 / 5)
    ldi r30, high(16 * 1000 * 10 / 5)
    ldi r29, low(16 * 1000 * 10 / 5)

debounce2_loop:
    subi r29, 1
    sbci r30, 0
    sbci r31, 0
    brcc debounce2_loop
    ret

; ===================== ROTINA DE ATUALIZAÇÃO DE DISPLAYS =========
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

    ; Seleciona dados para exibição conforme o modo
    lds reg_temp, modo_atual
    cpi reg_temp, MODO_RELOGIO
    breq exibir_relogio
    cpi reg_temp, MODO_CRONOMETRO
    breq exibir_cronometro
    
    ; Modo Ajuste - usa dados do relógio mas com piscar de dígitos
    rjmp exibir_relogio_ajuste

exibir_relogio:
    ; Prepara dados do relógio para exibição
    lds reg_temp, segundos_relogio
    rcall dividir_por_10
    mov r22, reg_unidades  ; Unidades de segundos
    mov r23, reg_dezenas   ; Dezenas de segundos

    lds reg_temp, minutos_relogio
    rcall dividir_por_10
    mov r24, reg_unidades  ; Unidades de minutos
    mov r25, reg_dezenas   ; Dezenas de minutos
    rjmp mostrar_displays

exibir_cronometro:
    ; Prepara dados do cronômetro para exibição
    lds reg_temp, segundos_cronometro
    rcall dividir_por_10
    mov r22, reg_unidades  ; Unidades de segundos
    mov r23, reg_dezenas   ; Dezenas de segundos

    lds reg_temp, minutos_cronometro
    rcall dividir_por_10
    mov r24, reg_unidades  ; Unidades de minutos
    mov r25, reg_dezenas   ; Dezenas de minutos
    rjmp mostrar_displays
    
exibir_relogio_ajuste:
    ; Prepara dados do relógio (modo ajuste)
    lds reg_temp, segundos_relogio
    rcall dividir_por_10
    mov r22, reg_unidades  ; Unid. segundos
    mov r23, reg_dezenas   ; Dez. segundos

    lds reg_temp, minutos_relogio
    rcall dividir_por_10
    mov r24, reg_unidades  ; Unid. minutos
    mov r25, reg_dezenas   ; Dez. minutos

    ; Controle do piscar (0.3s ligado, 0.3s desligado)
    lds reg_temp, contador_pisca
    cpi reg_temp, INTERVALO_PISCA/2
    brsh mostrar_tudo      ; Mostra tudo se na metade superior do intervalo
    
    ; Decide qual dígito piscar baseado na posição de ajuste
    lds reg_temp, posicao_ajuste
    cpi reg_temp, 0
    breq piscar_unidade_seg
    cpi reg_temp, 1
    breq piscar_dezena_seg
    cpi reg_temp, 2
    breq piscar_unidade_min
    cpi reg_temp, 3
    breq piscar_dezena_min
    rjmp mostrar_displays

piscar_unidade_seg:
    ldi r22, 0x00         ; Apaga unidade de segundos
    rjmp mostrar_displays
    
piscar_dezena_seg:
    ldi r23, 0x00         ; Apaga dezena de segundos
    rjmp mostrar_displays
    
piscar_unidade_min:
    ldi r24, 0x00         ; Apaga unidade de minutos
    rjmp mostrar_displays
    
piscar_dezena_min:
    ldi r25, 0x00         ; Apaga dezena de minutos

mostrar_tudo:
    rjmp mostrar_displays

mostrar_displays:
    ; Exibe unidade de segundos (display 1)
    mov reg_temp, r22
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000001  ; Ativa display 1
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Exibe dezena de segundos (display 2)
    mov reg_temp, r23
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000010  ; Ativa display 2
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Exibe unidade de minutos (display 3)
    mov reg_temp, r24
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00000100  ; Ativa display 3
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Exibe dezena de minutos (display 4)
    mov reg_temp, r25
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00001000  ; Ativa display 4
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Desativa todos os displays
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

; ===================== ROTINA DE DIVISÃO POR 10 ===================
dividir_por_10:
    push reg_aux
    ldi reg_unidades, 10  ; Divisor
    clr reg_dezenas       ; Contador de dezenas
div_loop:
    cp reg_temp, reg_unidades  ; Compara com 10
    brlo div_pronto       ; Se menor, terminou
    sub reg_temp, reg_unidades ; Subtrai 10
    inc reg_dezenas       ; Incrementa contador de dezenas
    rjmp div_loop         ; Repete
div_pronto:
    mov reg_unidades, reg_temp ; O resto são as unidades
    pop reg_aux
    ret

; ===================== ROTINA DE ATRASO PARA DISPLAYS ============
atraso_display:
    ldi reg_aux, 20       ; Contador externo
loop_externo:
    ldi reg_display, 60   ; Contador interno
loop_interno:
    dec reg_display
    brne loop_interno
    dec reg_aux
    brne loop_externo
    ret

; ===================== TRATAMENTO DE OVERFLOW DO TIMER0 ===========
trata_overflow:
    push reg_temp
    push reg_dezenas
    in reg_status, SREG
    push reg_status

    ; Recarrega timer para próximo overflow em 10ms
    ldi reg_temp, VALOR_INICIAL_TIMER
    out TCNT0, reg_temp

    ; Incrementa contador de overflows
    lds reg_temp, contador_overflow
    inc reg_temp
    sts contador_overflow, reg_temp
    
    ; Atualiza contador para piscar display (modo ajuste)
    lds reg_temp, contador_pisca
    inc reg_temp
    cpi reg_temp, INTERVALO_PISCA
    brlo salvar_contador_pisca
    clr reg_temp
salvar_contador_pisca:
    sts contador_pisca, reg_temp
    
    ; Verifica se passou 1 segundo (100 overflows)
    lds reg_temp, contador_overflow
    cpi reg_temp, NUMERO_OVERFLOWS
    brne fim_overflow

    ; Zera contador de overflows após 1 segundo
    clr reg_temp
    sts contador_overflow, reg_temp

    ; ========= ATUALIZAÇÃO DO RELÓGIO PRINCIPAL =========
    lds reg_dezenas, segundos_relogio
    inc reg_dezenas                  ; Incrementa segundos
    cpi reg_dezenas, 60              ; Verifica se passou de 59
    brlo salvar_segundos_relogio     ; Se não, salva
    clr reg_dezenas                  ; Se sim, zera segundos
    
    lds reg_unidades, minutos_relogio
    inc reg_unidades                 ; Incrementa minutos
    cpi reg_unidades, 60             ; Verifica se passou de 59
    brlo salvar_minutos_relogio      ; Se não, salva
    clr reg_unidades                 ; Se sim, zera minutos

salvar_minutos_relogio:
    sts minutos_relogio, reg_unidades

salvar_segundos_relogio:
    sts segundos_relogio, reg_dezenas

    ; ========= ATUALIZAÇÃO DO CRONÔMETRO (SE ATIVO) =========
    lds reg_temp, modo_atual         ; Verifica se está no modo cronômetro
    cpi reg_temp, MODO_CRONOMETRO
    brne fim_overflow
    
    lds reg_temp, cronometro_ativo   ; Verifica se cronômetro está ativo
    cpi reg_temp, 1
    brne fim_overflow

    ; Incrementa cronômetro (mesma lógica do relógio)
    lds reg_dezenas, segundos_cronometro
    inc reg_dezenas
    cpi reg_dezenas, 60
    brlo salvar_segundos_cronometro
    clr reg_dezenas
    
    lds reg_unidades, minutos_cronometro
    inc reg_unidades
    cpi reg_unidades, 60
    brlo salvar_minutos_cronometro
    clr reg_unidades

salvar_minutos_cronometro:
    sts minutos_cronometro, reg_unidades

salvar_segundos_cronometro:
    sts segundos_cronometro, reg_dezenas

fim_overflow:
    ; Restaura registradores e retorna
    pop reg_status
    out SREG, reg_status
    pop reg_dezenas
    pop reg_temp
    reti
