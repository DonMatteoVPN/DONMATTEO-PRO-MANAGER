#!/bin/bash
# =============================================================================
# МОДУЛЬ UFW (СЕТЕВОЙ ЭКРАН): m_30_ufw.sh
# =============================================================================
# Управляет UFW (Uncomplicated Firewall) — программой защиты от чужих подключений.
# Также настраивает продвинутую Anti-DDoS защиту через iptables.
#
# ДЛЯ ЧАЙНИКОВ: UFW — это «охранник» твоего сервера. Он разрешает нужные
# подключения (SSH, порты VPN) и блокирует всё остальное. Anti-DDoS правила
# защищают от слишком большого количества запросов с одного IP-адреса.
#
# ИСПРАВЛЕННЫЕ БАГИ:
#   - БАГ #7: Python-блок теперь ЗАПИСЫВАЕТ before.rules (был нефункционален!)
#   - БАГ #4: Экранирование пользовательского ввода в комментариях к правилу
#   - БАГ #10: После ufw reset — немедленно разрешаем SSH до любой паузы
# =============================================================================

# --- Переменные модуля ---
UFW_CONF=$(ensure_module_config "ufw")
LIMIT_CONN_FILE="${UFW_CONF}/limit_conn_ports.txt"
LIMIT_RATE_FILE="${UFW_CONF}/limit_rate_ports.txt"
LIMIT_CONN_VAL_FILE="${UFW_CONF}/limit_conn_val.txt"
LIMIT_RATE_VAL_FILE="${UFW_CONF}/limit_rate_val.txt"

# --- Инициализация файлов дефолтами ---
[[ ! -f "$LIMIT_CONN_FILE" ]] && echo "" > "$LIMIT_CONN_FILE"
[[ ! -f "$LIMIT_RATE_FILE" ]] && echo "" > "$LIMIT_RATE_FILE"
[[ ! -f "$LIMIT_CONN_VAL_FILE" ]] && echo "25" > "$LIMIT_CONN_VAL_FILE"
[[ ! -f "$LIMIT_RATE_VAL_FILE" ]] && echo "200/minute burst 50" > "$LIMIT_RATE_VAL_FILE"

# =============================================================================
# ГЛОБАЛЬНАЯ НАСТРОЙКА UFW
# =============================================================================
ufw_global_setup() {
    echo -e "${CYAN}[*] Базовая настройка UFW...${NC}"
    ufw --force reset > /dev/null 2>&1

    # ДЛЯ ЧАЙНИКОВ: КРИТИЧЕСКИ ВАЖНО разрешить SSH ДО любых других операций!
    # Иначе после reset мы потеряем доступ к серверу. Это «страховка».
    local ssh_ports
    ssh_ports=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [[ -z "$ssh_ports" ]] && ssh_ports="22"
    for p in $ssh_ports; do
        ufw allow "${p}/tcp" comment "SSH-emergency" >/dev/null 2>&1
    done

    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1

    echo -e "${GREEN}[✓] UFW базово настроен. SSH разрешён на портах: ${ssh_ports}${NC}"
}

