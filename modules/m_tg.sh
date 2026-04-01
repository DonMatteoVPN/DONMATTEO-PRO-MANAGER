#!/bin/bash

# Функция статуса (используется в главном меню)
get_tg_status() {
    if systemctl is-active --quiet antiscan-aggregate.timer; then 
        echo -e "${GREEN}[РАБОТАЕТ]${NC}"
    elif [[ -f /usr/local/bin/traffic-guard ]]; then 
        echo -e "${YELLOW}[УСТАНОВЛЕН, НО НЕ АКТИВЕН]${NC}"
    else 
        echo -e "${RED}[НЕ УСТАНОВЛЕНО]${NC}"
    fi
}

tg_sources_menu() {
    while true; do
        clear; echo -e "${MAGENTA}=== ИСТОЧНИКИ TRAFFICGUARD ===${NC}"
        # Инициализация файлов если их нет
        [[ ! -f "$TG_URL_FILE" ]] && echo "https://raw.githubusercontent.com/DonMatteoVPN/TrafficGuard/main/install.sh" > "$TG_URL_FILE"
        [[ ! -f "$TG_LISTS_FILE" ]] && touch "$TG_LISTS_FILE"

        echo -e "${CYAN}Установщик (Основная ссылка):${NC}\n$(cat "$TG_URL_FILE")\n"
        echo -e "${CYAN}Списки блокировок (Подсети и IP):${NC}"
        local i=1; declare -a LIST_ARRAY
        while read -r line; do 
            [[ -n "$line" ]] && { echo -e "  ${YELLOW}[$i]${NC} $line"; LIST_ARRAY[$i]="$line"; ((i++)); }; 
        done < "$TG_LISTS_FILE"
        [ $i -eq 1 ] && echo "  (Списков нет)"
        
        echo -e "\n ${GREEN}1.${NC} Изменить URL установщика | ${GREEN}2.${NC} Добавить список | ${RED}3.${NC} Удалить | ${CYAN}0.${NC} Назад"
        read -p ">> " src_choice
        case $src_choice in
            1) read -p "Впишите новый URL: " url; [[ -n "$url" ]] && echo "$url" > "$TG_URL_FILE" && echo -e "${GREEN}Успешно сохранено!${NC}"; sleep 1 ;;
            2) read -p "Впишите URL списка: " lst; [[ -n "$lst" ]] && { grep -q -F "$lst" "$TG_LISTS_FILE" && echo -e "${YELLOW}Уже есть в базе.${NC}" || { echo "$lst" >> "$TG_LISTS_FILE"; echo -e "${GREEN}Успешно добавлено!${NC}"; }; }; sleep 1 ;;
            3) read -p "Введите НОМЕР: " num; [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -lt "$i" ] && [ "$num" -gt 0 ] && { grep -v -x -F "${LIST_ARRAY[$num]}" "$TG_LISTS_FILE" > /tmp/tg_tmp && mv /tmp/tg_tmp "$TG_LISTS_FILE"; echo -e "${GREEN}Успешно удалено.${NC}"; sleep 1; } ;;
            0) return ;;
        esac
    done
}

tg_install() {
    clear; echo -e "${CYAN}🚀 УСТАНОВКА TRAFFICGUARD PRO (SMART MODE)${NC}"
    
    echo -e "${YELLOW}[*] Установка зависимостей...${NC}"
    smart_apt_install "curl" || return 1
    smart_apt_install "wget" || return 1
    smart_apt_install "rsyslog" || return 1
    smart_apt_install "ipset" || return 1
    smart_apt_install "whois" || return 1
    
    echo -e "\n${YELLOW}[*] Предустановка Grafana (обход блокировок)...${NC}"
    install_grafana_mirror || echo -e "${YELLOW}[!] Grafana не установлена — продолжаем без неё (необязательный компонент).${NC}"

    systemctl enable --now rsyslog

    echo -e "\n${YELLOW}[*] Скачивание и запуск установщика TrafficGuard...${NC}"
    # Гарантируем наличие URL
    [[ ! -f "$TG_URL_FILE" ]] && echo "https://raw.githubusercontent.com/DonMatteoVPN/TrafficGuard/main/install.sh" > "$TG_URL_FILE"
    local TG_URL=$(cat "$TG_URL_FILE")
    
    smart_curl "$TG_URL" "/tmp/tg_install.sh" || {
        echo -e "${RED}[!] Ошибка скачивания скрипта TG.${NC}"; pause; return;
    }
    
    bash /tmp/tg_install.sh
    
    if command -v traffic-guard >/dev/null; then
        local TG_ARGS=""
        if [[ -f "$TG_LISTS_FILE" ]]; then
            while read -r list; do [[ -n "$list" ]] && TG_ARGS+=" -u $list"; done < "$TG_LISTS_FILE"
        fi
        traffic-guard full $TG_ARGS --enable-logging
        
        # Настройка логов
        mkdir -p /var/log; touch /var/log/iptables-scanners-{ipv4,ipv6}.log
        local LOG_GROUP="syslog"; getent group adm >/dev/null && LOG_GROUP="adm"
        chown syslog:$LOG_GROUP /var/log/iptables-scanners-*.log; chmod 640 /var/log/iptables-scanners-*.log
        
        systemctl restart rsyslog
        systemctl restart antiscan-aggregate.service 2>/dev/null || true
        # Перезапускаем таймер только если он существует
        if systemctl list-unit-files | grep -q antiscan-aggregate.timer; then
            systemctl restart antiscan-aggregate.timer
        fi
        echo -e "\n${GREEN}✅ Установка полностью завершена!${NC}"; pause
    else
        echo -e "\n${RED}[!] Скрипт TrafficGuard отработал с ошибками.${NC}"; pause
    fi
}

