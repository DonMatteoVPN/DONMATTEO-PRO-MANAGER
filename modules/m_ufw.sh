#!/bin/bash

get_sysctl_status() {
    if [[ "$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)" == "1" ]]; then echo -e "${GREEN}[ВКЛЮЧЕНО]${NC}"; else echo -e "${RED}[НЕ УСТАНОВЛЕНО]${NC}"; fi
}

get_ufw_status() {
    if ufw status | grep -qw active; then echo -e "${GREEN}[РАБОТАЕТ]${NC}"; else echo -e "${RED}[ВЫКЛЮЧЕН]${NC}"; fi
}

ufw_global_setup() {
    echo -e "${CYAN}[*] Сборка и инициализация структуры UFW...${NC}"
    apt-get install ufw -y -qq
    cp /etc/ufw/before.rules /etc/ufw/before.rules.bak
    sed -i '/# --- НАЧАЛО: Правила защиты от DDoS (DonMatteo) ---/,/# --- КОНЕЦ: Направляем трафик на проверку скорости ---/d' /etc/ufw/before.rules
    
    local WL_BEFORE=""
    for ip in $(awk '{print $1}' "$WHITELIST_FILE" | grep -E '^[0-9]'); do WL_BEFORE+="-A ufw-before-input -s $ip -j ACCEPT\\n"; done
    
    local CONNLIMIT_RULES=""
    for port in $(cat "$CONNLIMIT_FILE" | grep -E '^[0-9]+$'); do CONNLIMIT_RULES+="-A ufw-before-input -p tcp --dport $port -m connlimit --connlimit-above 150 --connlimit-mask 32 -j DROP\\n"; done
    
    local RATELIMIT_RULES=""
    local ACTIVE_SSH=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    [[ -z "$ACTIVE_SSH" ]] && ACTIVE_SSH="22"
    RATELIMIT_RULES+="-A ufw-before-input -p tcp --dport $ACTIVE_SSH -m conntrack --ctstate NEW -j IN_LIMIT\\n"
    
    for port in $(cat "$RATELIMIT_FILE" | grep -E '^[0-9]+$'); do
        if [[ "$port" != "$ACTIVE_SSH" ]]; then RATELIMIT_RULES+="-A ufw-before-input -p tcp --dport $port -m conntrack --ctstate NEW -j IN_LIMIT\\n"; fi
    done

    sed -i '/^\*filter/a \
# --- НАЧАЛО: Правила защиты от DDoS (DonMatteo) ---\n\
:IN_LIMIT - [0:0]\n\
-A IN_LIMIT -m limit --limit 80/s --limit-burst 250 -j RETURN\n\
-A IN_LIMIT -j DROP\n\
# --- КОНЕЦ: Правила защиты от DDoS ---\n\
\n\
:ufw-before-input - [0:0]\n\
\n\
# --- НАЧАЛО: Белый список (Пропуск лимитов) ---\n\
'"$WL_BEFORE"'# --- КОНЕЦ: Белый список ---\n\
\n\
# --- НАЧАЛО: Защита от сканеров и кривых пакетов ---\n\
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP\n\
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP\n\
# --- КОНЕЦ: Защита от сканеров ---\n\
\n\
# --- НАЧАЛО: Лимит одновременных соединений ---\n\
'"$CONNLIMIT_RULES"'# --- КОНЕЦ: Лимит одновременных соединений ---\n\
\n\
# --- НАЧАЛО: Направляем трафик на проверку скорости ---\n\
'"$RATELIMIT_RULES"'# --- КОНЕЦ: Направляем трафик на проверку скорости ---' /etc/ufw/before.rules

    echo "y" | ufw enable > /dev/null 2>&1
    ufw reload > /dev/null 2>&1
    echo -e "${GREEN}[+] Ядро UFW и динамические лимиты настроены.${NC}"
}

manage_limit_ports() {
    local FILE=$1; local TITLE=$2; local DESC=$3
    while true; do
        clear
        echo -e "${MAGENTA}=== $TITLE ===${NC}\n${GRAY}$DESC${NC}\n"
        local i=1; declare -a ARR
        while read -r line; do
            if [[ -n "$line" ]]; then echo -e "  ${YELLOW}[$i]${NC} Порт: ${CYAN}$line${NC}"; ARR[$i]="$line"; ((i++)); fi
        done < "$FILE"
        [ $i -eq 1 ] && echo "  (Список пуст)"
        
        echo -e "\n ${GREEN}1.${NC} ➕ Добавить порт | ${RED}2.${NC} ➖ Удалить порт | ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " lch
        case $lch in
            1) read -p "Впишите порт: " new_port; [[ "$new_port" =~ ^[0-9]+$ ]] && { grep -q "^$new_port$" "$FILE" && echo -e "${YELLOW}Уже есть!${NC}" || { echo "$new_port" >> "$FILE"; ufw_global_setup >/dev/null 2>&1; echo -e "${GREEN}Успешно добавлен!${NC}"; }; }; sleep 1 ;;
            2) read -p "Введите НОМЕР: " del_num; if [[ "$del_num" =~ ^[0-9]+$ ]] && [ "$del_num" -lt "$i" ] && [ "$del_num" -gt 0 ]; then sed -i "/^${ARR[$del_num]}$/d" "$FILE"; ufw_global_setup >/dev/null 2>&1; echo -e "${GREEN}Удалено.${NC}"; sleep 1; fi ;;
            0) return ;;
        esac
    done
}

