#!/bin/bash
# =============================================================================
# МОДУЛЬ FAIL2BAN: m_40_f2b.sh  — ПОЛНОСТЬЮ ПЕРЕПИСАН
# =============================================================================
# Fail2Ban — программа, которая автоматически блокирует IP-адреса,
# если с них приходит слишком много попыток взлома или сканирования.
#
# ДЛЯ ЧАЙНИКОВ: Представь что у тебя есть охранник, который видит
# злоумышленников (которые пытаются угадать пароль SSH или сканируют VPN)
# и автоматически «закрывает им дверь» на определённое время.
#
# ИСПРАВЛЕННЫЕ БАГИ:
#   - БАГ #6: Больше НЕ перезаписывает jail.local при каждом вызове
#   - БАГ #20: Проверяет конфиг через fail2ban-client -t перед рестартом
#   - Использует современный формат jail.d/ (отдельные файлы на jail)
#   - Правильно определяет путь к логам (учитывает настройки из m_20_config.sh)
#   - Умная инициализация: не сломает чужие настройки в jail.local
# =============================================================================

# --- Переменные модуля ---
F2B_CONF=$(ensure_module_config "f2b")
F2B_WHITELIST="${F2B_CONF}/whitelist.txt"
F2B_MAXRETRY_FILE="${F2B_CONF}/maxretry.txt"
F2B_FINDTIME_FILE="${F2B_CONF}/findtime.txt"
F2B_BANTIME_FILE="${F2B_CONF}/bantime.txt"

# Директория для наших jail-файлов (современный подход)
F2B_JAIL_D="/etc/fail2ban/jail.d"
F2B_FILTER_D="${F2B_FILTER_DIR:-/etc/fail2ban/filter.d}"
F2B_DON_JAIL="${F2B_JAIL_D}/donmatteo.conf"
F2B_DON_JAIL_SSH="${F2B_JAIL_D}/donmatteo-ssh.conf"
F2B_DON_JAIL_NGINX="${F2B_JAIL_D}/donmatteo-nginx.conf"

# --- Дефолтные значения ---
[[ ! -f "$F2B_MAXRETRY_FILE" ]] && echo "3" > "$F2B_MAXRETRY_FILE"
[[ ! -f "$F2B_FINDTIME_FILE" ]] && echo "600" > "$F2B_FINDTIME_FILE"
[[ ! -f "$F2B_BANTIME_FILE" ]]  && echo "86400" > "$F2B_BANTIME_FILE"
[[ ! -f "$F2B_WHITELIST" ]]     && echo "127.0.0.1/8" > "$F2B_WHITELIST"

# =============================================================================
# УТИЛИТЫ
# =============================================================================

# Безопасный рестарт Fail2Ban с ТЕСТОМ конфига (БАГ #20 FIX)
# ДЛЯ ЧАЙНИКОВ: Перед перезапуском проверяем что конфиг не содержит ошибок.
# Это предотвращает ситуацию когда ты теряешь SSH из-за кривого конфига.
f2b_safe_restart() {
    echo -ne "${CYAN}[*] Проверка конфигурации Fail2Ban...${NC}"

    # Тест через fail2ban-client (БАГ #20 FIX)
    if fail2ban-client -t >/dev/null 2>&1; then
        echo -e " ${GREEN}[OK]${NC}"
    else
        echo -e " ${RED}[ОШИБКА!]${NC}"
        echo -e "${RED}[!] В конфиге Fail2Ban есть ошибки. Рестарт отменён!${NC}"
        echo -e "${YELLOW}Запустите: fail2ban-client -t для подробностей${NC}"
        fail2ban-client -t 2>&1 | tail -20
        return 1
    fi

    echo -ne "${CYAN}[*] Перезапуск Fail2Ban...${NC}"
    if systemctl restart fail2ban 2>/dev/null; then
        sleep 2
        if systemctl is-active --quiet fail2ban; then
            echo -e " ${GREEN}[OK]${NC}"
            return 0
        fi
    fi

    echo -e " ${RED}[ОШИБКА!]${NC}"
    echo -e "${RED}Логи: journalctl -u fail2ban -n 20${NC}"
    return 1
}

