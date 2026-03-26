#!/bin/bash
# Модуль управления TrafficGuard PRO

# Функция получения статистики атак
get_tg_stats() {
    # Считаем уникальные заблокированные IP из системного журнала за последние 24 часа
    local count=$(journalctl -k --since "24h" | grep -c "UFW BLOCK" || echo "0")
    echo "$count"
}

# Функция вывода Топ-10 атакующих IP
show_tg_top() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 📈 ТОП-10 ИСТОЧНИКОВ АТАК (ЗА 24 ЧАСА)${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${GRAY}Анализ системного журнала...${NC}\n"

    # Парсим journalctl: ищем блокировки UFW, вырезаем SRC=IP, считаем уникальные
    local top_list=$(journalctl -k --since "24h" | grep "UFW BLOCK" | grep -oP "SRC=\K[0-9.]+" | sort | uniq -c | sort -rn | head -10)

    if [[ -z "$top_list" ]]; then
        echo -e "${YELLOW} Активных атак за последние 24 часа не зафиксировано.${NC}"
    else
        echo -e "${CYAN} Кол-во  |  IP Адрес${NC}"
        echo -e "------------------------------------------------------"
        echo "$top_list" | while read -r line; do
            local hits=$(echo "$line" | awk '{print $1}')
            local ip=$(echo "$line" | awk '{print $2}')
            printf "  %-7s |  %s\n" "$hits" "$ip"
        done
    fi
    echo -e "${MAGENTA}======================================================${NC}"
    pause
}

# Функция Live-просмотра логов
show_tg_live() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 🕵 LIVE-ПОТОК БЛОКИРОВОК (Нажмите Ctrl+C для выхода)${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    # Читаем только новые записи лога ядра, фильтруя UFW
    journalctl -k -f | grep --line-buffered "UFW BLOCK" | while read -r line; do
        local ip=$(echo "$line" | grep -oP "SRC=\K[0-9.]+")
        local proto=$(echo "$line" | grep -oP "PROTO=\K\w+")
        local port=$(echo "$line" | grep -oP "DPT=\K[0-9]+")
        echo -e "${RED}[BLOCK]${NC} IP: ${YELLOW}$ip${NC} | Proto: ${CYAN}$proto${NC} | Port: ${CYAN}$port${NC}"
    done
}

menu_trafficguard() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "  🚦 УПРАВЛЕНИЕ TRAFFICGUARD PRO $(get_tg_status)"
        echo -e "  Защита от цензоров (ТСПУ) и активного зондирования."
        echo -e "${BLUE}======================================================${NC}"
        
        # Динамическая статистика
        local subnet_count=$(wc -l < "$WHITELIST_FILE" 2>/dev/null || echo "0")
        local attack_count=$(get_tg_stats)
        
        echo -e "  📊 В базе: ${CYAN}$subnet_count${NC} подсетей | 🔥 Отбито: ${RED}$attack_count${NC} атак"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        
        echo -e " ${YELLOW}1.${NC} 📈 Топ атак (Анализ логов)"
        echo -e "    └─ Статистика, кто чаще всего сканирует твой сервер."
        echo -e " ${YELLOW}2.${NC} 🕵 Логи (Live просмотр)"
        echo -e "    └─ Поток пакетов, отбрасываемых TrafficGuard."
        echo -e " ${YELLOW}3.${NC} 🧪 Управление IP (Ручной Ban/Unban)"
        echo -e "    └─ Ручная блокировка вредных подсетей."
        echo -e " ${YELLOW}4.${NC} 🔄 Обновить базы из Источников"
        echo -e "    └─ Скачивает свежие списки РКН и сканеров."
        echo -e " ${YELLOW}5.${NC} 📁 Редактировать Источники (URL / Списки)"
        echo -e "    └─ Ссылки на файлы с IP адресами для блокировки."
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}6.${NC} 🛠️  Установить / Переустановить"
        echo -e " ${RED}7.${NC} 🗑️  Удалить TrafficGuard с сервера"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -p ">> " choice
        case $choice in
            1) show_tg_top ;;
            2) show_tg_live ;;
            3) # Здесь должна быть твоя функция управления IP
               echo "Функция в разработке"; sleep 1 ;;
            4) # Здесь функция обновления баз
               echo "Обновление..."; sleep 1 ;;
            6) # Твой скрипт установки
               echo "Установка..."; sleep 1 ;;
            0) return ;;
            *) echo -e "${RED}Ошибка: Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}
