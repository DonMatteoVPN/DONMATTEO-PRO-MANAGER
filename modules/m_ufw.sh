#!/bin/bash
# Модуль UFW (Сетевой экран и Anti-DDoS)

[[ ! -f "$CONN_VAL_FILE" ]] && echo "150" > "$CONN_VAL_FILE"
[[ ! -f "$RATE_VAL_FILE" ]] && echo "80" > "$RATE_VAL_FILE"
[[ ! -f "$CONNLIMIT_FILE" ]] && touch "$CONNLIMIT_FILE"
[[ ! -f "$RATELIMIT_FILE" ]] && touch "$RATELIMIT_FILE"

get_sysctl_status() {
    if [[ "$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)" == "1" ]]; then echo -e "${GREEN}[ВКЛЮЧЕНО]${NC}"; else echo -e "${RED}[НЕ УСТАНОВЛЕНО]${NC}"; fi
}

get_ufw_status() {
    if ufw status 2>/dev/null | grep -qw active; then echo -e "${GREEN}[РАБОТАЕТ]${NC}"; else echo -e "${RED}[ВЫКЛЮЧЕН]${NC}"; fi
}

get_ufw_log_status() {
    if LANG=C ufw status verbose 2>/dev/null | grep -iq "logging: on"; then echo -e "${GREEN}[ВКЛЮЧЕНЫ]${NC}"; else echo -e "${RED}[ВЫКЛЮЧЕНЫ]${NC}"; fi
}

ensure_rsyslog() {
    if ! command -v rsyslogd &> /dev/null; then
        echo -e "${CYAN}[*] Служба rsyslog не найдена. Установка для работы логов...${NC}"
        smart_apt_install "rsyslog"
        systemctl enable --now rsyslog >/dev/null 2>&1
        sleep 2
    fi
    if ! systemctl is-active --quiet rsyslog; then systemctl start rsyslog; fi
    if [ ! -f /var/log/ufw.log ]; then touch /var/log/ufw.log; chmod 640 /var/log/ufw.log; chown syslog:adm /var/log/ufw.log; fi
}

# --- АВТОМАТИЧЕСКИЙ СКАНЕР ОТКРЫТЫХ ПОРТОВ ---
ufw_auto_protect_open_ports() {
    echo -e "${CYAN}[*] Авто-сканирование открытых портов UFW...${NC}"
    
    local open_ports=$(ufw show added 2>/dev/null | grep -i "allow" | grep -i "tcp" | awk '{print $3}' | cut -d'/' -f1 | grep -E '^[0-9]+$' | sort -u)
    
    local ACTIVE_SSH=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    [[ -z "$ACTIVE_SSH" ]] && ACTIVE_SSH="22"

    local added=0
    for port in $open_ports; do
        [[ "$port" == "$ACTIVE_SSH" ]] && continue
        
        local is_new=0
        if ! grep -q "^${port}$" "$CONNLIMIT_FILE" 2>/dev/null; then
            echo "$port" >> "$CONNLIMIT_FILE"
            is_new=1
        fi
        if ! grep -q "^${port}$" "$RATELIMIT_FILE" 2>/dev/null; then
            echo "$port" >> "$RATELIMIT_FILE"
            is_new=1
        fi
        [[ "$is_new" -eq 1 ]] && ((added++))
    done
    
    if [ "$added" -gt 0 ]; then
        echo -e "${GREEN}[+] Автоматически добавлено под Anti-DDoS защиту портов: $added${NC}"
    else
        echo -e "${GRAY}[i] Новых открытых портов для защиты не найдено.${NC}"
    fi
}

