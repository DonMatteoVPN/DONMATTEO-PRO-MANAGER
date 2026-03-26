#!/bin/bash
# Модуль Reality TLS Scanner PRO

SCANNER_DIR="/opt/RealiTLScanner"
SCANNER_BIN="$SCANNER_DIR/RealiTLScanner"
GEO_DB="$SCANNER_DIR/Country.mmdb"
INPUT_FILE="$SCANNER_DIR/in.txt"

# Функция проверки и установки сканера
check_scanner_install() {
    if [[ ! -f "$SCANNER_BIN" ]]; then
        echo -e "${YELLOW}[*] Сканер не найден. Начинаю установку и сборку...${NC}"
        apt-get update && apt-get install golang git -y >/dev/null 2>&1
        
        # Очистка старой папки если она криво создалась
        rm -rf "$SCANNER_DIR"
        git clone https://github.com/xtls/RealiTLScanner "$SCANNER_DIR"
        
        cd "$SCANNER_DIR" || return
        echo -e "${CYAN}[*] Компиляция Go-бинарника (это может занять минуту)...${NC}"
        go build -o RealiTLScanner
        
        if [[ -f "$SCANNER_BIN" ]]; then
            chmod +x "$SCANNER_BIN"
            echo -e "${GREEN}[+] Сканер успешно собран: $SCANNER_BIN${NC}"
        else
            echo -e "${RED}[!] ОШИБКА: Не удалось собрать бинарник. Проверьте установку Go (go version).${NC}"
            pause; return 1
        fi
    fi

    # Авто-загрузка GeoIP
    if [[ ! -f "$GEO_DB" ]]; then
        echo -e "${YELLOW}[*] Загрузка базы GeoIP...${NC}"
        curl -L -o "$GEO_DB" "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb" >/dev/null 2>&1
    fi
}

# Алгоритм "Умный Выбор"
analyze_results() {
    local file=$1
    [[ ! -f "$file" ]] && { echo -e "${RED}[!] Файл результатов не найден.${NC}"; return; }

    echo -e "\n${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}🤖 АНАЛИЗАТОР: РЕКОМЕНДАЦИИ ДЛЯ REALITY${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    # Ищем Let's Encrypt, Google, DigiCert (самые надежные для маскировки)
    local best=$(tail -n +2 "$file" | grep -E "Let's Encrypt|Google|DigiCert" | head -n 5)

    if [[ -z "$best" ]]; then
        echo -e "${YELLOW}Идеальных целей не найдено. Попробуйте скан другой подсети.${NC}"
    else
        echo -e "${GREEN}ТОП РЕКОМЕНДУЕМЫХ ДОМЕНОВ:${NC}"
        echo "$best" | awk -F',' '{print "📍 Домен: " $3 " | IP: " $1 " [" $5 "]"}'
    fi
}

# --- НОВАЯ ФУНКЦИЯ ДЛЯ 4 ПУНКТА ---
manage_input_file() {
    clear
    echo -e "${MAGENTA}=== УПРАВЛЕНИЕ СПИСКОМ ЦЕЛЕЙ (in.txt) ===${NC}"
    echo -e "${GRAY}Путь к файлу:${NC} $INPUT_FILE"
    echo -e "${CYAN}Инструкция:${NC} Впишите каждый IP, CIDR или Домен с новой строки.\n"
    
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo -e "${YELLOW}[!] Файл еще не создан. Создаю пустой файл...${NC}"
        touch "$INPUT_FILE"
    fi

    echo -e " ${YELLOW}1.${NC} 📝 Редактировать список (Открыть в nano)"
    echo -e " ${YELLOW}2.${NC} 🔍 Запустить скан по этому списку"
    echo -e " ${CYAN}0.${NC} ↩️  Назад"
    
    read -p ">> " in_choice
    case $in_choice in
        1) nano "$INPUT_FILE" ;;
        2) 
            if [[ ! -s "$INPUT_FILE" ]]; then
                echo -e "${RED}Ошибка: Файл пуст! Сначала добавьте цели.${NC}"; sleep 2
            else
                echo -e "${GREEN}[*] Начинаю скан списка...${NC}"
                cd "$SCANNER_DIR" && ./RealiTLScanner -in "$INPUT_FILE" -out "in_results.csv"
                analyze_results "$SCANNER_DIR/in_results.csv"
                pause
            fi ;;
        0) return ;;
    esac
}

menu_scanner() {
    check_scanner_install || return
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}  🔍 REALITY - TLS - SCANNER${NC}"
        echo -e "  Поиск идеальных доменов для маскировки Reality."
        echo -e "${BLUE}======================================================${NC}"
        
        echo -e " ${YELLOW}1.${NC} Быстрый скан одного IP / Домена"
        echo -e " ${YELLOW}2.${NC} Скан подсети (CIDR, например 1.2.3.0/24)"
        echo -e " ${YELLOW}3.${NC} Бесконечный поиск (Infinity Mode)"
        echo -e " ${YELLOW}4.${NC} 📂 Работа со списком файлов (in.txt)"
        echo -e " ${YELLOW}5.${NC} Сбор доменов с URL и их проверка"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}8.${NC} Посмотреть последний отчет (CSV)"
        echo -e " ${MAGENTA}9.${NC} Запустить Умный Анализ и Рекомендацию"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -p ">> " s_choice
        case $s_choice in
            1) 
                read -p "Введите цель: " target
                cd "$SCANNER_DIR" && ./RealiTLScanner -addr "$target" -v
                pause ;;
            2) 
                read -p "Введите подсеть: " sub
                read -p "Потоков (по умолчанию 10): " threads
                cd "$SCANNER_DIR" && ./RealiTLScanner -addr "$sub" -thread "${threads:-10}" -out "result.csv"
                analyze_results "$SCANNER_DIR/result.csv"
                pause ;;
            3)
                read -p "Введите стартовый IP: " s_ip
                echo -e "${RED}Для остановки нажмите Ctrl+C${NC}"
                cd "$SCANNER_DIR" && ./RealiTLScanner -addr "$s_ip"
                pause ;;
            4) manage_input_file ;;
            5)
                read -p "URL (например https://launchpad.net/...): " s_url
                cd "$SCANNER_DIR" && ./RealiTLScanner -url "$s_url" -out "url_results.csv"
                analyze_results "$SCANNER_DIR/url_results.csv"
                pause ;;
            8)
                [ -f "$SCANNER_DIR/out.csv" ] && column -t -s ',' "$SCANNER_DIR/out.csv" | less -S || echo "Отчет пуст."
                ;;
            9)
                # Анализируем основной файл по умолчанию
                analyze_results "$SCANNER_DIR/out.csv"
                pause ;;
            0) return ;;
        esac
    done
}
