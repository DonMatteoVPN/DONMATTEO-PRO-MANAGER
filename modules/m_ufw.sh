#!/bin/bash

# Пути к файлам настроек (значения лимитов)
export CONN_VAL_FILE="/opt/remnawave/limit_conn_val.txt"
export RATE_VAL_FILE="/opt/remnawave/limit_rate_val.txt"

# Инициализация дефолтных значений, если файлы пусты
[[ ! -f "$CONN_VAL_FILE" ]] && echo "150" > "$CONN_VAL_FILE"
[[ ! -f "$RATE_VAL_FILE" ]] && echo "80" > "$RATE_VAL_FILE"

get_sysctl_status() {
    if [[ "$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)" == "1" ]]; then echo -e "${GREEN}[ВКЛЮЧЕНО]${NC}"; else echo -e "${RED}[НЕ УСТАНОВЛЕНО]${NC}"; fi
}

get_ufw_status() {
    if ufw status | grep -qw active; then echo -e "${GREEN}[РАБОТАЕТ]${NC}"; else echo -e "${RED}[ВЫКЛЮЧЕН]${NC}"; fi
}

# Функция получения статуса логирования
get_ufw_log_status() {
    if ufw status verbose | grep -q "logging: on"; then
        echo -e "${GREEN}[ВКЛЮЧЕНЫ]${NC}"
    else
        echo -e "${RED}[ВЫКЛЮЧЕНЫ]${NC}"
    fi
}

# --- ВНУТРЕННЯЯ ФУНКЦИЯ: ПРОВЕРКА И УСТАНОВКА RSYSLOG ---
ensure_rsyslog() {
    if ! command -v rsyslogd &> /dev/null; then
        echo -e "${CYAN}[*] Служба rsyslog не найдена. Установка для работы логов...${NC}"
        apt-get update -qq && apt-get install rsyslog -y -qq
        systemctl enable --now rsyslog >/dev/null 2>&1
        # Даем немного времени на инициализацию файла лога
        sleep 2
    fi

    if ! systemctl is-active --quiet rsyslog; then
        echo -e "${YELLOW}[*] Запуск службы rsyslog...${NC}"
        systemctl start rsyslog
    fi

    # Проверяем, существует ли файл лога, если нет - создаем пустой
    if [ ! -f /var/log/ufw.log ]; then
        touch /var/log/ufw.log
        chmod 640 /var/log/ufw.log
        chown syslog:adm /var/log/ufw.log
    fi
}



# --- ГЛАВНАЯ ФУНКЦИЯ СБОРКИ ПРАВИЛ ---
ufw_global_setup() {
    echo -e "${CYAN}[*] Пересборка правил Anti-DDoS и перезапуск UFW...${NC}"
    apt-get install ufw -y -qq
    
    local CONN_LIMIT=$(cat "$CONN_VAL_FILE")
    local RATE_LIMIT=$(cat "$RATE_VAL_FILE")
    
    cp /etc/ufw/before.rules /etc/ufw/before.rules.bak
    
    # Очистка старых блоков правил DonMatteo
    sed -i '/# --- НАЧАЛО: Правила защиты от DDoS (DonMatteo) ---/,/# --- КОНЕЦ: Направляем трафик на проверку скорости ---/d' /etc/ufw/before.rules
    
    # Сборка Белого Списка
    local WL_BEFORE=""
    [[ -f "$WHITELIST_FILE" ]] && for ip in $(awk '{print $1}' "$WHITELIST_FILE" | grep -E '^[0-9]'); do WL_BEFORE+="-A ufw-before-input -s $ip -j ACCEPT\\n"; done
    
    # Сборка CONNLIMIT (Жесткие лимиты)
    local CONNLIMIT_RULES=""
    [[ -f "$CONNLIMIT_FILE" ]] && for port in $(cat "$CONNLIMIT_FILE" | grep -E '^[0-9]+$'); do 
        CONNLIMIT_RULES+="-A ufw-before-input -p tcp --dport $port -m connlimit --connlimit-above $CONN_LIMIT --connlimit-mask 32 -j DROP\\n"
    done
    
    # Сборка RATELIMIT (Плавные лимиты)
    local RATELIMIT_RULES=""
    local ACTIVE_SSH=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    [[ -z "$ACTIVE_SSH" ]] && ACTIVE_SSH="22"
    
    # SSH всегда под лимитом скорости
    RATELIMIT_RULES+="-A ufw-before-input -p tcp --dport $ACTIVE_SSH -m conntrack --ctstate NEW -j IN_LIMIT\\n"
    
    [[ -f "$RATELIMIT_FILE" ]] && for port in $(cat "$RATELIMIT_FILE" | grep -E '^[0-9]+$'); do
        if [[ "$port" != "$ACTIVE_SSH" ]]; then 
            RATELIMIT_RULES+="-A ufw-before-input -p tcp --dport $port -m conntrack --ctstate NEW -j IN_LIMIT\\n"
        fi
    done

    # Инъекция правил в начало файла before.rules
    sed -i '/^\*filter/a \
# --- НАЧАЛО: Правила защиты от DDoS (DonMatteo) ---\n\
:IN_LIMIT - [0:0]\n\
-A IN_LIMIT -m limit --limit '"$RATE_LIMIT"'/s --limit-burst 250 -j RETURN\n\
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
    echo -e "${GREEN}[+] Правила успешно применены. Лимиты: Conn=$CONN_LIMIT, Rate=$RATE_LIMIT/s${NC}"
}

