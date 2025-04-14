; Relógio Digital Completo para ATmega328P
; Projeto da disciplina de Microcontroladores e Aplicações do semestre 2024.2
; Matheus Ryan, Lucas Heron e Rafael Luciano
; 07/04/2025
; ================================================================

; ===================== CONSTANTES DE HARDWARE =====================
; Define as portas de saída para o BCD e de controle para o display
.equ PORT_BCD       = PORTB       ; PB0-PB3: Saída BCD para os displays
.equ DDR_BCD        = DDRB        ; Registrador de direção do PORTB
.equ PORT_CTRL      = PORTD       ; PD0-PD3: Controle dos displays
.equ DDR_CTRL       = DDRD        ; Registrador de direção do PORTD

; Define a porta dos botões
.equ DDRC_ADDR      = 0x27        ; Endereço do registrador DDRC
.equ PINC_ADDR      = 0x26        ; Endereço do registrador PINC
.equ PORTC_ADDR     = 0x28        ; Endereço do registrador PORTC

; ===================== CONSTANTES DE BOTÕES =======================
; Define o pino para cada botão
.equ BOTAO_MODE     = 2           ; PC2 - Botão para alternar modos
.equ BOTAO_START    = 1           ; PC1 - Botão Start/Stop
.equ BOTAO_RESET    = 0           ; PC0 - Botão Reset/Ajuste
.equ BUZZER_BIT     = 3           ; PC3 - Saída para o buzzer

; ===================== CONSTANTES DE MODOS ========================
; Define o valor de cada modo
.equ MODO_RELOGIO    = 0          ; Modo relógio normal
.equ MODO_CRONOMETRO = 1          ; Modo cronômetro
.equ MODO_AJUSTE     = 2          ; Modo ajuste de hora

; ===================== CONSTANTES DE TEMPORIZAÇÃO =================
; Define o tempo que o timer irá contar para dar 1 segundo
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
.def reg_uni_seg    = r22        ; Unidades de segundos
.def reg_dez_seg    = r23         ; Dezenas de segundos
.def reg_uni_min    = r24         ; Unidades de minutos
.def reg_dez_min    = r25         ; Dezenas de minutos

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
mensagem_inicial:		.byte 1   ; Flag para mensagem inicial
bloqueio_start:         .byte 1   ; Flag para bloquear START temporariamente
bloqueio_reset:         .byte 1   ; Flag para bloquear RESET temporariamente

; ===================== VETORES DE INTERRUPÇÃO =====================
.cseg
.org 0x0000
    jmp inicio                   
.org OVF0addr
    jmp trata_overflow           ; Vetor de interrupção de overflow do Timer0