# Читает настройку
f2b_get_setting() {
    local file="$1"; local default="$2"
    cat "$file" 2>/dev/null || echo "$default"
}

# Определяем где находится лог аутентификации (разные дистрибутивы)
f2b_detect_auth_log() {
    for log in /var/log/auth.log /var/log/secure /var/log/messages; do
        [[ -f "$log" ]] && echo "$log" && return 0
    done
    # Systemd journald — fail2ban умеет читать через backend
    echo "%(syslog_facility)s"
    return 0
}

# =============================================================================
# УСТАНОВКА FAIL2BAN (БАГ #6 FIX: не ломаем существующий jail.local!)
# =============================================================================
install_fail2ban() {
    echo -e "${CYAN}[*] Установка и настройка Fail2Ban...${NC}"

    # Устанавливаем если нет
    if ! command -v fail2ban-server >/dev/null 2>&1; then
        smart_apt_install "fail2ban" "python3"
    fi

    # Убеждаемся что rsyslog / systemd пишет логи аутентификации
    if ! systemctl is-active --quiet rsyslog 2>/dev/null; then
        smart_apt_install "rsyslog"
        systemctl enable --now rsyslog >/dev/null 2>&1 || true
    fi

    # Создаём директорию для наших конфигов
    mkdir -p "$F2B_JAIL_D" "$F2B_FILTER_D"

    # Создаём базовый jail.local ТОЛЬКО если его нет (БАГ #6 FIX!)
    if [[ ! -f /etc/fail2ban/jail.local ]]; then
        echo -e "${CYAN}[*] Создание базового jail.local...${NC}"
        cat > /etc/fail2ban/jail.local <<'EOF'
# jail.local — базовые настройки Fail2Ban
# Наши jail-файлы находятся в /etc/fail2ban/jail.d/donmatteo*.conf
# НЕ редактируй этот файл вручную — используй меню менеджера

[DEFAULT]
# Серверный backend (systemd-journald для современных систем)
backend = auto
EOF
    fi

    local maxretry; maxretry=$(f2b_get_setting "$F2B_MAXRETRY_FILE" "3")
    local findtime; findtime=$(f2b_get_setting "$F2B_FINDTIME_FILE" "600")
    local bantime;  bantime=$(f2b_get_setting "$F2B_BANTIME_FILE" "86400")
    local whitelist; whitelist=$(cat "$F2B_WHITELIST" 2>/dev/null | tr '\n' ' ')
    local auth_log; auth_log=$(f2b_detect_auth_log)
    local nginx_log_dir="${NGINX_LOGS_DIR:-/opt/remnawave/nginx_logs}"

    # --- 1. Создаём наши фильтры ---
    write_f2b_filters

    # --- 2. SSH Jail ---
    echo -e "${CYAN}[*] Настройка SSH-защиты...${NC}"
    cat > "$F2B_DON_JAIL_SSH" <<EOF
# DonMatteo: SSH Brute-Force Protection — автоматически обновляется менеджером
[sshd]
enabled   = true
port      = ssh
filter    = sshd
logpath   = ${auth_log}
backend   = auto
maxretry  = ${maxretry}
findtime  = ${findtime}
bantime   = ${bantime}
ignoreip  = ${whitelist} 127.0.0.1/8 ::1
EOF

    # --- 3. Nginx Jails (для нашей панели) ---
    echo -e "${CYAN}[*] Настройка Nginx-защиты...${NC}"
    cat > "$F2B_DON_JAIL_NGINX" <<EOF
# DonMatteo: Nginx Protection — автоматически обновляется менеджером

# Защита от сканеров в Nginx Stream
[nginx-stream-scanners]
enabled   = true
port      = all
filter    = donmatteo-stream-scanner
logpath   = ${nginx_log_dir}/stream_scanners.log
maxretry  = 2
findtime  = 300
bantime   = 86400
ignoreip  = ${whitelist} 127.0.0.1/8

# Защита от HTTP-сканеров и ботов
[nginx-http-scan]
enabled   = true
port      = http,https
filter    = donmatteo-nginx-scan
logpath   = ${nginx_log_dir}/access.log
maxretry  = ${maxretry}
findtime  = ${findtime}
bantime   = ${bantime}
ignoreip  = ${whitelist} 127.0.0.1/8

# Белый список для порта панели ${PANEL_PORT:-2222}
[nginx-panel-whitelist]
enabled   = false
EOF

    # --- 4. Активируем и запускаем ---
    systemctl enable fail2ban >/dev/null 2>&1
    f2b_safe_restart && echo -e "${GREEN}[✓] Fail2Ban установлен и работает!${NC}"
}

