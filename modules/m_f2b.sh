#!/bin/bash
# Модуль Fail2Ban (Защита от брутфорса и сканеров)

[[ ! -f "$F2B_RETRY_FILE" ]] && echo "3" > "$F2B_RETRY_FILE"
[[ ! -f "$F2B_FIND_FILE" ]] && echo "600" > "$F2B_FIND_FILE"
[[ ! -f "$F2B_BAN_FILE" ]] && echo "24h" > "$F2B_BAN_FILE"
[[ ! -f "$WHITELIST_FILE" ]] && touch "$WHITELIST_FILE"

install_fail2ban() {
    echo -e "${CYAN}[*] Настройка конфигурации Fail2Ban...${NC}"
    
    if [ ! -f /var/log/auth.log ]; then
        echo -e "${YELLOW}[!] Файл /var/log/auth.log не найден. Создаю и устанавливаю rsyslog...${NC}"
        touch /var/log/auth.log
        chmod 640 /var/log/auth.log
        chown root:adm /var/log/auth.log 2>/dev/null
        smart_apt_install "rsyslog" || echo -e "${YELLOW}[!] Rsyslog не установлен, продолжаем...${NC}"
        systemctl enable rsyslog >/dev/null 2>&1
        systemctl restart rsyslog >/dev/null 2>&1
        sleep 1
    fi
    
    smart_apt_install "fail2ban" || { pause; return 1; }
    
    mkdir -p /opt/remnawave/nginx_logs
    touch /opt/remnawave/nginx_logs/access.log
    touch /opt/remnawave/nginx_logs/stream_scanners.log

    local WL_IPS=$(awk '{print $1}' "$WHITELIST_FILE" | grep -E '^[0-9]' | tr '\n' ' ')
    
    local CUR_RETRY=$(cat "$F2B_RETRY_FILE")
    local CUR_FIND=$(cat "$F2B_FIND_FILE")
    local CUR_BAN=$(cat "$F2B_BAN_FILE")

    cat << 'EOF' > /etc/fail2ban/filter.d/nginx-scanners.conf
[Definition]
failregex = ^<HOST> \- \- \[.*\] "(GET|POST|HEAD|PROPFIND|OPTIONS|PUT|DELETE).*?" (400|401|403|404|405|444)
            ^<HOST>\s*\[[^\]]+\]\s*SNI:".*?"\s*RoutedTo:"unix:/dev/shm/nginx_external\.sock"
ignoreregex =
EOF

    local ACTIVE_SSH=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | paste -sd "," -)
    [[ -z "$ACTIVE_SSH" ]] && ACTIVE_SSH="22"

    cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
banaction = ufw
ignoreip = 127.0.0.1/8 ::1 ${WL_IPS}

[sshd]
enabled = true
port    = ${ACTIVE_SSH}
filter  = sshd
logpath = /var/log/auth.log
maxretry = ${CUR_RETRY}
findtime = ${CUR_FIND}
bantime = ${CUR_BAN}

[nginx-scanners]
enabled  = true
port     = anyport
filter   = nginx-scanners
logpath  = /opt/remnawave/nginx_logs/access.log
           /opt/remnawave/nginx_logs/stream_scanners.log
maxretry = ${CUR_RETRY}
findtime = ${CUR_FIND}
bantime  = ${CUR_BAN}
EOF

    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban > /dev/null 2>&1
    
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}[+] Конфигурация Fail2Ban успешно применена.${NC}"
    else
        echo -e "${RED}[!] Ошибка при запуске. Проверьте синтаксис значений.${NC}"
        [[ "$DEBUG" == "true" ]] && { echo -e "${CYAN}--- ЛОГ ОШИБОК FAIL2BAN ---${NC}"; journalctl -u fail2ban -n 20 --no-pager; }
    fi
}

set_f2b_val() {
    local FILE=$1; local NAME=$2; local EXAMPLE=$3
    clear; echo -e "${MAGENTA}=== ИЗМЕНЕНИЕ НАСТРОЙКИ: $NAME ===${NC}"
    echo -e "${GRAY}Текущее значение: $(cat "$FILE")${NC}"
    echo -e "${GRAY}Пример формата: $EXAMPLE${NC}\n"
    read -p "Введите новое значение: " newval
    if [[ -z "$newval" ]]; then return; fi
    echo "$newval" > "$FILE"
    install_fail2ban
    sleep 1
}