# =============================================================================
# ANTI-DDOS ЗАЩИТА (БАГ #7 FIX: Python теперь ЗАПИСЫВАЕТ файл!)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: «Anti-DDoS» — это правила, которые блокируют атаки, когда
# кто-то отправляет ОЧЕНЬ много запросов за короткое время.
# CONNLIMIT = лимит одновременных подключений с одного IP
# RATELIMIT = лимит скорости новых подключений
apply_antiddos_rules() {
    local conn_ports; conn_ports=$(cat "$LIMIT_CONN_FILE" 2>/dev/null)
    local rate_ports; rate_ports=$(cat "$LIMIT_RATE_FILE" 2>/dev/null)
    local conn_val; conn_val=$(cat "$LIMIT_CONN_VAL_FILE" 2>/dev/null || echo "25")
    local rate_val; rate_val=$(cat "$LIMIT_RATE_VAL_FILE" 2>/dev/null || echo "200/minute burst 50")
    
    [[ -z "$conn_ports" && -z "$rate_ports" ]] && return 0

    echo -e "${CYAN}[*] Применяем Anti-DDoS правила к before.rules...${NC}"

    # КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ (БАГ #7):
    # Используем Python3 с явной записью файла. Ранее файл только читался, но никогда не сохранялся!
    python3 - <<PYEOF
import re, sys

BEFORE_RULES = '/etc/ufw/before.rules'
try:
    with open(BEFORE_RULES, 'r') as f:
        content = f.read()
except Exception as e:
    print(f"[!] Ошибка чтения before.rules: {e}")
    sys.exit(1)

MARKER_START = '# --- DONMATTEO ANTI-DDOS START ---'
MARKER_END   = '# --- DONMATTEO ANTI-DDOS END ---'

# Удаляем предыдущий блок если есть
if MARKER_START in content:
    content = re.sub(
        r'# --- DONMATTEO ANTI-DDOS START ---.*?# --- DONMATTEO ANTI-DDOS END ---\n?',
        '',
        content,
        flags=re.DOTALL
    )

# Формируем новый блок правил
new_rules = [MARKER_START]

# CONNLIMIT правила
conn_ports = """${conn_ports}""".strip()
conn_val   = """${conn_val}""".strip()
if conn_ports:
    for port in conn_ports.split():
        port = port.strip()
        if not port or not port.isdigit():
            continue
        new_rules.append(f'-A ufw-before-input -p tcp --dport {port} -m connlimit --connlimit-above {conn_val} -j REJECT --reject-with tcp-reset')
        new_rules.append(f'# CONNLIMIT: max {conn_val} соединений с одного IP на порт {port}')

# RATELIMIT правила
rate_ports = """${rate_ports}""".strip()
rate_val   = """${rate_val}""".strip()
if rate_ports:
    # Парсим: "200/minute burst 50" → limit=200/min, burst=50
    limit_match = __import__('re').match(r'(\d+)/(minute|second).*burst\s+(\d+)', rate_val)
    if limit_match:
        limit_num  = limit_match.group(1)
        limit_unit = limit_match.group(2)
        burst_num  = limit_match.group(3)
        for port in rate_ports.split():
            port = port.strip()
            if not port or not port.isdigit():
                continue
            new_rules.append(f'-A ufw-before-input -p tcp --dport {port} -m state --state NEW -m limit --limit {limit_num}/{limit_unit} --limit-burst {burst_num} -j ACCEPT')
            new_rules.append(f'-A ufw-before-input -p tcp --dport {port} -m state --state NEW -j DROP')
            new_rules.append(f'# RATELIMIT: порт {port} — {limit_num}/{limit_unit}, burst {burst_num}')

new_rules.append(MARKER_END)
new_block = '\n'.join(new_rules) + '\n'

# Вставляем перед строкой COMMIT (финал правил)
if 'COMMIT' in content:
    content = content.replace('COMMIT', new_block + 'COMMIT', 1)
else:
    content = content + new_block

# === КРИТИЧЕСКИ ВАЖНО: ЗАПИСЫВАЕМ ФАЙЛ! (БАГ #7 FIX) ===
try:
    with open(BEFORE_RULES, 'w') as f:
        f.write(content)
    print('[+] before.rules успешно обновлён!')
except Exception as e:
    print(f'[!] Ошибка записи before.rules: {e}')
    sys.exit(1)
PYEOF

    if [[ $? -eq 0 ]]; then
        # Перезагружаем UFW для применения изменений
        ufw --force disable >/dev/null 2>&1
        ufw --force enable >/dev/null 2>&1
        echo -e "${GREEN}[✓] Anti-DDoS правила применены!${NC}"
    else
        echo -e "${RED}[!] Ошибка применения Anti-DDoS правил.${NC}"
    fi
}