# =============================================================================
# ФИЛЬТРЫ FAIL2BAN (улучшенные regex для наших логов)
# =============================================================================
write_f2b_filters() {
    # Фильтр для Nginx Stream сканеров
    cat > "${F2B_FILTER_D}/donmatteo-stream-scanner.conf" <<'EOF'
# DonMatteo: Nginx Stream Scanner Filter
# Ловит сканеры и боты в потоковом прокси Nginx
[Definition]
failregex = ^<HOST>.* "(?:GET|POST|HEAD|CONNECT|OPTIONS|TRACE)\s
            ^\[stream_ban\] .*client: <HOST>
            ^.*\[TLS\].*handshake_failure.*<HOST>
datepattern = %%d/%%b/%%Y:%%H:%%M:%%S %%z
             %%Y-%%m-%%dT%%H:%%M:%%S
ignoreregex =
EOF

    # Фильтр для Nginx HTTP сканеров
    cat > "${F2B_FILTER_D}/donmatteo-nginx-scan.conf" <<'EOF'
# DonMatteo: Nginx HTTP Scanner Filter
# Ловит сканеры портов, уязвимостей и плохие боты
[Definition]
failregex = ^<HOST> -.*"(?:GET|POST|HEAD).*/(?:wp-admin|\.env|\.git|\.php|phpinfo|xmlrpc|shell|cmd|exec|eval|etc/passwd|/admin|/login|/wp-login)
            ^<HOST> -.*HTTP/(1\.0|1\.1|2\.0)" (?:400|404|403|444|499|500)
            ^<HOST> -.*"(?:zgrab|sqlmap|nikto|masscan|nmap|dirbuster|gobuster|hydra)"
datepattern = %%d/%%b/%%Y:%%H:%%M:%%S %%z
ignoreregex = ^<HOST> -.*"/healthcheck"
              ^<HOST> -.*"/favicon\.ico"
              ^<HOST> -.*"/robots\.txt"
EOF

    echo -e "${GREEN}[✓] Фильтры Fail2Ban обновлены.${NC}"
}

# =============================================================================
# УПРАВЛЕНИЕ БАНАМИ
# =============================================================================
f2b_ban_ip() {
    local ip; ip=$(ui_input_ip "Введите IP для бана")
    [[ -z "$ip" ]] && return

    local jail; jail=$(ui_input "Jail для бана" "sshd")
    if fail2ban-client set "$jail" banip "$ip" >/dev/null 2>&1; then
        log_audit "F2B_BAN" "${ip} в jail ${jail}"
        echo -e "${GREEN}[+] IP ${ip} забанен в jail ${jail}!${NC}"
    else
        echo -e "${RED}[!] Не удалось. Jail '${jail}' существует?${NC}"
    fi
    sleep 1
}

