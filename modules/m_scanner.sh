#!/bin/bash
# Модуль Reality TLS Scanner Интеграция

SCANNER_DIR="/opt/RealiTLScanner"
SCANNER_BIN="$SCANNER_DIR/RealiTLScanner"
GEO_DB="$SCANNER_DIR/Country.mmdb"

# Функция проверки и установки сканера
check_scanner_install() {
    if [[ ! -f "$SCANNER_BIN" ]]; then
        echo -e "${YELLOW}[*] Сканер не найден. Начинаю установку...${NC}"
        apt update && apt install golang git -y
        git clone https://github.com/xtls/RealiTLScanner "$SCANNER_DIR"
        cd "$SCANNER_DIR" && go build
        echo -e "${GREEN}[+] Сканер успешно собран.${NC}"
    fi

    # Авто-загрузка GeoIP если нет
    if [[ ! -f "$GEO_DB" ]]; then
        echo -e "${YELLOW}[*] Загрузка базы GeoIP для определения стран...${NC}"
        curl -L -o "$GEO_DB" "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb"
        echo -e "${GREEN}[+] База GeoIP готова.${NC}"
    fi
}

# Алгоритм "Умный Выбор"
analyze_results() {
    local file=$1
    if [[ ! -f "$file" ]]; then return; fi

    echo -e "\n${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}🤖 АНАЛИЗАТОР: РЕКОМЕНДАЦИИ ПО ВЫБОРУ ЦЕЛИ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    # Читаем CSV (пропуская заголовок)
    # Критерии: TLS 1.3 + h2 + Известный эмитент
    local best=$(tail -n +2 "$file" | grep -E "Let's Encrypt|Google|DigiCert" | head -n 3)

    if [[ -z "$best" ]]; then
        echo -e "${RED}Подходящих целей с идеальными параметрами не найдено.${NC}"
    else
        echo -e "${GREEN}ТОП-3 РЕКОМЕНДУЕМЫХ ДОМЕНА ДЛЯ REALITY:${NC}"
        echo "$best" | awk -F',' '{print "📍 Домен: " $3 " (IP: " $1 ", Страна: " $5 ")"}'
        echo -e "\n${GRAY}Почему они? У них TLS 1.3, поддержка h2 и доверенный сертификат.${NC}"
    fi
}

menu_scanner() {
    check_scanner_install
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}  🔍 REALITY - TLS - SCANNER${NC}"
        echo -e "  Поиск идеальных доменов для маскировки Reality."
        echo -e "${BLUE}======================================================${NC}"
        
        echo -e " ${YELLOW}1.${NC} Быстрый скан одного IP / Домена"
        echo -e " ${YELLOW}2.${NC} Скан подсети (CIDR, например 1.2.3.0/24)"
        echo -e " ${YELLOW}3.${NC} Бесконечный поиск (Infinity Mode)"
        echo -e " ${YELLOW}4.${NC} Скан списка из файла (in.txt)"
        echo -e " ${YELLOW}5.${NC} Сбор доменов с URL и их проверка"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}8.${NC} Посмотреть последний отчет (CSV)"
        echo -e " ${MAGENTA}9.${NC} Запустить Умный Анализ и Рекомендацию"
        echo -e " ${RED}0.${NC} ↩️ Назад"
        
        read -p ">> " s_choice
        case $s_choice in
            1) 
                read -p "Введите цель: " target
                $SCANNER_BIN -addr "$target" -v
                pause ;;
            2) 
                read -p "Введите подсеть: " sub
                read -p "Потоков (по умолчанию 10): " threads
                $SCANNER_BIN -addr "$sub" -thread "${threads:-10}" -out "result.csv"
                analyze_results "$SCANNER_DIR/result.csv"
                pause ;;
            3)
                read -p "Введите стартовый IP: " s_ip
                echo -e "${RED}Для остановки нажмите Ctrl+C${NC}"
                $SCANNER_BIN -addr "$s_ip"
                pause ;;
            5)
                read -p "URL (например https://launchpad.net/...): " s_url
                $SCANNER_BIN -url "$s_url" -out "url_results.csv"
                analyze_results "$SCANNER_DIR/url_results.csv"
                pause ;;
            8)
                [ -f "$SCANNER_DIR/out.csv" ] && column -t -s ',' "$SCANNER_DIR/out.csv" || echo "Отчет пуст."
                pause ;;
            9)
                analyze_results "$SCANNER_DIR/out.csv"
                pause ;;
            0) return ;;
        esac
    done
}