ufw_global_setup() {
    echo -e "${CYAN}[*] Пересборка правил Anti-DDoS (Без изменения открытых портов)...${NC}"
    smart_apt_install "ufw" || return 1

    local CONN_LIMIT
    CONN_LIMIT=$(cat "$CONN_VAL_FILE")
    local RATE_LIMIT
    RATE_LIMIT=$(cat "$RATE_VAL_FILE")

    # Резервная копия и восстановление, если файл был поврежден предыдущими скриптами
    [[ -f /etc/ufw/before.rules ]] && cp /etc/ufw/before.rules /etc/ufw/before.rules.bak
    if ! grep -q ":ufw-before-output - \[0:0\]" /etc/ufw/before.rules 2>/dev/null; then
        if [[ -f /usr/share/ufw/before.rules ]]; then
            echo -e "${YELLOW}[!] Файл before.rules поврежден. Восстанавливаем из системного шаблона...${NC}"
            cp -f /usr/share/ufw/before.rules /etc/ufw/before.rules
        fi
    fi

    # Whitelist: применяем через UFW allow from IP (автоматически)
    if [[ -f "$WHITELIST_FILE" ]]; then
        while IFS= read -r wl_line; do
            local wl_ip
            wl_ip=$(echo "$wl_line" | awk '{print $1}')
            [[ "$wl_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9] ]] || continue
            local wl_comment
            wl_comment=$(echo "$wl_line" | sed 's/^[^ ]*//' | sed 's/^[[:space:]]*//' | sed 's/^#[[:space:]]*//')
            [[ -z "$wl_comment" ]] && wl_comment="Whitelist"
            ufw allow from "$wl_ip" comment "$wl_comment" >/dev/null 2>&1 || true
        done < "$WHITELIST_FILE"
    fi

    local ACTIVE_SSH
    ACTIVE_SSH=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    [[ -z "$ACTIVE_SSH" ]] && ACTIVE_SSH="22"

    # ==================================================================
    # Строим before.rules через Python (надёжнее sed для многострочных блоков)
    # ==================================================================
    python3 - <<PYEOF
import re

with open('/etc/ufw/before.rules', 'r') as f:
    content = f.read()

# Очищаем старые блоки (любые варианты с НАЧАЛО/КОНЕЦ)
content = re.sub(r'# --- НАЧАЛО: Правила защиты от DDoS.*?# --- КОНЕЦ: Правила защиты от DDoS.*?\n', '', content, flags=re.DOTALL)
content = re.sub(r'# --- НАЧАЛО: Защита от сканеров.*?# --- КОНЕЦ: Защита от сканеров.*?\n', '', content, flags=re.DOTALL)
content = re.sub(r'# --- НАЧАЛО: Лимит одновременных.*?# --- КОНЕЦ: Лимит одновременных.*?\n', '', content, flags=re.DOTALL)
content = re.sub(r'# --- НАЧАЛО: Направляем трафик.*?# --- КОНЕЦ: Направляем трафик.*?\n', '', content, flags=re.DOTALL)

# Очищаем остатки старых IN_LIMIT и DON_LIMITS если они были вне блоков
lines = [l for l in content.split('\n') if not l.startswith(':IN_LIMIT') and not l.startswith('-A IN_LIMIT') and not l.startswith(':DON-LIMITS') and not l.startswith('-A DON-LIMITS')]
content = '\n'.join(lines)

# 1. Цепочка IN_LIMIT вставляется после *filter
chain_block = """# --- НАЧАЛО: Правила защиты от DDoS (DonMatteo) ---
:IN_LIMIT - [0:0]
-A IN_LIMIT -m limit --limit ${RATE_LIMIT}/s --limit-burst 250 -j RETURN
-A IN_LIMIT -j DROP
# --- КОНЕЦ: Правила защиты от DDoS (DonMatteo) ---
"""
if '*filter' in content:
    content = content.replace('*filter', '*filter\n' + chain_block, 1)

# 2. Строим блок правил для ufw-before-input
input_rules = []

# Защита от сканеров
input_rules.append('\n# --- НАЧАЛО: Защита от сканеров и кривых пакетов ---')
input_rules.append('-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP')
input_rules.append('-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP')
input_rules.append('-A ufw-before-input -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP')
input_rules.append('-A ufw-before-input -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP')
input_rules.append('-A ufw-before-input -p tcp --tcp-flags SYN,RST SYN,RST -j DROP')
input_rules.append('-A ufw-before-input -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP')
input_rules.append('-A ufw-before-input -p tcp --tcp-flags ALL SYN,ACK,FIN,RST,PSH,URG -j DROP')
input_rules.append('\n# Лимит на ICMP (Защита от Ping Flood)')
input_rules.append('-A ufw-before-input -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT')
input_rules.append('-A ufw-before-input -p icmp --icmp-type echo-request -j DROP')
input_rules.append('# --- КОНЕЦ: Защита от сканеров ---')

# CONNLIMIT
conn_ports = []
try:
    with open('${CONNLIMIT_FILE}') as cf:
        conn_ports = [p.strip() for p in cf if p.strip().isdigit()]
except: pass

if conn_ports:
    input_rules.append('# --- НАЧАЛО: Лимит одновременных соединений (Анти-ДДОС L4 на 1 IP) ---')
    for p in conn_ports:
        input_rules.append(f'-A ufw-before-input -p tcp --dport {p} -m connlimit --connlimit-above ${CONN_LIMIT} --connlimit-mask 32 -j DROP')
    input_rules.append('# --- КОНЕЦ: Лимит одновременных соединений ---')

# RATELIMIT
rate_ports = []
try:
    with open('${RATELIMIT_FILE}') as rf:
        rate_ports = [p.strip() for p in rf if p.strip().isdigit()]
except: pass

all_rate_ports = ['${ACTIVE_SSH}'] + [p for p in rate_ports if p != '${ACTIVE_SSH}']
input_rules.append('# --- НАЧАЛО: Направляем трафик на проверку скорости (Глобальный лимит) ---')
for p in all_rate_ports:
    input_rules.append(f'-A ufw-before-input -p tcp --dport {p} -m conntrack --ctstate NEW -j IN_LIMIT')
input_rules.append('# --- КОНЕЦ: Направляем трафик на проверку скорости ---')

input_block = '\n'.join(input_rules) + '\n'

# Вставляем ПОСЛЕ :ufw-before-input - [0:0]
target = ':ufw-before-input - [0:0]'
if target in content:
    content = content.replace(target, target + '\n' + input_block, 1)

with open('/etc/ufw/before.rules', 'w') as f:
    f.write(content)
print('before.rules OK')
PYEOF

    # UFW defaults: incoming=deny, outgoing=allow (стандарт — не меняем оутгоинг)
    ufw default deny incoming  > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1

    echo "y" | ufw enable > /dev/null 2>&1
    ufw reload > /dev/null 2>&1
    echo -e "${GREEN}[+] Правила Anti-DDoS применены. Conn=${CONN_LIMIT}, Rate=${RATE_LIMIT}/s${NC}"
    echo -e "${GRAY}    └─ Before.rules обновлён. SSH: ${ACTIVE_SSH}${NC}"
}

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

ufw_logs_menu() {
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
            2) ufw logging high; echo -e "${YELLOW}Логи включены (high)${NC}"; sleep 1 ;;
            3) ufw logging off; echo -e "${RED}Логи выключены${NC}"; sleep 1 ;;
            4) view_ufw_logs_live ;;
            5) show_top_attackers ;;
            6) show_top_ports ;;
            0) return ;;
        esac
    done
}