; ===================== PROGRAMA PRINCIPAL =========================
.org 0x0034
inicio:
    ; Inicialização da pilha
    ldi reg_temp, high(RAMEND)
    out SPH, reg_temp
    ldi reg_temp, low(RAMEND)
    out SPL, reg_temp

	; Configuração da UART (9600 bps, 8 bits, sem paridade, 1 stop bit)
	ldi reg_temp, 0x00
	sts UBRR0H, reg_temp
	ldi reg_temp, 103 ; 16MHz / (16 * 9600) - 1 = 103.166 → 103
	sts UBRR0L, reg_temp

	; Habilita transmissão e recepção
    ldi reg_temp, (1<<TXEN0)|(1<<RXEN0)
    sts UCSR0B, reg_temp
    
    ; Configura formato do frame: 8 bits, 1 stop bit, sem paridade
    ldi reg_temp, (1<<UCSZ01)|(1<<UCSZ00)
    sts UCSR0C, reg_temp

    ; Configuração das portas de saída
    ldi reg_temp, 0x0F           ; PB0-PB3 como saída (BCD)
    out DDR_BCD, reg_temp
	ldi reg_temp, 0xF0
    out DDR_CTRL, reg_temp       ; PD0-PD3 como saída (controle displays)
    
    ; Configuração dos botões e buzzer
    lds reg_temp, DDRC_ADDR
    andi reg_temp, ~((1<<BOTAO_MODE)|(1<<BOTAO_START)|(1<<BOTAO_RESET)) ; Configura os botões como entrada (0)
    ori reg_temp, (1<<BUZZER_BIT)	; Define botão do Buzzer como saída (1)
    sts DDRC_ADDR, reg_temp
    
    ; Ativa pull-ups para os botões
    ldi reg_temp, (1<<BOTAO_MODE)|(1<<BOTAO_START)|(1<<BOTAO_RESET) ; Carrega 0b00000111 em reg_temp, ativando pull-ups internos nos pinos PC2, PC1 e PC0
    sts PORTC_ADDR, reg_temp		; Configura PORTC definindo que os botões tenham nível lógico alto quando não pressionados.
    
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
	sts mensagem_inicial, reg_temp

    ; Configuração do Timer0 (prescaler 1024, overflow interrupt)
    ldi reg_temp, (1<<CS02)|(1<<CS00)	; 101
    out TCCR0B, reg_temp				; Registrador de controle TCCR0B do Timer0
    ldi reg_temp, VALOR_INICIAL_TIMER
    out TCNT0, reg_temp					; Define contador do timer com valor inicial 96
    ldi reg_temp, (1<<TOIE0)			; Ativa a interrupção de overflow do Timer0 
    sts TIMSK0, reg_temp				; Habilita a interrupção no registrador TIMSK0

    sei                           ; Habilita interrupções globais

; ===================== EXIBIÇÃO DE MENSAGEM INICIAL ===============
	push ZL
    push ZH
    push reg_temp
    
    ; Verifica se já enviou
    lds reg_temp, mensagem_inicial
    cpi reg_temp, 1
    breq loop_principal  ; Se já enviou, não envia de novo
    
    ; Envia mensagem inicial
    ldi ZL, low(2*msg_modo1)
    ldi ZH, high(2*msg_modo1)
    rcall uart_enviar_string
    
    ; Marca como enviada
    ldi reg_temp, 1
    sts mensagem_inicial, reg_temp

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
	; Evita com que ele aperte start "sozinho" ao trocar de modo
	ldi reg_aux, 1
    sts bloqueio_start, reg_aux
    
    sts modo_atual, reg_temp      ; Armazena novo modo

	; Carrega msg do modo 1
	push ZL
	push ZH
	ldi ZL, low(2*msg_modo1)
	ldi ZH, high(2*msg_modo1)

	; Desvia para o modo apropriado
	cpi reg_temp, MODO_CRONOMETRO
	breq modo2_msg
	cpi reg_temp, MODO_AJUSTE
	breq modo3_msg

; Envia as mensagens
modo1_msg:
	rcall uart_enviar_string			; Envia mensagem modo 1
	rjmp fim_msg

modo2_msg:
	ldi ZL, low(2*msg_modo2_zero)		; Carrega mensagem de Zero no modo 2
    ldi ZH, high(2*msg_modo2_zero)
    rcall uart_enviar_string			; Envia mensagem modo 2
    rjmp fim_msg

modo3_msg:
    ldi ZL, low(2*msg_modo3_uni_seg)	; Carrega mensagem do modo 3
    ldi ZH, high(2*msg_modo3_uni_seg)
    rcall uart_enviar_string			; Envia mensagem modo 3
    
fim_msg:
    pop ZH
    pop ZL
    
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
    sts contador_pisca, reg_aux	  ; Variável que determina a duração do pisca

; Rotina feita para evitar pressionamento várias vezes
aguarda_liberar_start:
    lds reg_temp, PINC_ADDR
    sbrs reg_temp, BOTAO_START    ; Se o botão START estiver em nível lógico alto (liberado),
    rjmp aguarda_liberar_start    ; continua esperando
    