f2b_unban_ip() {
    # Показываем забаненных
    echo -e "${YELLOW}Забаненные IP:${NC}"
    fail2ban-client status 2>/dev/null | grep -oP "'[^']+'" | \
    while read -r jail_name; do
        jail_name="${jail_name//\'/}"
        local banned; banned=$(fail2ban-client status "$jail_name" 2>/dev/null | grep "Banned IP")
        [[ -n "$banned" ]] && echo -e "  ${CYAN}[$jail_name]${NC}: $banned"
    done

    local ip; ip=$(ui_input_ip "IP для разбана")
    [[ -z "$ip" ]] && return

    # Разбан во всех jail
    local unbanned=false
    fail2ban-client status 2>/dev/null | grep -oP "'[^']+'" | \
    while read -r jail_name; do
        jail_name="${jail_name//\'/}"
        if fail2ban-client set "$jail_name" unbanip "$ip" >/dev/null 2>&1; then
            unbanned=true
            log_audit "F2B_UNBAN" "${ip} из jail ${jail_name}"
            echo -e "${GREEN}[+] ${ip} разбанен в ${jail_name}!${NC}"
        fi
    done
    sleep 1
}

# =============================================================================
# УПРАВЛЕНИЕ БЕЛЫМ СПИСКОМ (WHITELIST)
# =============================================================================
menu_f2b_whitelist() {
    while true; do
        clear
        ui_header "✅" "БЕЛЫЙ СПИСОК (WHITELIST)"
        echo -e " ${GRAY}IP из этого списка Fail2Ban никогда не забанит.${NC}\n"
        local i=1
        declare -a LIST_ARRAY
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            echo -e "  ${YELLOW}[$i]${NC} $entry"
            LIST_ARRAY[$i]="$entry"
            ((i++))
        done < "$F2B_WHITELIST" 2>/dev/null
        [[ $i -eq 1 ]] && echo -e "  ${GRAY}(Список пуст)${NC}"

        ui_sep
        echo -e " ${GREEN}A.${NC} ➕ Добавить IP/подсеть"
        echo -e " ${RED}D.${NC} ➖ Удалить по номеру"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty

        case "${ch^^}" in
            A)
                read -rp "Введите IP или подсеть (напр. 192.168.1.1 или 10.0.0.0/24): " new_entry < /dev/tty
                if [[ -n "$new_entry" ]] && ! grep -qxF "$new_entry" "$F2B_WHITELIST" 2>/dev/null; then
                    echo "$new_entry" >> "$F2B_WHITELIST"
                    log_audit "F2B_WHITELIST_ADD" "$new_entry"
                    # Обновляем jail конфиги с новым whitelist
                    install_fail2ban >/dev/null 2>&1 &
                    echo -e "${GREEN}[+] Добавлено: ${new_entry}${NC}"; sleep 1
                fi ;;
            D)
                read -rp "Номер для удаления: " del_num < /dev/tty
                if [[ "$del_num" =~ ^[0-9]+$ ]] && [[ -n "${LIST_ARRAY[$del_num]:-}" ]]; then
                    local entry_to_del="${LIST_ARRAY[$del_num]}"
                    # Атомарная замена файла (БАГ #14 FIX)
                    local tmpf; tmpf=$(safe_tmp "f2b_wl")
                    grep -v -x -F "$entry_to_del" "$F2B_WHITELIST" > "$tmpf"
                    mv "$tmpf" "$F2B_WHITELIST"
                    log_audit "F2B_WHITELIST_DEL" "$entry_to_del"
                    echo -e "${GREEN}[+] Удалено!${NC}"; sleep 1
                fi ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# НАСТРОЙКА ПАРАМЕТРОВ FAIL2BAN