view_ufw_logs_live() {
    clear
    echo -e "${YELLOW}Мониторинг блокировок (Нажмите Ctrl+C для выхода)...${NC}"
    echo -e "${GRAY}Вы будете видеть только события [BLOCK] и [LIMIT]${NC}\n"
    if [ ! -s /var/log/ufw.log ]; then
        echo -e "${YELLOW}Лог-файл пока пуст. Попробуйте обновить страницу позже.${NC}"
        pause; return
    fi
    tail -f /var/log/ufw.log | grep --line-buffered -E "\[UFW (BLOCK|LIMIT)\]" | awk '{
        match($0, /SRC=([0-9.]+)/, src);
        match($0, /DPT=([0-9]+)/, dpt);
        match($0, /PROTO=([A-Z]+)/, proto);
        port = (dpt[1] ? dpt[1] : "---");
        print "\033[1;31m[DROP]\033[0m IP: \033[1;33m" src[1] "\033[0m -> Port: \033[1;36m" port "\033[0m (" proto[1] ")"
    }'
}

show_top_attackers() {
    clear; echo -e "${MAGENTA}=== ТОП-10 IP ПОД БЛОКИРОВКОЙ ===${NC}\n"
    if [ ! -s /var/log/ufw.log ]; then echo -e "${RED}Файл логов пуст.${NC}"; pause; return; fi
    grep "UFW BLOCK" /var/log/ufw.log | awk -F'SRC=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 10 | awk '{print "  [" $1 " атак] - " $2}'
    pause
}