# Функция изменения числового значения лимита
set_limit_val() {
    local FILE=$1; local NAME=$2
    clear; echo -e "${MAGENTA}=== ИЗМЕНЕНИЕ ЗНАЧЕНИЯ: $NAME ===${NC}"
    echo -e "${GRAY}Текущее значение: $(cat "$FILE")${NC}"
    read -p "Введите новое число: " newval
    if [[ "$newval" =~ ^[0-9]+$ ]] && [ "$newval" -gt 0 ]; then
        echo "$newval" > "$FILE"
        ufw_global_setup
    else
        echo -e "${RED}Ошибка: Введите целое число!${NC}"; sleep 1
    fi
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
            1) read -p "Впишите порт: " new_port; [[ "$new_port" =~ ^[0-9]+$ ]] && { grep -q "^$new_port$" "$FILE" && echo -e "${YELLOW}Уже есть!${NC}" || { echo "$new_port" >> "$FILE"; ufw_global_setup; }; }; sleep 1 ;;
            2) read -p "Введите НОМЕР: " del_num; if [[ "$del_num" =~ ^[0-9]+$ ]] && [ "$del_num" -lt "$i" ] && [ "$del_num" -gt 0 ]; then sed -i "/^${ARR[$del_num]}$/d" "$FILE"; ufw_global_setup; echo -e "${GREEN}Удалено.${NC}"; sleep 1; fi ;;
            0) return ;;
        esac
    done
}

ufw_limits_menu() {
    while true; do
        local cur_conn=$(cat "$CONN_VAL_FILE")
        local cur_rate=$(cat "$RATE_VAL_FILE")
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  ⚙️ УПРАВЛЕНИЕ ЛИМИТАМИ (ANTI-DDOS)${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 🛡️  Порты CONNLIMIT (Жесткий блок) ${GRAY}[Значение: $cur_conn]${NC}"
        echo -e " ${YELLOW}2.${NC} 🚦 Порты RATELIMIT (Плавный блок)  ${GRAY}[Значение: $cur_rate/s]${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${GREEN}3.${NC} ✍️  Изменить лимит потоков (сейчас $cur_conn)"
        echo -e " ${GREEN}4.${NC} ✍️  Изменить лимит скорости (сейчас $cur_rate)"
        echo -e " ${CYAN}5.${NC} 📖 ${BOLD}СПРАВКА: КАКИЕ ЗНАЧЕНИЯ СТАВИТЬ ДЛЯ VPN?${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " ch
        case $ch in
            1) manage_limit_ports "$CONNLIMIT_FILE" "CONNLIMIT ПОРТЫ" "Блокирует IP, если он превысил порог соединений." ;;
            2) manage_limit_ports "$RATELIMIT_FILE" "RATELIMIT ПОРТЫ" "Ограничивает число новых попыток подключения в секунду." ;;
            3) set_limit_val "$CONN_VAL_FILE" "CONNLIMIT" ;;
            4) set_limit_val "$RATE_VAL_FILE" "RATELIMIT" ;;
            5) show_vpn_limits_help ;;
            0) return ;;
        esac
    done
}

# --- МЕНЮ ЛОГОВ ---
ufw_logs_menu() {
    # ПРОВЕРКА ЗАВИСИМОСТЕЙ ПРИ ВХОДЕ
    ensure_rsyslog

    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  📊 ЛОГИ И АНАЛИТИКА FIREWALL ${NC}$(get_ufw_log_status)"
        echo -e "${GRAY} Позволяет видеть, кто и какие порты атакует прямо сейчас.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 🟢 Включить логирование (Обычное)"
        echo -e " ${YELLOW}2.${NC} 🟠 Включить логирование (Детальное - HIGH)"
        echo -e " ${YELLOW}3.${NC} 🔴 Выключить логирование"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${GREEN}4.${NC} 🕵️  Смотреть блокировки LIVE (В реальном времени)"
        echo -e " ${GREEN}5.${NC} 🏆 ТОП-10 атакующих IP (Статистика из логов)"
        echo -e " ${GREEN}6.${NC} 🎯 ТОП атакуемых портов"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " ch
        case $ch in
            1) ufw logging on; echo -e "${GREEN}Логи включены (low)${NC}"; sleep 1 ;;
            2) ufw logging high; echo -e "${ORANGE}Логи включены (high)${NC}"; sleep 1 ;;
            3) ufw logging off; echo -e "${RED}Логи выключены${NC}"; sleep 1 ;;
            4) view_ufw_logs_live ;;
            5) show_top_attackers ;;
            6) show_top_ports ;;
            0) return ;;
        esac
    done
}

# --- ФУНКЦИИ АНАЛИЗА ---

