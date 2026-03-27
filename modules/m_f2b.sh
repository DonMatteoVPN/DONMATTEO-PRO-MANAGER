#!/bin/bash

get_f2b_status() {
    if systemctl is-active --quiet fail2ban; then echo -e "${GREEN}[РАБОТАЕТ]${NC}"; else echo -e "${RED}[НЕ УСТАНОВЛЕНО/ВЫКЛЮЧЕН]${NC}"; fi
}

install_fail2ban() {
    echo -e "${CYAN}[*] Установка и настройка Fail2Ban...${NC}"
    apt-get update -qq && apt-get install fail2ban -y -qq
    
    # Убедимся, что файлы логов существуют, чтобы Fail2Ban не выдал ошибку при старте
    mkdir -p /var/log/nginx_custom
    touch /var/log/nginx_custom/access.log
    touch /var/log/nginx_custom/stream_scanners.log

    # Создаем пустой whitelist, если его еще нет
    touch "$WHITELIST_FILE"
    local WL_IPS=$(awk '{print $1}' "$WHITELIST_FILE" | grep -E '^[0-9]' | tr '\n' ' ')
    
    # СОЗДАЕМ ФИЛЬТР
    cat << 'EOF' > /etc/fail2ban/filter.d/nginx-scanners.conf
[Definition]
failregex = ^<HOST> \- \- \[.*\] "(GET|POST|HEAD|PROPFIND|OPTIONS|PUT|DELETE).*?" (400|401|403|404|405|444)
            ^<HOST>\s*\[[^\]]+\]\s*SNI:".*?"\s*RoutedTo:"unix:/dev/shm/nginx_external\.sock"
ignoreregex =
EOF

    local ACTIVE_SSH=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | paste -sd "," -)
    [[ -z "$ACTIVE_SSH" ]] && ACTIVE_SSH="22"

    # НАСТРАИВАЕМ JAIL: Обратите внимание на отступ (пробелы) перед вторым файлом логов!
    cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
banaction = ufw
ignoreip = 127.0.0.1/8 ::1 ${WL_IPS}

[sshd]
enabled = true
port    = ${ACTIVE_SSH}
filter  = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = ${BANTIME}

[nginx-scanners]
enabled  = true
port     = anyport
filter   = nginx-scanners
logpath  = /var/log/nginx_custom/access.log
           /var/log/nginx_custom/stream_scanners.log
maxretry = 3
findtime = 600
bantime  = ${BANTIME}
EOF

    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban > /dev/null 2>&1
    
    # Проверка, успешно ли запустился Fail2Ban
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}[+] Fail2Ban активирован и работает без ошибок!${NC}"
    else
        echo -e "${RED}[!] Ошибка запуска Fail2Ban. Проверьте логи: systemctl status fail2ban${NC}"
    fi
}

show_f2b_stats() {
    clear; echo -e "${MAGENTA}=== СТАТИСТИКА БЛОКИРОВОК FAIL2BAN ===${NC}\n"
    for jail in sshd nginx-scanners; do
        local raw_status=$(fail2ban-client status "$jail" 2>/dev/null || echo "")
        [[ -z "$raw_status" ]] && continue
        
        local cur_fail=$(echo "$raw_status" | grep "Currently failed:" | sed 's/[^0-9]*//g')
        local tot_fail=$(echo "$raw_status" | grep "Total failed:" | sed 's/[^0-9]*//g')
        local cur_ban=$(echo "$raw_status" | grep "Currently banned:" | sed 's/[^0-9]*//g')
        local tot_ban=$(echo "$raw_status" | grep "Total banned:" | sed 's/[^0-9]*//g')
        local banned_ips=$(echo "$raw_status" | grep "Banned IP list:" | awk -F':' '{print $2}' | xargs)
        [[ -z "$banned_ips" ]] && banned_ips="Никого нет в бане"
        
        [[ "$jail" == "sshd" ]] && echo -e "${CYAN}[ 🛡️  Защита SSH (Брутфорс паролей) ]${NC}" || echo -e "${CYAN}[ 🛡️  Защита NGINX (Сканеры уязвимостей) ]${NC}"
        echo -e "  └─ ⚠️  Ошибок прямо сейчас:         ${YELLOW}${cur_fail:-0}${NC}"
        echo -e "  └─ 📈 Всего попыток взлома:        ${YELLOW}${tot_fail:-0}${NC}"
        echo -e "  └─ ⛔ Сейчас в бане (IP):          ${RED}${cur_ban:-0}${NC}"
        echo -e "  └─ 💀 Всего забанено за всё время: ${RED}${tot_ban:-0}${NC}"
        echo -e "  └─ 🚫 Список заблокированных IP:   ${RED}${banned_ips}${NC}\n"
    done
    pause
}