fim_alternar_modo:
    rcall apitar_buzzer           ; Feedback audível
    ret

; ===================== ROTINA PARA TRATAR BOTÃO START =============
tratar_start:
	; Evita com que ele aperte start "sozinho" ao trocar de modo
    lds reg_aux, bloqueio_start
    cpi reg_aux, 1
    breq ignorar_start
    
    rcall debounce2               ; Debounce rápido
    
    lds reg_temp, modo_atual      ; Verifica modo atual
    cpi reg_temp, MODO_CRONOMETRO
    breq start_cronometro         ; Vai pro modo cronômetro
    cpi reg_temp, MODO_AJUSTE
    breq start_ajuste             ; Vai pro modo ajuste
    
    ret                           ; Nada a fazer em outros modos

ignorar_start:
    ret
    
; Evita pressionamento várias vezes de start
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
    
; Alterna estado do cronômetro (start/stop)
start_confirma_pressionado:

    lds reg_temp, cronometro_ativo
    ldi reg_aux, 1
    eor reg_temp, reg_aux
    sts cronometro_ativo, reg_temp
    
    ; Envia mensagem adequada
    push ZL
    push ZH
    ldi ZL, low(2*msg_modo2_start)
    ldi ZH, high(2*msg_modo2_start)
    cpi reg_temp, 0					; Vê se cronometro tá zerado
    breq send_zero_msg				; Se tiver, manda a msg de 0
    rcall uart_enviar_string		; Se não, envia a de start
    rjmp fim_start_msg
send_zero_msg:
    ldi ZL, low(2*msg_modo2_start)
    ldi ZH, high(2*msg_modo2_start)
    rcall uart_enviar_string
fim_start_msg:
    pop ZH
    pop ZL
    
    rcall apitar_buzzer 
    
; Espera soltar o botão
start_aguarda_soltar:
    rcall debounce2
    lds reg_temp, PINC_ADDR
    sbrs reg_temp, BOTAO_START
    rjmp start_aguarda_soltar
    
start_sair:
    ret
    
; Avança para próxima posição de ajuste
start_ajuste:
    rcall debounce
    
    ; Verifica se o RESET está pressionado antes de mudar posição
    lds reg_temp, PINC_ADDR
    sbrc reg_temp, BOTAO_RESET    ; Se RESET não está pressionado
    rjmp mudar_posicao            ; Continua normalmente
    
    ; Se RESET está pressionado, ignora a mudança de posição
    ret

mudar_posicao:
    lds reg_temp, posicao_ajuste
    inc reg_temp
    cpi reg_temp, 4               ; Verifica se passou da última posição
    brlt salvar_posicao_ajuste
    clr reg_temp                ; Volta para primeira posição
    
salvar_posicao_ajuste:
    sts posicao_ajuste, reg_temp
	
    
    ; Ativa bloqueio do RESET temporariamente
    ldi reg_aux, 1
    sts bloqueio_reset, reg_aux
    ; Envia mensagem da posição de ajuste
    push ZL
    push ZH
    lds reg_temp, posicao_ajuste
    cpi reg_temp, 0
    breq msg_uni_seg
    cpi reg_temp, 1
    breq msg_dez_seg
    cpi reg_temp, 2
    breq msg_uni_min
    
; Mensagem da posição da dezena dos minutos
msg_dez_min:
    ldi ZL, low(2*msg_modo3_dez_min)
    ldi ZH, high(2*msg_modo3_dez_min)
    rjmp send_ajuste_msg

; Mensagem da posição da unidade dos segundos
msg_uni_seg:
    ldi ZL, low(2*msg_modo3_uni_seg)
    ldi ZH, high(2*msg_modo3_uni_seg)
    rjmp send_ajuste_msg

; Mensagem da posição da dezena dos segundos
msg_dez_seg:
    ldi ZL, low(2*msg_modo3_dez_seg)
    ldi ZH, high(2*msg_modo3_dez_seg)
    rjmp send_ajuste_msg