ufw_limits_menu() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  ⚙️ УПРАВЛЕНИЕ ЛИМИТАМИ (ANTI-DDOS)${NC}"
        echo -e "${GRAY} Защита от исчерпания ресурсов сервера на уровне ядра.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 🛡️  Жесткий лимит соединений (CONNLIMIT)"
        echo -e "    ${GRAY}└─ Сбрасывает IP, если он открыл > 150 потоков.${NC}"
        echo -e " ${YELLOW}2.${NC} 🚦 Плавный лимит скорости (RATELIMIT)"
        echo -e "    ${GRAY}└─ Режет скорость, если идет > 80 запросов в секунду.${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " ch
        case $ch in
            1) manage_limit_ports "$CONNLIMIT_FILE" "ПОРТЫ ДЛЯ CONNLIMIT (Жесткий блок)" "Сбрасывает злоумышленника, если он открыл больше 150 соединений." ;;
            2) manage_limit_ports "$RATELIMIT_FILE" "ПОРТЫ ДЛЯ RATELIMIT (Скорость сессий)" "Ограничивает глобальный шторм новых подключений." ;;
            0) return ;;
        esac
    done
}

ufw_add_port() {
    clear; echo -e "${MAGENTA}=== ОТКРЫТИЕ ПОРТА ===${NC}"; read -p "Впишите порт: " port; [[ -z "$port" ]] && return
    read -p "Укажите протокол (tcp/udp/any) [any]: " proto; [[ -z "$proto" || "$proto" == "any" ]] && proto_str="" || proto_str="/$proto"
    read -p "Добавьте комментарий: " comment; [[ -z "$comment" ]] && comment="Manual_Rule"
    ufw allow ${port}${proto_str} comment "${comment}"; echo -e "${GREEN}Правило успешно добавлено!${NC}"; pause
}

ufw_add_ip() {
    clear; echo -e "${MAGENTA}=== ДОСТУП ДЛЯ IP ===${NC}"; read -p "Впишите IP адрес: " ip; [[ -z "$ip" ]] && return
    read -p "Впишите порт (или 'any' для всех) [any]: " port; [[ -z "$port" ]] && port="any"
    read -p "Укажите протокол (tcp/udp/any) [any]: " proto; [[ -z "$proto" || "$proto" == "any" ]] && proto_str="" || proto_str="proto $proto"
    read -p "Добавьте комментарий: " comment; [[ -z "$comment" ]] && comment="IP_Access"
    if [[ "$port" == "any" ]]; then ufw allow from $ip comment "$comment"; else ufw allow from $ip to any port $port $proto_str comment "$comment"; fi
    echo -e "${GREEN}Доступ разрешен!${NC}"; pause
}

ufw_show_delete() {
    while true; do
        clear; echo -e "${MAGENTA}=== УДАЛЕНИЕ ПРАВИЛ FIREWALL ===${NC}"
        ufw status numbered | sed -e 's/Status: active/Статус: Активен/' -e 's/Status: inactive/Статус: Выключен/' -e 's/To/Куда/' -e 's/Action/Действие/' -e 's/From/Откуда/'
        echo -e "\nВведите ${YELLOW}НОМЕР${NC} для удаления, или ${YELLOW}0${NC} для выхода:"
        read -p ">> " num
        [[ "$num" == "0" || -z "$num" ]] && return
        [[ "$num" =~ ^[0-9]+$ ]] && { echo "y" | ufw delete $num; echo -e "${GREEN}Правило удалено.${NC}"; sleep 1; } || { echo -e "${RED}Ошибка ввода.${NC}"; sleep 1; }
    done
}

menu_ufw() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🌐 УПРАВЛЕНИЕ FIREWALL (UFW) ${NC}$(get_ufw_status)"
        echo -e "${GRAY} Сетевой экран. Определяет, кто может подключиться.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 🔓 Открыть порт (Для всех)"
        echo -e "    ${GRAY}└─ Разрешает входящий трафик из интернета на порт.${NC}"
        echo -e " ${YELLOW}2.${NC} 🎯 Открыть порт (Для конкретного IP)"
        echo -e "    ${GRAY}└─ Доступ к порту будет только у доверенного IP.${NC}"
        echo -e " ${YELLOW}3.${NC} 📋 Просмотр активных правил и Удаление"
        echo -e "    ${GRAY}└─ Показывает нумерованный список для управления.${NC}"
        echo -e " ${YELLOW}4.${NC} ⚙️  Управление портами защиты (DDoS Лимиты)"
        echo -e "    ${GRAY}└─ Настройка встроенного Anti-DDoS от флуда.${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) ufw_add_port ;; 2) ufw_add_ip ;; 3) ufw_show_delete ;; 4) ufw_limits_menu ;; 0) return ;;
        esac
    done
}