f2b_unban() {
    while true; do
        clear; echo -e "${MAGENTA}=== РАЗБАН И УПРАВЛЕНИЕ IP ===${NC}"
        local SSH_BANS=$(fail2ban-client get sshd banip 2>/dev/null); local NGINX_BANS=$(fail2ban-client get nginx-scanners banip 2>/dev/null)
        local UNIQUE_BANS=$(echo "$SSH_BANS $NGINX_BANS" | tr ' ' '\n' | sort -u | grep -v '^$')
        [[ -z "$UNIQUE_BANS" ]] && { echo -e "${GREEN}Заблокированных IP нет! Все чисто.${NC}"; pause; return; }

        echo -e "${CYAN}Список заблокированных IP:${NC}"; declare -a BAN_ARRAY; local i=1
        for ip in $UNIQUE_BANS; do echo -e "  ${YELLOW}[$i]${NC} $ip"; BAN_ARRAY[$i]=$ip; ((i++)); done

        read -p $'\nНОМЕР или IP (0 - Назад): ' ch; [[ "$ch" == "0" || -z "$ch" ]] && return
        if [[ "$ch" =~ ^[0-9]+$ ]] &&[ "$ch" -lt "$i" ] && [ "$ch" -gt 0 ]; then local TARGET_IP="${BAN_ARRAY[$ch]}"; else local TARGET_IP="$ch"; fi

        fail2ban-client set sshd unbanip "$TARGET_IP" >/dev/null 2>&1; fail2ban-client set nginx-scanners unbanip "$TARGET_IP" >/dev/null 2>&1
        echo -e "${GREEN}IP $TARGET_IP успешно разблокирован!${NC}"; sleep 1
    done
}

f2b_whitelist() {
    while true; do
        clear; echo -e "${MAGENTA}=== БЕЛЫЙ СПИСОК (WHITELIST) ===${NC}"
        echo -e "${GRAY}IP-адреса, которые игнорируются при блокировках.${NC}\n"
        local i=1; declare -a WL_ARRAY
        while read -r line; do
            if [[ -n "$line" ]]; then
                local RAW_IP=$(echo "$line" | awk '{print $1}'); local COMMENT=$(echo "$line" | cut -d'#' -f2- | sed 's/^ //'); [[ "$RAW_IP" == "$COMMENT" ]] && COMMENT="Без описания"
                echo -e "  ${YELLOW}[$i]${NC} ${CYAN}${RAW_IP}${NC} \t(Имя: ${COMMENT})"; WL_ARRAY[$i]="$line"; ((i++))
            fi
        done < "$WHITELIST_FILE"
        [ $i -eq 1 ] && echo "  (Список пуст)"
        
        echo -e "\n ${GREEN}1.${NC} Добавить IP | ${RED}2.${NC} Удалить IP | ${CYAN}0.${NC} Назад"
        read -p ">> " ch
        case $ch in
            1) read -p "Впишите IP: " ip; [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { awk '{print $1}' "$WHITELIST_FILE" | grep -q "^$ip$" && echo -e "${YELLOW}Уже в списке!${NC}" || { read -p "Краткое описание: " name; [[ -z "$name" ]] && name="Вручную"; echo "$ip # $name" >> "$WHITELIST_FILE"; ufw allow from $ip comment "Whitelist" >/dev/null 2>&1; install_fail2ban >/dev/null 2>&1; ufw_global_setup >/dev/null 2>&1; echo -e "${GREEN}Успешно добавлен!${NC}"; }; } || echo "Ошибка IP"; sleep 1 ;;
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
        echo -e "${GRAY} Блокирует хакеров, подбирающих пароли и уязвимости.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 📊 Подробная статистика блокировок"
        echo -e "    ${GRAY}└─ Показывает, сколько ботов сейчас в бане.${NC}"
        echo -e " ${YELLOW}2.${NC} ✅ Разбан IP (Интерактивно)"
        echo -e "    ${GRAY}└─ Позволяет вытащить IP-адрес из черного списка.${NC}"
        echo -e " ${YELLOW}3.${NC} 🌟 Управление Белым Списком (Whitelist)"
        echo -e "    ${GRAY}└─ Добавление своих IP, чтобы их никогда не банили.${NC}"
        echo -e " ${YELLOW}4.${NC} 🕵️  Смотреть логи Fail2Ban (Live)"
        echo -e "    ${GRAY}└─ Журнал работы снайпера (кого банит прямо сейчас).${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) show_f2b_stats ;; 2) f2b_unban ;; 3) f2b_whitelist ;;
            4) clear; echo -e "${YELLOW}Нажмите Ctrl+C для выхода...${NC}"; tail -f /var/log/fail2ban.log ;;
            0) return ;;
        esac
    done
}