; Mensagem da posição da unidade dos minutos
msg_uni_min:
    ldi ZL, low(2*msg_modo3_uni_min)
    ldi ZH, high(2*msg_modo3_uni_min)
    
send_ajuste_msg:
    rcall uart_enviar_string
    pop ZH
    pop ZL
    
    rcall apitar_buzzer           ; Feedback audível
    ret

; ===================== ROTINA PARA TRATAR BOTÃO RESET =============
tratar_reset:
    rcall debounce                ; Espera debounce
    
    lds reg_temp, modo_atual      ; Verifica modo atual
    cpi reg_temp, MODO_CRONOMETRO
    breq reset_cronometro         ; Vai pro modo cronômetro
    cpi reg_temp, MODO_AJUSTE
    breq reset_ajuste             ; Vai pro modo ajuste
    
    ret                           ; Nada a fazer em outros modos
    
reset_cronometro:
    ; Só reseta se o cronômetro estiver parado
    lds reg_temp, cronometro_ativo
    cpi reg_temp, 0
    brne fim_reset
    
    clr reg_temp                  ; Zera contadores
    sts segundos_cronometro, reg_temp
    sts minutos_cronometro, reg_temp
    
    ; Envia mensagem de reset
    push ZL
    push ZH
    ldi ZL, low(2*msg_modo2_reset)
    ldi ZH, high(2*msg_modo2_reset)
    rcall uart_enviar_string
    pop ZH
    pop ZL
    
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
    ; Carrega o valor total de segundos
    lds reg_temp, segundos_relogio
    
    ; Extrai dezena e unidade usando divisão por 10
    rcall dividir_por_10
    mov reg_dezenas, reg_dezenas    ; Preserva a dezena atual
    mov reg_unidades, reg_unidades  ; Carrega a unidade atual
    
    ; Incrementa a unidade
    inc reg_unidades
    cpi reg_unidades, 10			; Compara com 10
    brlt combinar_segundos			; Se for menor, vai combinar (Dezena * 10 + Unidade)
    ldi reg_unidades, 0             ; Reseta unidade para 0 se atingir 10
    
combinar_segundos:
    ; Combina dezena e unidade: total = dezena * 10 + unidade
    ldi reg_aux, 10
    mul reg_dezenas, reg_aux        ; Multiplica dezena por 10
    mov reg_temp, r0                ; Resultado da multiplicação em r0
    add reg_temp, reg_unidades      ; Adiciona a nova unidade
    sts segundos_relogio, reg_temp  ; Salva o novo valor total
    rcall apitar_buzzer             ; Feedback audível
    ret
    
ajustar_dezena_seg:
    ; Incrementa dezena de segundos (+10)
    lds reg_temp, segundos_relogio
    ldi reg_aux, 10
    add reg_temp, reg_aux
    cpi reg_temp, 60
    brlt salvar_segundos
    subi reg_temp, 60

salvar_segundos:
    sts segundos_relogio, reg_temp
    rcall apitar_buzzer
    ret
    
ajustar_unidade_min:
    ; Carrega o valor total de minutos
    lds reg_temp, minutos_relogio
    
    ; Extrai dezena e unidade usando divisão por 10
    rcall dividir_por_10
    mov reg_dezenas, reg_dezenas    ; Preserva a dezena atual
    mov reg_unidades, reg_unidades  ; Carrega a unidade atual
    
    ; Incrementa a unidade
    inc reg_unidades
    cpi reg_unidades, 10			; Compara com 10
    brlt combinar_minutos			; Se for menor, vai combinar (Dezena * 10 + Unidade)
    ldi reg_unidades, 0             ; Reseta unidade para 0 se atingir 10
    