f2b_settings_menu() {
    while true; do
        clear
        local retry=$(cat "$F2B_RETRY_FILE")
        local find=$(cat "$F2B_FIND_FILE")
        local ban=$(cat "$F2B_BAN_FILE")
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  ⚙️  НАСТРОЙКИ АГРЕССИВНОСТИ ЗАЩИТЫ${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} Количество попыток (Maxretry)    ${CYAN}[$retry]${NC}"
        echo -e " ${YELLOW}2.${NC} Окно поиска атак (Findtime)      ${CYAN}[$find сек]${NC}"
        echo -e " ${YELLOW}3.${NC} Время блокировки (Bantime)       ${CYAN}[$ban]${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${GREEN}4.${NC} 📖 ${BOLD}СПРАВКА ДЛЯ ЧАЙНИКОВ (Как настроить?)${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " ch
        case $ch in
            1) set_f2b_val "$F2B_RETRY_FILE" "MAXRETRY" "3 (число попыток)" ;;
            2) set_f2b_val "$F2B_FIND_FILE" "FINDTIME" "600 (в секундах)" ;;
            3) set_f2b_val "$F2B_BAN_FILE" "BANTIME" "24h или 3600 (сек)" ;;
            4) show_f2b_help ;;
            0) return ;;
        esac
    done
}

show_f2b_help() {
    clear
    echo -e "${MAGENTA}=== СПРАВКА ПО НАСТРОЙКАМ FAIL2BAN ===${NC}\n"
    echo -e "${BOLD}1. Maxretry (Попытки)${NC}"
    echo -e "   Сколько раз хакер может ошибиться, прежде чем его забанят."
    echo -e "   ${CYAN}Для VPN:${NC} Ставьте ${GREEN}3-5${NC}. Меньше 3 нельзя — забаните себя при опечатке."
    
    echo -e "\n${BOLD}2. Findtime (Окно поиска)${NC}"
    echo -e "   Время (в секундах), в течение которого считаются ошибки."
    echo -e "   Если Findtime 600 (10 мин), а Maxretry 3 — хакера забанят, "
    echo -e "   только если он совершил 3 атаки именно за эти 10 минут."
    echo -e "   ${CYAN}Для VPN:${NC} Рекомендуется ${GREEN}600 (10 мин)${NC} или 3600 (1 час)."

    echo -e "\n${BOLD}3. Bantime (Время бана)${NC}"
    echo -e "   На сколько IP адрес попадает в черный список UFW."
    echo -e "   Можно писать в секундах (3600) или часах/днях (24h, 7d)."
    echo -e "   ${CYAN}Для VPN:${NC} Рекомендуется ${GREEN}24h${NC} или больше."
    pause
}

show_f2b_stats() {
    clear; echo -e "${MAGENTA}=== ПОДРОБНАЯ СТАТИСТИКА ЗАЩИТЫ FAIL2BAN ===${NC}\n"
    for jail in sshd nginx-scanners; do
        local raw_status=$(fail2ban-client status "$jail" 2>/dev/null || echo "")
        [[ -z "$raw_status" ]] && continue
        
        local cur_fail=$(echo "$raw_status" | grep "Currently failed:" | sed 's/[^0-9]*//g')
        local tot_fail=$(echo "$raw_status" | grep "Total failed:" | sed 's/[^0-9]*//g')
        local cur_ban=$(echo "$raw_status" | grep "Currently banned:" | sed 's/[^0-9]*//g')
        local tot_ban=$(echo "$raw_status" | grep "Total banned:" | sed 's/[^0-9]*//g')
        local banned_ips=$(echo "$raw_status" | grep "Banned IP list:" | awk -F':' '{print $2}' | xargs)
        [[ -z "$banned_ips" ]] && banned_ips="Чисто"
        
        if [[ "$jail" == "sshd" ]]; then
            echo -e "${CYAN}[ 🛡️  ЗАЩИТА SSH (Брутфорс паролей) ]${NC}"
        else
            echo -e "${CYAN}[ 🛡️  ЗАЩИТА NGINX (Reality + XHTTP + Сканеры) ]${NC}"
        fi

        echo -e "  ├─ ⚠️  Подозрительных прямо сейчас:   ${YELLOW}${cur_fail:-0}${NC}"
        echo -e "  ├─ 📈 Всего попыток атаки забанено:  ${YELLOW}${tot_fail:-0}${NC}"
        echo -e "  ├─ ⛔ Заблокировано IP в данный момент: ${RED}${cur_ban:-0}${NC}"
        echo -e "  ├─ 💀 Всего трупов за всё время:      ${RED}${tot_ban:-0}${NC}"
        echo -e "  └─ 🚫 Список забаненных:             ${RED}${banned_ips}${NC}\n"
    done
    pause
}