tg_uninstall() {
    echo -e "\n${RED}=== УДАЛЕНИЕ TRAFFICGUARD ===${NC}"; read -p "Вы точно уверены? (y/N): " confirm; [[ "$confirm" != "y" ]] && return
    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null; systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    rm -f /usr/local/bin/traffic-guard /usr/local/bin/antiscan-aggregate-logs.sh
    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null; iptables -F SCANNERS-BLOCK 2>/dev/null; iptables -X SCANNERS-BLOCK 2>/dev/null
    ipset flush SCANNERS-BLOCK-V4 2>/dev/null; ipset destroy SCANNERS-BLOCK-V4 2>/dev/null
    systemctl restart rsyslog; echo -e "${GREEN}✅ Успешно удалено.${NC}"; pause
}

tg_ban_unban() {
    while true; do
        clear; echo -e "${MAGENTA}=== 🧪 УПРАВЛЕНИЕ IP TRAFFICGUARD ===${NC}"
        echo -e " ${RED}1.${NC} ЗАБАНИТЬ IP | ${GREEN}2.${NC} РАЗБАНИТЬ IP | ${CYAN}0.${NC} Назад"
        read -p ">> " action
        case $action in
            1) read -p "Впишите IP: " ip; [[ -z "$ip" ]] && continue; OUTPUT=$(ipset add SCANNERS-BLOCK-V4 "$ip" 2>&1); if [ $? -eq 0 ]; then echo -e "${GREEN}✅ ЗАБЛОКИРОВАН!${NC}"; grep -Fxq "$ip" "$MANUAL_FILE" || echo "$ip" >> "$MANUAL_FILE"; else echo -e "${RED}❌ Возникла ошибка:${NC} $OUTPUT"; fi; sleep 1 ;;
            2) echo -e "\n${GREEN}=== РУЧНЫЕ БАНЫ ===${NC}"; if [ ! -s "$MANUAL_FILE" ]; then echo "Список пуст."; pause; continue; fi
               mapfile -t MANUAL_IPS < "$MANUAL_FILE"; local i=1; for ip in "${MANUAL_IPS[@]}"; do echo -e "  ${YELLOW}[$i]${NC} $ip"; ((i++)); done
               read -p "НОМЕР или IP (0 - Назад): " input; [[ "$input" == "0" || -z "$input" ]] && continue
               if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -le "${#MANUAL_IPS[@]}" ]; then local INDEX=$((input-1)); local TARGET_IP="${MANUAL_IPS[$INDEX]}"; else local TARGET_IP="$input"; fi
               ipset del SCANNERS-BLOCK-V4 "$TARGET_IP" >/dev/null 2>&1; sed -i "/^$TARGET_IP$/d" "$MANUAL_FILE"; echo -e "${GREEN}✅ Успешно разбанен!${NC}"; sleep 1 ;;
            0) return ;;
        esac
    done
}

menu_trafficguard() {
    while true; do
        clear
        local IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep -c "^\([0-9]\)" 2>/dev/null || echo "0")
        local PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | grep "LOG" | awk '{print $1}')
        [[ -z "$PKTS_CNT" ]] && PKTS_CNT="0"
        
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🚦 УПРАВЛЕНИЕ TRAFFICGUARD PRO ${NC}$(get_tg_status)"
        echo -e "${GRAY} Защита от цензоров (ТСПУ) и активного зондирования.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "  📊 В базе: ${GREEN}${IPSET_CNT}${NC} подсетей | 🔥 Отбито: ${RED}${PKTS_CNT}${NC} атак"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${YELLOW}1.${NC} 📈 Топ атак (Статистика CSV)"
        echo -e " ${YELLOW}2.${NC} 🕵 Логи (Live просмотр)"
        echo -e " ${YELLOW}3.${NC} 🧪 Управление IP (Ручной Ban/Unban)"
        echo -e " ${YELLOW}4.${NC} 🔄 Обновить базы из Источников"
        echo -e " ${YELLOW}5.${NC} 📁 Редактировать Источники (URL / Списки)"
        echo -e " ${YELLOW}6.${NC} 🛠️  Установить / Переустановить"
        echo -e " ${RED}7.${NC} 🗑️  Удалить TrafficGuard с сервера"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) clear; echo -e "${GREEN}ТОП 20 АТАКУЮЩИХ:${NC}"; [ -f /var/log/iptables-scanners-aggregate.csv ] && tail -20 /var/log/iptables-scanners-aggregate.csv || echo "Нет собранных данных"; pause ;;
            2) clear; echo -e "${YELLOW}Нажмите Ctrl+C для возврата...${NC}"; tail -f /var/log/iptables-scanners-ipv4.log ;;
            3) tg_ban_unban ;;
            4) clear; local TG_ARGS=""; [[ -f "$TG_LISTS_FILE" ]] && while read -r list; do [[ -n "$list" ]] && TG_ARGS+=" -u $list"; done < "$TG_LISTS_FILE"; traffic-guard full $TG_ARGS --enable-logging; echo -e "${GREEN}Списки успешно обновлены.${NC}"; sleep 2 ;;
            5) tg_sources_menu ;; 6) tg_install ;; 7) tg_uninstall ;; 0) return ;;
        esac
    done
}