combinar_minutos:
    ; Combina dezena e unidade: total = dezena * 10 + unidade
    ldi reg_aux, 10
    mul reg_dezenas, reg_aux        ; Multiplica dezena por 10
    mov reg_temp, r0                ; Resultado da multiplicação em r0
    add reg_temp, reg_unidades      ; Adiciona a nova unidade
    sts minutos_relogio, reg_temp   ; Salva o novo valor total
    rcall apitar_buzzer             ; Feedback audível
    ret
    
ajustar_dezena_min:
    ; Incrementa dezena de minutos (+10)
    lds reg_temp, minutos_relogio
    ldi reg_aux, 10
    add reg_temp, reg_aux
    cpi reg_temp, 60
    brlt salvar_minutos
    subi reg_temp, 60

salvar_minutos:
    sts minutos_relogio, reg_temp
    rcall apitar_buzzer
    ret

; ===================== ROTINA DO BUZZER ===========================
apitar_buzzer:
    push reg_temp
    push reg_aux

    ; Ativa o buzzer (PC3)
    lds reg_temp, PORTC_ADDR
    ori reg_temp, (1 << BUZZER_BIT)
    sts PORTC_ADDR, reg_temp

    ; Delay para bip (0.15 a 0.2 s dependendo do clock)
    ldi reg_temp, 150        ; Loop externo

bip_delay_outer:
    ldi reg_aux, 255         ; Loop interno

bip_delay_inner:
    dec reg_aux
    brne bip_delay_inner

    dec reg_temp
    brne bip_delay_outer

    ; Desativa o buzzer
    lds reg_temp, PORTC_ADDR
    andi reg_temp, ~(1 << BUZZER_BIT)
    sts PORTC_ADDR, reg_temp

    pop reg_aux
    pop reg_temp
    ret


; ===================== ROTINAS DE DEBOUNCE ========================
; Configura um contador de 32 bits para 300ms de delay
; Repete enquanto o carry não for setado
debounce:
    ; Debounce de ~300ms
	;           clock(MHz)   delay(ms)
	;               v           v
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
    ; Debounce rápido de ~30ms (para botão START)
    ldi r31, byte3(16 * 1000 * 40 / 5)
    ldi r30, high(16 * 1000 * 40 / 5)
    ldi r29, low(16 * 1000 * 40 / 5)

debounce2_loop:
    subi r29, 1
    sbci r30, 0
    sbci r31, 0
    brcc debounce2_loop
    ret

; ===================== ROTINA DE ATUALIZAÇÃO DE DISPLAYS =========
atualiza_displays:
	; Salva os registradores usados na pilha
    push reg_temp
    push reg_dezenas
    push reg_unidades
    push reg_aux
    push reg_display
    push reg_uni_seg
    push reg_dez_seg
    push reg_uni_min
    push reg_dez_min

    ; Exibe relógio de acordo com o modo atual
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
    mov reg_uni_seg, reg_unidades   ; Unidades de segundos
    mov reg_dez_seg, reg_dezenas			; Dezenas de segundos

    lds reg_temp, minutos_relogio
    rcall dividir_por_10
    mov reg_uni_min, reg_unidades			; Unidades de minutos
    mov reg_dez_min, reg_dezenas			; Dezenas de minutos
    rjmp mostrar_displays

exibir_cronometro:
    ; Prepara dados do cronômetro para exibição
    lds reg_temp, segundos_cronometro
    rcall dividir_por_10
    mov reg_uni_seg, reg_unidades   ; Unidades de segundos
    mov reg_dez_seg, reg_dezenas			; Dezenas de segundos

    lds reg_temp, minutos_cronometro
    rcall dividir_por_10
    mov reg_uni_min, reg_unidades			; Unidades de minutos
    mov reg_dez_min, reg_dezenas			; Dezenas de minutos
    rjmp mostrar_displays
    