show_top_ports() {
    clear; echo -e "${MAGENTA}=== САМЫЕ АТАКУЕМЫЕ ПОРТЫ ===${NC}\n"
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
    echo -e "\n${BOLD}2. RATELIMIT (Скорость новых запросов)${NC}"
    echo -e "   ${CYAN}Как работает:${NC} Сколько РАЗ в секунду клиент может постучаться на порт."
    echo -e "   ${CYAN}Для VPN:${NC} Обычный клиент стучится 1-2 раза при подключении."
    echo -e "   Боты-сканеры (Shodan) стучатся 500+ раз в секунду."
    echo -e "   ${GREEN}Рекомендуемое значение:${NC} 50-100 в секунду."
    pause
}

ufw_add_port() {
    clear; echo -e "${MAGENTA}=== ОТКРЫТИЕ ПОРТА ===${NC}"; read -p "Впишите порт: " port; [[ -z "$port" ]] && return
    read -p "Укажите протокол (tcp/udp/any) [any]: " proto; [[ -z "$proto" || "$proto" == "any" ]] && proto_str="" || proto_str="/$proto"
    read -p "Добавьте комментарий: " comment; [[ -z "$comment" ]] && comment="Manual_Rule"
    
    ufw allow ${port}${proto_str} comment "${comment}" >/dev/null 2>&1
    echo -e "${GREEN}Правило успешно добавлено в UFW!${NC}"
    
    if [[ -z "$proto_str" || "$proto_str" == "/tcp" ]]; then
        grep -q "^$port$" "$CONNLIMIT_FILE" || echo "$port" >> "$CONNLIMIT_FILE"
        grep -q "^$port$" "$RATELIMIT_FILE" || echo "$port" >> "$RATELIMIT_FILE"
        ufw_global_setup >/dev/null 2>&1
        echo -e "${YELLOW}[i] Порт $port автоматически взят под защиту Anti-DDoS.${NC}"
    fi
    pause
}

ufw_add_ip() {
    clear; echo -e "${MAGENTA}=== ДОСТУП ДЛЯ IP ===${NC}"; read -p "Впишите IP адрес: " ip; [[ -z "$ip" ]] && return
    read -p "Впишите порт (или 'any' для всех) [any]: " port; [[ -z "$port" ]] && port="any"
    read -p "Укажите протокол (tcp/udp/any)[any]: " proto; [[ -z "$proto" || "$proto" == "any" ]] && proto_str="" || proto_str="proto $proto"
    read -p "Добавьте комментарий: " comment; [[ -z "$comment" ]] && comment="IP_Access"
    if [[ "$port" == "any" ]]; then ufw allow from $ip comment "$comment"; else ufw allow from $ip to any port $port $proto_str comment "$comment"; fi
    echo -e "${GREEN}Доступ разрешен!${NC}"; pause
}

ufw_show_delete() {
    while true; do
        clear; echo -e "${MAGENTA}=== УДАЛЕНИЕ ПРАВИЛ FIREWALL ===${NC}"
        ufw status numbered 2>/dev/null | sed -e 's/Status: active/Статус: Активен/' -e 's/Status: inactive/Статус: Выключен/' -e 's/To/Куда/' -e 's/Action/Действие/' -e 's/From/Откуда/'
        echo -e "\nВведите ${YELLOW}НОМЕР${NC} для удаления, или ${YELLOW}0${NC} для выхода:"
        read -p ">> " num
        [[ "$num" == "0" || -z "$num" ]] && return
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            echo "y" | ufw delete $num >/dev/null 2>&1
            echo -e "${GREEN}Правило удалено.${NC}"
            ufw_global_setup >/dev/null 2>&1
            sleep 1
        else
            echo -e "${RED}Ошибка ввода.${NC}"; sleep 1
        fi
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