# Удаляет Anti-DDoS блок из before.rules
remove_antiddos_rules() {
    python3 - <<'PYEOF'
import re
BEFORE_RULES = '/etc/ufw/before.rules'
try:
    with open(BEFORE_RULES, 'r') as f:
        content = f.read()
    content = re.sub(
        r'# --- DONMATTEO ANTI-DDOS START ---.*?# --- DONMATTEO ANTI-DDOS END ---\n?',
        '', content, flags=re.DOTALL
    )
    with open(BEFORE_RULES, 'w') as f:
        f.write(content)
    print('[+] Anti-DDoS правила удалены из before.rules')
except Exception as e:
    print(f'[!] Ошибка: {e}')
PYEOF
    ufw --force disable >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1
}

# =============================================================================
# УПРАВЛЕНИЕ ПОРТАМИ (БАГ #4 FIX: экранирование комментария)
# =============================================================================
ufw_add_port() {
    local port; port=$(ui_input_port "Введите порт для открытия")
    [[ -z "$port" ]] && return

    echo -e "${CYAN}Протокол: 1) tcp  2) udp  3) tcp+udp${NC}"
    read -rp ">> " proto_ch < /dev/tty
    local proto_str=""
    case "$proto_ch" in
        1) proto_str="/tcp" ;;
        2) proto_str="/udp" ;;
        *)  proto_str="" ;;  # tcp+udp = без суффикса
    esac

    # Запрашиваем комментарий — санитизируем специальные символы (БАГ #4)
    read -rp "Комментарий (необязательно): " raw_comment < /dev/tty
    local comment; comment=$(echo "$raw_comment" | tr -d ';&|`$(){}\\<>' | head -c 64)

    if ufw allow "${port}${proto_str}" comment "${comment:-don-rule}" >/dev/null 2>&1; then
        log_audit "UFW_ADD" "Открыт порт ${port}${proto_str} (${comment})"
        echo -e "${GREEN}[+] Порт ${port}${proto_str} открыт!${NC}"
    else
        echo -e "${RED}[!] Ошибка добавления правила UFW.${NC}"
    fi
    sleep 1
}

ufw_remove_port() {
    local port; port=$(ui_input_port "Введите порт для закрытия")
    [[ -z "$port" ]] && return

    if ufw delete allow "${port}" >/dev/null 2>&1 || \
       ufw delete allow "${port}/tcp" >/dev/null 2>&1 || \
       ufw delete allow "${port}/udp" >/dev/null 2>&1; then
        log_audit "UFW_DEL" "Закрыт порт ${port}"
        echo -e "${GREEN}[+] Правило для порта ${port} удалено.${NC}"
    else
        echo -e "${YELLOW}[!] Правило для порта ${port} не найдено.${NC}"
    fi
    sleep 1
}