exibir_relogio_ajuste:
    ; Carrega os valores normais dos dígitos
    lds reg_temp, segundos_relogio
    rcall dividir_por_10
    mov reg_uni_seg, reg_unidades
    mov reg_dez_seg, reg_dezenas

    lds reg_temp, minutos_relogio
    rcall dividir_por_10
    mov reg_uni_min, reg_unidades
    mov reg_dez_min, reg_dezenas
    
    ; Incrementa display_piscando para controlar o piscar
    lds reg_temp, display_piscando
    inc reg_temp
    sts display_piscando, reg_temp
    
    ; O piscar será tratado em mostrar_displays
    rjmp mostrar_displays

mostrar_displays:
    ; Dígito 1: Unidades de segundos (reg_uni_seg, posicao_ajuste = 0)
    lds reg_aux, modo_atual
    cpi reg_aux, MODO_AJUSTE		; Vê se tá no modo ajuste
    brne set_normal1				; Se não, só mostra normalmente
    lds reg_aux, posicao_ajuste
    cpi reg_aux, 0					; Vê se tá na posicao de ajuste 0
    brne set_normal1				; Se não, só mostra normalmente
    lds reg_aux, display_piscando	; Se sim, carrega o estado de piscar
    andi reg_aux, 0x10				; Pisca mais rápido
    breq set_blank1					; Se 0, apaga o dígito (pisca)
set_normal1:
    mov reg_temp, reg_uni_seg				; Mostra unidade dos segundos
    out PORT_BCD, reg_temp			; Envia os segundos pro BCD
    ldi reg_temp, 0b00010000		; Ativa somente o display de unidades de segundos
    rjmp set_ctrl1
set_blank1:
    clr reg_temp
    out PORT_BCD, reg_temp  ; Limpa PORT_BCD para garantir que nenhum segmento acenda
    ldi reg_temp, 0
set_ctrl1:
    out PORT_CTRL, reg_temp	; Ativa somente o display de unidades de segundos
    rcall atraso_display

    ; Dígito 2: Dezenas de segundos (reg_dez_seg, posicao_ajuste = 1)
    lds reg_aux, modo_atual
    cpi reg_aux, MODO_AJUSTE
    brne set_normal2
    lds reg_aux, posicao_ajuste
    cpi reg_aux, 1
    brne set_normal2
    lds reg_aux, display_piscando
    andi reg_aux, 0x10  
    breq set_blank2
set_normal2:
    mov reg_temp, reg_dez_seg
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b00100000
    rjmp set_ctrl2
set_blank2:
    clr reg_temp
    out PORT_BCD, reg_temp  ; Limpa PORT_BCD
    ldi reg_temp, 0
set_ctrl2:
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Dígito 3: Unidades de minutos (reg_uni_min, posicao_ajuste = 2)
    lds reg_aux, modo_atual
    cpi reg_aux, MODO_AJUSTE
    brne set_normal3
    lds reg_aux, posicao_ajuste
    cpi reg_aux, 2
    brne set_normal3
    lds reg_aux, display_piscando
    andi reg_aux, 0x10  
    breq set_blank3
set_normal3:
    mov reg_temp, reg_uni_min
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b01000000
    rjmp set_ctrl3
set_blank3:
    clr reg_temp
    out PORT_BCD, reg_temp  ; Limpa PORT_BCD
    ldi reg_temp, 0
set_ctrl3:
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Dígito 4: Dezenas de minutos (reg_dez_min, posicao_ajuste = 3)
    lds reg_aux, modo_atual
    cpi reg_aux, MODO_AJUSTE
    brne set_normal4
    lds reg_aux, posicao_ajuste
    cpi reg_aux, 3
    brne set_normal4
    lds reg_aux, display_piscando
    andi reg_aux, 0x10  
    breq set_blank4
set_normal4:
    mov reg_temp, reg_dez_min
    out PORT_BCD, reg_temp
    ldi reg_temp, 0b10000000 
    rjmp set_ctrl4
set_blank4:
    clr reg_temp
    out PORT_BCD, reg_temp  ; Limpa PORT_BCD
    ldi reg_temp, 0