# =============================================================================
menu_f2b_settings() {
    while true; do
        clear
        ui_header "⚙️" "ПАРАМЕТРЫ FAIL2BAN"
        local maxretry; maxretry=$(f2b_get_setting "$F2B_MAXRETRY_FILE" "3")
        local findtime; findtime=$(f2b_get_setting "$F2B_FINDTIME_FILE" "600")
        local bantime;  bantime=$(f2b_get_setting "$F2B_BANTIME_FILE" "86400")

        echo -e " ${YELLOW}1.${NC} MaxRetry  — попыток до бана:       ${CYAN}${maxretry}${NC}"
        echo -e " ${YELLOW}2.${NC} FindTime  — окно поиска (сек):     ${CYAN}${findtime}${NC} $(( findtime/60 )) мин"
        echo -e " ${YELLOW}3.${NC} BanTime   — время бана (сек):      ${CYAN}${bantime}${NC} $(( bantime/3600 )) ч"
        ui_sep
        echo -e " ${MAGENTA}4.${NC} ✅ Применить (пересоздать конфиги)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1) local v; v=$(ui_input "MaxRetry (попыток до бана)" "$maxretry")
               [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" > "$F2B_MAXRETRY_FILE"; sleep 1 ;;
            2) local v; v=$(ui_input "FindTime (секунды, окно поиска)" "$findtime")
               [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" > "$F2B_FINDTIME_FILE"; sleep 1 ;;
            3) local v; v=$(ui_input "BanTime (секунды, -1 = навсегда)" "$bantime")
               [[ "$v" =~ ^-?[0-9]+$ ]] && echo "$v" > "$F2B_BANTIME_FILE"; sleep 1 ;;
            4) install_fail2ban; ui_pause ;;
            0) return ;;
        esac
    done
}

# --- Просмотр статуса всех jail ---
show_f2b_status() {
    clear
    ui_header "📊" "СТАТУС FAIL2BAN"
    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${RED}[!] Fail2Ban не запущен!${NC}"
        ui_pause; return
    fi

    fail2ban-client status 2>/dev/null | grep -oP "'[^']+'" | \
    while read -r jail_name; do
        jail_name="${jail_name//\'/}"
        echo -e "\n${CYAN}━━━ Jail: ${BOLD}${jail_name}${NC}${CYAN} ━━━${NC}"
        fail2ban-client status "$jail_name" 2>/dev/null | \
            grep -E "Currently banned|Total banned|Banned IP"
    done
    echo ""
    ui_pause
}

# --- Просмотр логов Fail2Ban ---
show_f2b_log() {
    clear
    echo -e "${YELLOW}=== Последние 50 строк Fail2Ban лога ===${NC}\n"
    journalctl -u fail2ban --no-pager -n 50 2>/dev/null || \
        tail -n 50 /var/log/fail2ban.log 2>/dev/null || \
        echo -e "${GRAY}(Лог недоступен)${NC}"
    ui_pause
}

# =============================================================================
# ГЛАВНОЕ МЕНЮ FAIL2BAN
# =============================================================================
menu_f2b() {
    while true; do
        clear
        ui_header "🔒" "FAIL2BAN — ЗАЩИТА ОТ ВЗЛОМЩИКОВ" "$(get_f2b_status)"
        local f2b_active; f2b_active=$(systemctl is-active fail2ban 2>/dev/null)
        echo -e " ${GREEN}1.${NC} 📥 Установить / Переустановить Fail2Ban"
        echo -e " ${YELLOW}2.${NC} 📊 Статус и забаненные IP"
        echo -e " ${YELLOW}3.${NC} ⚙️  Параметры (MaxRetry / FindTime / BanTime)"
        echo -e " ${YELLOW}4.${NC} ✅ Белый список (Whitelist)"
        ui_sep
        echo -e " ${RED}5.${NC} 🔨 Забанить IP вручную"
        echo -e " ${GREEN}6.${NC} 🔓 Разбанить IP"
        echo -e " ${MAGENTA}7.${NC} 🔄 Обновить фильтры (перечитать конфиг Nginx путей)"
        echo -e " ${CYAN}8.${NC} 📋 Посмотреть лог Fail2Ban"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " choice < /dev/tty
        case "$choice" in
            1) install_fail2ban; ui_pause ;;
            2) show_f2b_status ;;
            3) menu_f2b_settings ;;
            4) menu_f2b_whitelist ;;
            5) f2b_ban_ip ;;
            6) f2b_unban_ip ;;
            7)
                echo -e "${CYAN}[*] Обновление фильтров и путей Nginx...${NC}"
                write_f2b_filters
                install_fail2ban
                ui_pause ;;
            8) show_f2b_log ;;
            0) return ;;
        esac
    done
}