# =============================================================================
# НАСТРОЙКА ANTI-DDOS ЛИМИТОВ
# =============================================================================
menu_ufw_antiddos() {
    while true; do
        clear
        ui_header "🛡️" "ANTI-DDOS НАСТРОЙКИ"
        local conn_ports; conn_ports=$(cat "$LIMIT_CONN_FILE" 2>/dev/null)
        local rate_ports; rate_ports=$(cat "$LIMIT_RATE_FILE" 2>/dev/null)
        local conn_val; conn_val=$(cat "$LIMIT_CONN_VAL_FILE" 2>/dev/null || echo "25")
        local rate_val; rate_val=$(cat "$LIMIT_RATE_VAL_FILE" 2>/dev/null || echo "200/minute burst 50")

        echo -e " ${YELLOW}CONNLIMIT${NC} — лимит одновременных соединений с одного IP:"
        echo -e "   Порты: ${CYAN}${conn_ports:-не задано}${NC}"
        echo -e "   Лимит: ${CYAN}${conn_val} соедин.${NC}\n"
        echo -e " ${YELLOW}RATELIMIT${NC} — лимит новых соединений в минуту с одного IP:"
        echo -e "   Порты: ${CYAN}${rate_ports:-не задано}${NC}"
        echo -e "   Лимит: ${CYAN}${rate_val}${NC}\n"

        echo -e " ${GREEN}1.${NC} Задать порты для CONNLIMIT"
        echo -e " ${GREEN}2.${NC} Задать значение CONNLIMIT"
        echo -e " ${GREEN}3.${NC} Задать порты для RATELIMIT"
        echo -e " ${GREEN}4.${NC} Задать значение RATELIMIT"
        ui_sep
        echo -e " ${MAGENTA}5.${NC} ✅ Применить Anti-DDoS правила к UFW"
        echo -e " ${RED}6.${NC} 🗑️  Удалить Anti-DDoS правила"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1) echo -e "${GRAY}Порты через пробел (например: 443 8080 3000):${NC}"
               read -rp ">> " new_ports < /dev/tty
               echo "$new_ports" > "$LIMIT_CONN_FILE"; echo -e "${GREEN}[+] Сохранено!${NC}"; sleep 1 ;;
            2) local val; val=$(ui_input "Макс. одновременных соединений с одного IP" "$conn_val")
               echo "$val" > "$LIMIT_CONN_VAL_FILE"; echo -e "${GREEN}[+] Сохранено!${NC}"; sleep 1 ;;
            3) echo -e "${GRAY}Порты через пробел (например: 80 443):${NC}"
               read -rp ">> " new_ports < /dev/tty
               echo "$new_ports" > "$LIMIT_RATE_FILE"; echo -e "${GREEN}[+] Сохранено!${NC}"; sleep 1 ;;
            4) local val; val=$(ui_input "Лимит (пример: 200/minute burst 50)" "$rate_val")
               echo "$val" > "$LIMIT_RATE_VAL_FILE"; echo -e "${GREEN}[+] Сохранено!${NC}"; sleep 1 ;;
            5) apply_antiddos_rules; ui_pause ;;
            6) remove_antiddos_rules; ui_pause ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# ПРОСМОТР СТАТУСА UFW
# =============================================================================
show_ufw_status() {
    clear
    ui_header "📋" "ТЕКУЩИЙ СТАТУС UFW"
    ufw status verbose 2>/dev/null || echo -e "${RED}UFW не установлен или недоступен.${NC}"
    echo -e "\n${MAGENTA}--- Anti-DDoS блок в before.rules: ---${NC}"
    if grep -q "DONMATTEO ANTI-DDOS" /etc/ufw/before.rules 2>/dev/null; then
        echo -e "${GREEN}[✓] Anti-DDoS правила АКТИВНЫ в before.rules${NC}"
    else
        echo -e "${YELLOW}[!] Anti-DDoS правила не применены${NC}"
    fi
    ui_pause
}

# =============================================================================
# ГЛАВНОЕ МЕНЮ UFW
# =============================================================================
menu_ufw() {
    while true; do
        clear
        ui_header "🔒" "УПРАВЛЕНИЕ UFW (ФАЙЕРВОЛ)" "$(get_ufw_status)"
        echo -e " ${GREEN}1.${NC} ➕ Открыть порт"
        echo -e " ${RED}2.${NC} ➖ Закрыть порт"
        echo -e " ${YELLOW}3.${NC} 📋 Просмотр всех правил"
        ui_sep
        echo -e " ${MAGENTA}4.${NC} 🛡️  Anti-DDoS настройки"
        echo -e " ${RED}5.${NC} 🗑️  Полный сброс UFW (ОПАСНО!)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " choice < /dev/tty
        case "$choice" in
            1) ufw_add_port ;;
            2) ufw_remove_port ;;
            3) show_ufw_status ;;
            4) menu_ufw_antiddos ;;
            5)
                echo -e "${RED}${BOLD}⚠️  ВНИМАНИЕ! Все правила UFW будут удалены!${NC}"
                echo -e "${RED}    SSH разрешён на текущих портах — доступ сохранится.${NC}"
                if ui_confirm "Сбросить UFW?" "N"; then
                    ufw_global_setup
                    log_audit "UFW_RESET" "Полный сброс UFW"
                    echo -e "${GREEN}[+] UFW сброшен к базовым настройкам.${NC}"
                fi
                sleep 2 ;;
            0) return ;;
        esac
    done
}