set_ctrl4:
    out PORT_CTRL, reg_temp
    rcall atraso_display

    ; Limpa PORT_CTRL
    clr reg_temp
    out PORT_CTRL, reg_temp

    pop reg_dez_min
    pop reg_uni_min
    pop reg_dez_seg
    pop reg_uni_seg
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
	; reg_temp é minutos ou segundos
    cp reg_temp, reg_unidades   ; Vê se temp é menor que 10
    brlo div_pronto				; Se for, não precisa separar nada
    sub reg_temp, reg_unidades  ; Se não, subtrai 10
    inc reg_dezenas				; Incrementa as dezenas
    rjmp div_loop				; Repete
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

	clr reg_temp
    sts bloqueio_reset, reg_temp

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
	; Atualizações do temporizador (1 vez por segundo)
    lds reg_temp, contador_overflow
    cpi reg_temp, NUMERO_OVERFLOWS
    brne fim_overflow
    
    ; Desativa o bloqueio do START após 1 segundo
    clr reg_temp
    sts bloqueio_start, reg_temp

salvar_contador_pisca:
    sts contador_pisca, reg_temp
    
    ; Verifica se passou 1 segundo (100 overflows)
    lds reg_temp, contador_overflow
    cpi reg_temp, NUMERO_OVERFLOWS
    brne fim_overflow					; Se não, acaba

    ; Se sim, zera contador de overflows após 1 segundo e incrementa o relógio
    clr reg_temp
    sts contador_overflow, reg_temp

    ; ========= ATUALIZA O RELÓGIO PRINCIPAL =========
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
    inc reg_dezenas							; Incrementa segundos
    cpi reg_dezenas, 60						; Verifica se passou de 59
    brlo salvar_segundos_cronometro			; Se não, salva
    clr reg_dezenas							; Se sim, zera segundos
    
    lds reg_unidades, minutos_cronometro
    inc reg_unidades						; Incrementa minutos
    cpi reg_unidades, 60					; Verifica se passou de 59
    brlo salvar_minutos_cronometro			
    clr reg_unidades						; Se sim, zera minutos

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


; ===================== DADOS EM MEMÓRIA DE PROGRAMA ==============
msg_modo1:				.db "[Modo 1] MM:SS",13,10,0
msg_modo2_zero:			.db "[MODO 2] ZERO",13,10,0
msg_modo2_start:		.db "[MODO 2] START",13,10,0
msg_modo2_reset:		.db "[MODO 2] RESET",13,10,0
msg_modo3_uni_seg:		.db "[MODO 3] Ajustando a unidade dos segundos",13,10,0
msg_modo3_dez_seg:		.db "[MODO 3] Ajustando a dezena dos segundos",13,10,0
msg_modo3_uni_min:		.db "[MODO 3] Ajustando a unidade dos minutos",13,10,0
msg_modo3_dez_min:		.db "[MODO 3] Ajustando a dezena dos minutos",13,10,0

; ===================== ROTINAS PARA UART =====================
; Envia um caractere pela UART (caractere em reg_temp)
uart_enviar:
    push reg_aux
uart_espera:
    lds reg_aux, UCSR0A
    sbrs reg_aux, UDRE0          ; Espera buffer de transmissão vazio
    rjmp uart_espera
    sts UDR0, reg_temp           ; Envia o caractere
    pop reg_aux
    ret

; Envia uma string pela UART (endereço em Z)
uart_enviar_string:
    push reg_temp
uart_string_loop:
    lpm reg_temp, Z+             ; Carrega caractere da memória de programa
    cpi reg_temp, 0              ; Verifica fim da string (terminada com null)
    breq uart_string_fim
    rcall uart_enviar            ; Envia o caractere
    rjmp uart_string_loop
uart_string_fim:
    pop reg_temp
    ret

; Converte número de 0-9 para ASCII (entrada em reg_temp, saída em reg_temp)
numero_para_ascii:
    subi reg_temp, -'0'          ; Adiciona '0' ao valor
    ret	
