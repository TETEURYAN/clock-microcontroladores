# ⏱️ Relógio Digital com ATmega328P | Microcontroladores

Projeto de um relógio digital multifuncional desenvolvido em Assembly para o microcontrolador **ATmega328P**, como parte da disciplina de **Microcontroladores e Aplicações**. O sistema implementa três modos de operação: relógio, cronômetro e ajuste de hora, com suporte a entrada por botões e feedback sonoro via buzzer.

<p align="center">
  <img src="https://user-images.githubusercontent.com/91018438/204195385-acc6fcd4-05a7-4f25-87d1-cb7d5cc5c852.png" alt="animated" />
</p>

## 👥 Integrantes

<center>

    Matheus Ryan | Lucas Heron | Rafael Luciano
 </center>

<center>
  
---


## 📦 Visão Geral

- 🔧 **Plataforma:** ATmega328P  
- 🖥️ **Displays:** 4 dígitos de 7 segmentos multiplexados (saída BCD)  
- 🎚️ **Botões:** MODE (PC2), START (PC1), RESET (PC0)  
- 🔊 **Buzzer:** PC3 para feedback audível  
- 💬 **UART Serial:** 9600 bps, 8N1

---

## ⚙️ Modos de Operação

### 1. ⏰ Modo Relógio (`MODO_RELOGIO`)

- Exibe a hora atual no formato **MM:SS**
- Atualização automática a cada segundo

**Controles:**
- `MODE`: alterna para o modo cronômetro
- `START` e `RESET`: sem função neste modo

  ![image](https://github.com/user-attachments/assets/b636519b-6480-4ae6-8087-ad867b5555af)


---

### 2. ⏱️ Modo Cronômetro (`MODO_CRONOMETRO`)

- Conta o tempo decorrido (intervalo de 00:00 a 59:59)

**Controles:**
- `START`: inicia/pausa a contagem
- `RESET` (com contagem pausada): zera o cronômetro
- `MODE`: alterna para o modo ajuste

  ![image](https://github.com/user-attachments/assets/e8a302e6-29fd-4e52-b504-4764bbf61f73)


---

### 3. ⚙️ Modo Ajuste de Hora (`MODO_AJUSTE`)

- Permite configurar o horário do relógio

**Controles:**
- `START`: navega entre os dígitos (unid. seg → dez. seg → unid. min → dez. min)
- `RESET`: incrementa o valor do dígito selecionado
- `MODE`: retorna ao modo relógio

O dígito selecionado **pisca** a cada 0,3s para facilitar a visualização

![image](https://github.com/user-attachments/assets/da6ef012-81cc-4bab-aef2-09ad3f3aa3b9)


---

## 🎛️ Funcionalidades Extras

### ✅ Controle de Botões

- **Debounce** implementado para todos os botões
- **Bloqueio automático** após mudanças de modo para evitar múltiplos acionamentos acidentais

### 🔊 Feedback Audível

- Buzzer emite **bip curto** ao pressionar qualquer botão (ação confirmada)

---

## 🛰️ Comunicação Serial (UART)

Através da UART (9600 bps), o sistema envia mensagens informativas sobre:

- 🕹️ Modo atual selecionado
- ▶️ Ações executadas (`start`, `stop`, `reset`)
- 🎯 Posição ativa no modo de ajuste

---

## 🧠 Destaques Técnicos

- Multiplexação eficiente de displays com apenas 4 pinos de controle
- Uso preciso do **Timer0** para temporização e contagem
- Otimização do consumo de recursos do microcontrolador
- Implementação estruturada em Assembly com uso de:
  - Interrupções
  - Máscaras e deslocamentos de bits
  - Controle de fluxo com salto condicional
  - Manipulação direta de registradores

---

## 📂 Estrutura do Código

Código organizado em seções claras para facilitar a leitura e manutenção:

- 🧾 Definições de hardware
- 🧠 Variáveis e registradores
- 📌 Vetores de interrupção
- 🔄 Rotinas principais
- 🖥️ Controle dos displays
- 🔧 Lógica de modos e navegação

---

## ❗ Rotinas Importantes

### Debounce
 ```asm
debounce:
    ldi r31, byte3(16 * 1000 * 300 / 5)
    ldi r30, high(16 * 1000 * 300 / 5)
    ldi r29, low(16 * 1000 * 300 / 5)
debounce_loop:
    subi r29, 1
    sbci r30, 0
    sbci r31, 0
    brcc debounce_loop
    ret
  ```

### Buzzer

```asm
apitar_buzzer:
    lds reg_temp, PORTC_ADDR
    ori reg_temp, (1 << BUZZER_BIT)
    sts PORTC_ADDR, reg_temp

    ldi reg_temp, 150
bip_delay_outer:
    ldi reg_aux, 255
bip_delay_inner:
    dec reg_aux
    brne bip_delay_inner
    dec reg_temp
    brne bip_delay_outer

    andi reg_temp, ~(1 << BUZZER_BIT)
    sts PORTC_ADDR, reg_temp
    ret

```

## ⚠️ Observações

- O sistema valida e limita corretamente os valores de minutos e segundos (00–59)
- Proteções contra:
  - Pressionamento múltiplo não intencional
  - Incrementos acidentais no modo ajuste
  - Troca de modo indesejada