view_ufw_logs_live() {
    clear
    echo -e "${YELLOW}Мониторинг блокировок (Нажмите Ctrl+C для выхода)...${NC}"
    echo -e "${GRAY}Вы будете видеть только события [BLOCK] и [LIMIT]${NC}\n"
    
    # Проверка наполнения лога
    if [ ! -s /var/log/ufw.log ]; then
        echo -e "${YELLOW}Лог-файл пока пуст. Попробуйте обновить страницу позже,${NC}"
        echo -e "${YELLOW}когда появятся первые заблокированные запросы.${NC}"
        pause; return
    fi

    tail -f /var/log/ufw.log | grep --line-buffered -E "\[UFW (BLOCK|LIMIT)\]" | awk '{
        match($0, /SRC=([0-9.]+)/, src);
        match($0, /DPT=([0-9]+)/, dpt);
        match($0, /PROTO=([A-Z]+)/, proto);
        # Если DPT не найден (например в ICMP), ставим прочерк
        port = (dpt[1] ? dpt[1] : "---");
        print "\033[1;31m[DROP]\033[0m IP: \033[1;33m" src[1] "\033[0m -> Port: \033[1;36m" port "\033[0m (" proto[1] ")"
    }'
}

show_top_attackers() {
    clear
    echo -e "${MAGENTA}=== ТОП-10 IP ПОД БЛОКИРОВКОЙ ===${NC}"
    echo -e "${GRAY}На основе текущего файла /var/log/ufw.log${NC}\n"
    
    if [ ! -s /var/log/ufw.log ]; then echo -e "${RED}Файл логов пуст.${NC}"; pause; return; fi
    
    grep "UFW BLOCK" /var/log/ufw.log | awk -F'SRC=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 10 | awk '{print "  [" $1 " атак] - " $2}'
    pause
}

show_top_ports() {
    clear
    echo -e "${MAGENTA}=== САМЫЕ АТАКУЕМЫЕ ПОРТЫ ===${NC}\n"
    if [ ! -s /var/log/ufw.log ]; then echo -e "${RED}Файл логов пуст.${NC}"; pause; return; fi
    
    grep "UFW BLOCK" /var/log/ufw.log | awk -F'DPT=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 5 | awk '{print "  Порт " $2 " - заблокировано " $1 " запросов"}'
    pause
}

show_vpn_limits_help() {
    clear
    echo -e "${MAGENTA}=== СПРАВКА ПО ЛИМИТАМ ДЛЯ VPN ===${NC}\n"
    echo -e "${BOLD}1. CONNLIMIT (Макс. соединений с одного IP)${NC}"
    echo -e "   ${CYAN}Как работает:${NC} Считает, сколько 'ниток' тянет клиент. "
    echo -e "   ${CYAN}Для VPN:${NC} Если используете Xray gRPC или Reality с мультиплексированием (Mux),"
    echo -e "   клиент занимает ВСЕГО 1-5 соединений. Если Mux выключен - до 50."
    echo -e "   ${GREEN}Рекомендуемое значение:${NC} 150-200 (золотая середина)."
    echo -e "   ${YELLOW}Зачем повышать?${NC} Если за одним роутером (NAT) сидит весь офис."
    echo -e "\n${BOLD}2. RATELIMIT (Скорость новых запросов)${NC}"
    echo -e "   ${CYAN}Как работает:${NC} Сколько РАЗ в секунду клиент может постучаться на порт."
    echo -e "   ${CYAN}Для VPN:${NC} Обычный клиент стучится 1-2 раза при подключении."
    echo -e "   Боты-сканеры (Shodan) стучатся 500+ раз в секунду."
    echo -e "   ${GREEN}Рекомендуемое значение:${NC} 50-100 в секунду."
    echo -e "\n${BOLD}Как определить идеальное значение?${NC}"
    echo -e "   Включите логи UFW (${YELLOW}ufw logging on${NC}). Если в логах много 'DROP' "
    echo -e "   от реальных пользователей - повышайте значения на 50 пунктов."
    pause
}

# --- ОСТАЛЬНЫЕ ФУНКЦИИ (ПОРТЫ И IP) ---
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

# --- ОБНОВЛЕННОЕ ГЛАВНОЕ МЕНЮ МОДУЛЯ ---

menu_ufw() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🌐 УПРАВЛЕНИЕ FIREWALL (UFW) ${NC}$(get_ufw_status)"
        echo -e "${GRAY} Сетевой экран. Определяет, кто может подключиться.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 🔓 Открыть порт (Для всех)"
        echo -e " ${YELLOW}2.${NC} 🎯 Открыть порт (Для конкретного IP)"
        echo -e " ${YELLOW}3.${NC} 📋 Просмотр активных правил и Удаление"
        echo -e " ${YELLOW}4.${NC} ⚙️  Управление лимитами (Anti-DDoS)"
        echo -e " ${YELLOW}5.${NC} 📊 Логи и Аналитика (Кто атакует?) \e[40G${NC}$(get_ufw_log_status)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) ufw_add_port ;; 
            2) ufw_add_ip ;; 
            3) ufw_show_delete ;; 
            4) ufw_limits_menu ;; 
            5) ufw_logs_menu ;;
            0) return ;;
        esac
    done
}