f2b_unban() {
    while true; do
        clear; echo -e "${MAGENTA}=== РАЗБАН И УПРАВЛЕНИЕ IP ===${NC}"
        local SSH_BANS=$(fail2ban-client get sshd banip 2>/dev/null)
        local NGINX_BANS=$(fail2ban-client get nginx-scanners banip 2>/dev/null)
        
        if [[ -z "$SSH_BANS" && -z "$NGINX_BANS" ]]; then
            echo -e "${GREEN}Заблокированных IP нет! Все чисто.${NC}"; pause; return
        fi

        echo -e "${CYAN}Список заблокированных IP:${NC}"
        declare -a BAN_IP_ARRAY; declare -a BAN_JAIL_ARRAY; local i=1
        for ip in $SSH_BANS; do echo -e "  ${YELLOW}[$i]${NC} $ip ${BLUE}[SSH]${NC}"; BAN_IP_ARRAY[$i]=$ip; BAN_JAIL_ARRAY[$i]="sshd"; ((i++)); done
        for ip in $NGINX_BANS; do echo -e "  ${YELLOW}[$i]${NC} $ip ${MAGENTA}[NGINX]${NC}"; BAN_IP_ARRAY[$i]=$ip; BAN_JAIL_ARRAY[$i]="nginx-scanners"; ((i++)); done

        echo -e "\nВыберите ${YELLOW}НОМЕР${NC} для разблокировки или ${YELLOW}0${NC} для выхода:"
        read -p ">> " ch
        [[ "$ch" == "0" || -z "$ch" ]] && return
        if [[ "$ch" =~ ^[0-9]+$ ]] && [ "$ch" -lt "$i" ] && [ "$ch" -gt 0 ]; then
            local TARGET_IP="${BAN_IP_ARRAY[$ch]}"
            local TARGET_JAIL="${BAN_JAIL_ARRAY[$ch]}"
            fail2ban-client set "$TARGET_JAIL" unbanip "$TARGET_IP" >/dev/null 2>&1
            echo -e "${GREEN}IP $TARGET_IP разблокирован!${NC}"; sleep 1
        fi
    done
}

f2b_whitelist() {
    while true; do
        clear; echo -e "${MAGENTA}=== БЕЛЫЙ СПИСОК (WHITELIST) ===${NC}"
        echo -e "${GRAY}IP из этого списка игнорируют лимиты UFW и баны Fail2Ban.${NC}\n"
        local i=1; declare -a WL_ARRAY
        while read -r line; do
            if [[ -n "$line" ]]; then
                local RAW_IP=$(echo "$line" | awk '{print $1}'); local COMMENT=$(echo "$line" | cut -d'#' -f2- | sed 's/^ //')
                echo -e "  ${YELLOW}[$i]${NC} ${CYAN}${RAW_IP}${NC} \t(Имя: ${COMMENT})"; WL_ARRAY[$i]="$line"; ((i++))
            fi
        done < "$WHITELIST_FILE"
        [ $i -eq 1 ] && echo "  (Список пуст)"
        
        echo -e "\n ${GREEN}1.${NC} Добавить IP | ${RED}2.${NC} Удалить IP | ${CYAN}0.${NC} Назад"
        read -p ">> " ch
        case $ch in
            1) read -p "Впишите IP: " ip; [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { read -p "Описание: " name; echo "$ip # $name" >> "$WHITELIST_FILE"; install_fail2ban >/dev/null 2>&1; ufw_global_setup >/dev/null 2>&1; echo -e "${GREEN}Добавлен в исключения!${NC}"; }; sleep 1 ;;
            2) read -p "Впишите НОМЕР: " num; [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -lt "$i" ] && [ "$num" -gt 0 ] && { grep -v -x -F "${WL_ARRAY[$num]}" "$WHITELIST_FILE" > /tmp/wl_tmp && mv /tmp/wl_tmp "$WHITELIST_FILE"; install_fail2ban >/dev/null 2>&1; ufw_global_setup >/dev/null 2>&1; echo -e "${GREEN}Удалено.${NC}"; }; sleep 1 ;;
            0) return ;;
        esac
    done
}

menu_fail2ban() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  👮 УПРАВЛЕНИЕ ЗАЩИТОЙ (FAIL2BAN) ${NC}$(get_f2b_status)"
        echo -e "${GRAY} Мощная защита от брутфорса и сканеров РКН.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 📊 Подробная статистика блокировок"
        echo -e " ${YELLOW}2.${NC} ✅ Разбан IP (Интерактивно)"
        echo -e " ${YELLOW}3.${NC} 🌟 Управление Белым Списком (Whitelist)"
        echo -e " ${YELLOW}4.${NC} ⚙️  Настройки агрессивности (Bantime/Retry)"
        echo -e " ${YELLOW}5.${NC} 🕵️  Смотреть логи Fail2Ban (Live)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) show_f2b_stats ;; 2) f2b_unban ;; 3) f2b_whitelist ;;
            4) f2b_settings_menu ;;
            5) clear; echo -e "${YELLOW}Нажмите Ctrl+C для выхода...${NC}"; tail -f /var/log/fail2ban.log ;;
            0) return ;;
        esac
    done
}
