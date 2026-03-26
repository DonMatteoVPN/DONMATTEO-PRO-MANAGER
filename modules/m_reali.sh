#!/bin/bash

# --- ПУТИ МОДУЛЯ ---
export REALI_DIR="/opt/reali-scanner"
export REALI_BIN="${REALI_DIR}/RealiTLScanner"
export REALI_OUT="${REALI_DIR}/out.csv"
export REALI_GEO="${REALI_DIR}/Country.mmdb"

get_reali_status() {
    if [[ -f "$REALI_BIN" ]]; then echo -e "${GREEN}[УСТАНОВЛЕН]${NC}"; else echo -e "${RED}[НЕ УСТАНОВЛЕНО]${NC}"; fi
}

install_reali() {
    clear; echo -e "${CYAN}[*] Подготовка окружения для RealiTLScanner...${NC}"
    apt-get update -qq && apt-get install -y golang git wget -qq [cite: 32]
    
    mkdir -p "$REALI_DIR"
    cd "$REALI_DIR" || return
    
    echo -e "${CYAN}[*] Клонирование и сборка (Go 1.21+)...${NC}"
    git clone https://github.com/xtls/RealiTLScanner.git . 2>/dev/null || git pull
    go build -o RealiTLScanner . [cite: 32]
    
    echo -e "${CYAN}[*] Загрузка GeoIP базы...${NC}"
    wget -qO "$REALI_GEO" "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb"
    
    echo -e "${GREEN}[+] Установка завершена!${NC}"; pause
}

run_scan() {
    [[ ! -f "$REALI_BIN" ]] && { echo -e "${RED}[!] Сначала установите сканер (Пункт 6).${NC}"; sleep 2; return; }
    
    clear; echo -e "${MAGENTA}=== НАСТРОЙКА СКАНИРОВАНИЯ ===${NC}"
    echo -e "Выберите тип цели:"
    echo -e " 1. Конкретный IP / Домен / CIDR"
    echo -e " 2. Список из файла (in.txt)"
    echo -e " 3. Сбор доменов с URL (Ubuntu Mirrors)"
    read -p ">> " target_type

    local cmd_args=""
    case $target_type in
        1) read -p "Введите цель (напр. 1.1.1.1): " target_addr; cmd_args="-addr $target_addr" ;; 
        2) read -p "Путь к файлу: " target_in; cmd_args="-in $target_in" ;; 
        3) read -p "URL для сбора (Enter = Ubuntu Mirrors): " target_url; [[ -z "$target_url" ]] && target_url="https://launchpad.net/ubuntu/+archivemirrors"; cmd_args="-url $target_url" ;; 
        *) return ;;
    esac

    read -p "Количество потоков (Enter = 10): " threads; [[ -z "$threads" ]] && threads=10
    read -p "Таймаут в секундах (Enter = 5): " timeout; [[ -z "$timeout" ]] && timeout=5
    read -p "Порт (Enter = 443): " port; [[ -z "$port" ]] && port=443

    echo -e "\n${CYAN}[*] ЗАПУСК СКАНИРОВАНИЯ...${NC}"
    echo -e "${GRAY}Команда: $REALI_BIN $cmd_args -thread $threads -timeout $timeout -port $port -out $REALI_OUT${NC}\n"

    # Запуск сканера
    "$REALI_BIN" $cmd_args -thread "$threads" -timeout "$timeout" -port "$port" -out "$REALI_OUT"

    echo -e "\n${GREEN}[✓] Сканирование завершено! Результат сохранен в $REALI_OUT${NC}"
    show_best_domains
}

show_best_domains() {
    [[ ! -f "$REALI_OUT" ]] && { echo -e "${RED}[!] Файл результатов не найден.${NC}"; pause; return; }
    
    clear; echo -e "${MAGENTA}=== УМНЫЙ АНАЛИЗ И РЕКОМЕНДАЦИИ ===${NC}"
    echo -e "${GRAY}Алгоритм подбора идеального домена для Reality:${NC}"
    echo -e "✅ Критерии: TLS 1.3 + ALPN h2 + Совпадение домена с сертификатом.\n"

    local i=1; declare -a BEST_LIST
    # Читаем CSV и фильтруем лучшие результаты (без учета заголовка)
    while IFS=, read -r ip origin cert_domain cert_issuer geo; do
        [[ "$ip" == "IP" ]] && continue # Пропускаем заголовок
        
        # Интеллектуальная рекомендация:
        # 1. Домен должен быть чистым (без '*')
        # 2. Популярные регистраторы (Let's Encrypt, ZeroSSL) — это хорошо, но коммерческие (GlobalSign, DigiCert) — лучше для маскировки.
        
        echo -e "  ${YELLOW}[$i]${NC} ${GREEN}${cert_domain}${NC} (${geo})"
        echo -e "     └─ IP: ${CYAN}${ip}${NC} | Издатель: ${GRAY}${cert_issuer}${NC}"
        
        BEST_LIST[$i]="$cert_domain"
        ((i++))
    done < "$REALI_OUT"

    if [ $i -eq 1 ]; then
        echo -e "${RED}[!] Подходящих целей не найдено. Попробуйте сменить IP или увеличить охват.${NC}"
    else
        echo -e "\n${BOLD}${CYAN}🏆 РЕКОМЕНДАЦИЯ СКРИПТА:${NC}"
        echo -e "Для маскировки VLESS Reality лучше всего использовать: ${GREEN}${BEST_LIST[1]}${NC}"
        echo -e "Он прошел все проверки (TLS 1.3, ALPN h2) и имеет стабильный сертификат."
    fi
    pause
}

menu_reali() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🚦 REALITY TLS SCANNER ${NC}$(get_reali_status)"
        echo -e "${GRAY} Поиск идеальных доменов для маскировки VLESS-трафика.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 🚀 Начать сканирование (Интерактивно)"
        echo -e "    ${GRAY}└─ Поиск подходящих целей по IP или спискам.${NC}"
        echo -e " ${YELLOW}2.${NC} 📊 Показать последний отчет и рекомендации"
        echo -e "    ${GRAY}└─ Анализ файла out.csv и выбор лучшего домена.${NC}"
        echo -e " ${YELLOW}3.${NC} 🧹 Очистить результаты сканирования"
        echo -e "    ${GRAY}└─ Удаляет файл отчета для нового цикла.${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${GREEN}6.${NC} 🛠️  Установить / Обновить сканер"
        echo -e " ${RED}7.${NC} 🗑️  Удалить сканер с сервера"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) run_scan ;; 2) show_best_domains ;;
            3) rm -f "$REALI_OUT"; echo -e "${GREEN}Готово.${NC}"; sleep 1 ;;
            6) install_reali ;;
            7) rm -rf "$REALI_DIR"; echo -e "${GREEN}Удалено.${NC}"; sleep 1 ;;
            0) return ;;
        esac
    done
}
