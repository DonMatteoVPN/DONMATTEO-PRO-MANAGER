#!/bin/bash

get_f2b_status() {
    if systemctl is-active --quiet fail2ban; then echo -e "${GREEN}[РАБОТАЕТ]${NC}"; else echo -e "${RED}[НЕ УСТАНОВЛЕНО/ВЫКЛЮЧЕН]${NC}"; fi
}

install_fail2ban() {
    echo -e "${CYAN}[*] Установка и настройка Fail2Ban...${NC}"
    apt-get update -qq && apt-get install fail2ban -y -qq
    local WL_IPS=$(awk '{print $1}' "$WHITELIST_FILE" | grep -E '^[0-9]' | tr '\n' ' ')
    
    cat << 'EOF' > /etc/fail2ban/filter.d/nginx-scanners.conf
[Definition]
failregex = ^<HOST> \- \- \[.*\] "(GET|POST|HEAD|PROPFIND|OPTIONS|PUT|DELETE).*?" (400|401|403|404|405|444) 
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
backend = systemd
maxretry = 3
bantime = ${BANTIME}

[nginx-scanners]
enabled  = true
port     = anyport
filter   = nginx-scanners
logpath  = /opt/remnawave/nginx_logs/access.log
maxretry = 3
findtime = 600
bantime  = ${BANTIME}
EOF

    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban > /dev/null 2>&1
    echo -e "${GREEN}[+] Fail2Ban активирован.${NC}"
}

show_f2b_stats() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}          🛡️  СУММАРНАЯ СТАТИСТИКА ЗАЩИТЫ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"

    # --- БЛОК 1: FAIL2BAN (SSH) ---
    local ssh_ban=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $4}' || echo "0")
    local ssh_total=$(fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $4}' || echo "0")
    local ssh_list=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | cut -d: -f2 | sed 's/^[ \t]*//')

    echo -e "${YELLOW}[ 🛡️  Защита SSH (Fail2Ban) ]${NC}"
    echo -e "  └─ ⛔ Сейчас в бане (IP):      ${RED}${ssh_ban}${NC}"
    echo -e "  └─ 💀 Всего банов (за сессию): ${ssh_total}"
    echo -e "  └─ 🚫 Список IP: ${GRAY}${ssh_list:-Никого нет}${NC}\n"

    # --- БЛОК 2: FAIL2BAN (NGINX) ---
    local ngx_ban=$(fail2ban-client status nginx-scanners 2>/dev/null | grep "Currently banned" | awk '{print $4}' || echo "0")
    local ngx_total=$(fail2ban-client status nginx-scanners 2>/dev/null | grep "Total banned" | awk '{print $4}' || echo "0")
    local ngx_list=$(fail2ban-client status nginx-scanners 2>/dev/null | grep "Banned IP list" | cut -d: -f2 | sed 's/^[ \t]*//')

    echo -e "${CYAN}[ 🛡️  Защита NGINX (Fail2Ban) ]${NC}"
    echo -e "  └─ ⛔ Сейчас в бане (IP):      ${RED}${ngx_ban}${NC}"
    echo -e "  └─ 💀 Всего банов (за сессию): ${ngx_total}"
    echo -e "  └─ 🚫 Список IP: ${GRAY}${ngx_list:-Никого нет}${NC}\n"

    # --- БЛОК 3: TRAFFICGUARD (ЯДРО) ---
    local tg_subnets=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}' || echo "0")
    local tg_hits=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | grep "DROP" | awk '{print $1}' | awk '{s+=$1} END {print s}' || echo "0")
    local tg_manual=$(wc -l < "/opt/trafficguard-manual.list" 2>/dev/null || echo "0")

    echo -e "${MAGENTA}[ 🛡️  TrafficGuard PRO (Kernel Level) ]${NC}"
    echo -e "  └─ 📊 Заблокировано подсетей:  ${GREEN}${tg_subnets}${NC}"
    echo -e "  └─ 🔥 Всего отбито атак:       ${RED}${tg_hits:-0} пакетов${NC}"
    echo -e "  └─ 🧪 Ручных блокировок:       ${YELLOW}${tg_manual}${NC}"
    
    echo -e "${MAGENTA}======================================================${NC}"
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
        if [[ "$ch" =~ ^[0-9]+$ ]] && [ "$ch" -lt "$i" ] && [ "$ch" -gt 0 ]; then local TARGET_IP="${BAN_ARRAY[$ch]}"; else local TARGET_IP="$ch"; fi

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
