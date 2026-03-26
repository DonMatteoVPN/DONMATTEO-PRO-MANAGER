#!/bin/bash
# Модуль Reality TLS Scanner PRO

SCANNER_DIR="/opt/RealiTLScanner"
SCANNER_BIN="$SCANNER_DIR/RealiTLScanner"
GEO_DB="$SCANNER_DIR/Country.mmdb"
INPUT_FILE="$SCANNER_DIR/in.txt"

# --- 1. УСТАНОВКА И СБОРКА ---
check_scanner_install() {
    export PATH=/usr/local/go/bin:$PATH

    if [[ ! -f "$SCANNER_BIN" ]]; then
        echo -e "${YELLOW}[*] Сканер не найден. Начинаю установку и сборку...${NC}"
        apt-get update >/dev/null 2>&1
        apt-get install git wget curl -y >/dev/null 2>&1
        
        # Устанавливаем актуальный Go (1.22+), так как Debian 12 дает старый 1.19
        echo -e "${CYAN}[*] Загрузка и установка актуального Go (1.22+)...${NC}"
        wget -q https://go.dev/dl/go1.22.1.linux-amd64.tar.gz -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        export PATH=/usr/local/go/bin:$PATH

        # Очистка старой папки и клонирование
        rm -rf "$SCANNER_DIR"
        git clone https://github.com/xtls/RealiTLScanner "$SCANNER_DIR"
        
        cd "$SCANNER_DIR" || return
        echo -e "${CYAN}[*] Компиляция Go-бинарника (это может занять минуту)...${NC}"
        go build -o RealiTLScanner
        
        if [[ -f "$SCANNER_BIN" ]]; then
            chmod +x "$SCANNER_BIN"
            echo -e "${GREEN}[+] Сканер успешно собран: $SCANNER_BIN${NC}"
        else
            echo -e "${RED}[!] ОШИБКА: Не удалось собрать бинарник.${NC}"
            pause; return 1
        fi
    fi

    # Авто-загрузка GeoIP (Country.mmdb должен быть рядом с бинарником)
    if [[ ! -f "$GEO_DB" ]]; then
        echo -e "${YELLOW}[*] Загрузка базы GeoIP (Country.mmdb)...${NC}"
        curl -L -o "$GEO_DB" "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb" >/dev/null 2>&1
    fi
}

# --- 2. УМНЫЙ АНАЛИЗАТОР ---
analyze_results() {
    local file=$1
    [[ ! -f "$file" ]] && { echo -e "${RED}[!] Файл результатов не найден или пуст.${NC}"; return; }

    echo -e "\n${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}🤖 АНАЛИЗАТОР: РЕКОМЕНДАЦИИ ПО ВЫБОРУ ЦЕЛИ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    echo -e "${GRAY}Для максимальной маскировки желательно, чтобы домен находился${NC}"
    echo -e "${GRAY}в той же стране, что и ваш сервер (меньше подозрений у DPI).${NC}"
    read -p "Введите страну ВАШЕГО сервера (например NL, DE, US, RU) [Enter = пропустить]: " my_geo
    my_geo=$(echo "$my_geo" | tr '[:lower:]' '[:upper:]')

    echo -e "\n${CYAN}Анализируем результаты...${NC}"
    # Отсеиваем только известные и доверенные сертификаты (убираем мусор)
    local filtered=$(tail -n +2 "$file" | grep -iE "Let's Encrypt|Google|DigiCert|Cloudflare|Sectigo|ZeroSSL|GlobalSign")

    # Фильтруем по ГЕО, если пользователь ввел код страны
    if [[ -n "$my_geo" ]]; then
        echo -e "${GRAY}[*] Ищем домены в стране: $my_geo...${NC}"
        local geo_matched=$(echo "$filtered" | grep ",$my_geo$")
        if [[ -n "$geo_matched" ]]; then
            filtered="$geo_matched"
            echo -e "${GREEN}[+] Найдены совпадения по вашей локации!${NC}"
        else
            echo -e "${YELLOW}[!] Идеальных совпадений по ГЕО ($my_geo) не найдено. Показываю лучшие из других стран.${NC}"
        fi
    fi

    local best=$(echo "$filtered" | head -n 7)

    if [[ -z "$best" ]]; then
        echo -e "${RED}Подходящих целей (TLS 1.3 + HTTP/2 + Хороший Issuer) не найдено.${NC}"
    else
        echo -e "\n${GREEN}🏆 ТОП РЕКОМЕНДУЕМЫХ ДОМЕНОВ:${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo "$best" | awk -F',' '{print "📍 Домен: \033[1;32m" $3 "\033[0m\n   └─ IP: " $1 " | ГЕО: \033[1;33m" $5 "\033[0m | Издатель: " $4 "\n"}'
    fi
    echo -e "${MAGENTA}======================================================${NC}"
    pause
}

# --- 3. ИНТЕРАКТИВНЫЙ ЗАПУСК ---
run_scanner() {
    local mode=$1
    local target=$2

    echo -e "\n${CYAN}--- Тонкая настройка сканирования ---${NC}"
    read -p "Порт (Enter = 443): " s_port
    s_port=${s_port:-443}

    read -p "Потоков (Enter = 10): " s_thread
    s_thread=${s_thread:-10}

    read -p "Таймаут проверки в сек (Enter = 5): " s_timeout
    s_timeout=${s_timeout:-5}

    local out_file="result_$(date +%s).csv"

    echo -e "\n${GREEN}[*] Запуск сканирования...${NC}"
    echo -e "${YELLOW}(Нажмите Ctrl+C, если хотите прервать скан досрочно)${NC}\n"
    
    cd "$SCANNER_DIR" || return
    export PATH=/usr/local/go/bin:$PATH
    
    ./RealiTLScanner -"$mode" "$target" -port "$s_port" -thread "$s_thread" -timeout "$s_timeout" -out "$out_file"

    echo -e "\n${GREEN}[+] Сканирование завершено!${NC}"
    analyze_results "$SCANNER_DIR/$out_file"
}

# --- 4. РАБОТА С ФАЙЛОМ IN.TXT ---
manage_input_file() {
    clear
    echo -e "${MAGENTA}=== УПРАВЛЕНИЕ СПИСКОМ ЦЕЛЕЙ (in.txt) ===${NC}"
    echo -e "${GRAY}Путь к файлу:${NC} $INPUT_FILE"
    echo -e "${CYAN}Инструкция:${NC} Впишите каждый IP, CIDR или Домен с новой строки.\n"
    
    if [[ ! -f "$INPUT_FILE" ]]; then
        touch "$INPUT_FILE"
        echo -e "${YELLOW}[!] Создан пустой файл.${NC}"
    fi

    echo -e " ${YELLOW}1.${NC} 📝 Редактировать список (Откроется в nano)"
    echo -e " ${YELLOW}2.${NC} 🔍 Запустить скан по этому списку"
    echo -e " ${CYAN}0.${NC} ↩️  Назад"
    
    read -p ">> " in_choice
    case $in_choice in
        1) nano "$INPUT_FILE" ;;
        2) 
            if [[ ! -s "$INPUT_FILE" ]]; then
                echo -e "${RED}Ошибка: Файл пуст! Сначала добавьте цели.${NC}"; sleep 2
            else
                run_scanner "in" "$INPUT_FILE"
            fi ;;
        0) return ;;
    esac
}

# --- ГЛАВНОЕ МЕНЮ МОДУЛЯ ---
menu_scanner() {
    check_scanner_install || return
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}  🔍 REALITY - TLS - SCANNER${NC}"
        echo -e "  Умный поиск идеальных доменов для маскировки."
        echo -e "${BLUE}======================================================${NC}"
        
        echo -e " ${YELLOW}1.${NC} Быстрый скан одного IP / Домена"
        echo -e " ${YELLOW}2.${NC} Скан подсети (CIDR, например 104.21.0.0/24)"
        echo -e " ${YELLOW}3.${NC} Бесконечный поиск (Infinity Mode от IP)"
        echo -e " ${YELLOW}4.${NC} 📂 Работа со списком (файл in.txt)"
        echo -e " ${YELLOW}5.${NC} Сбор и скан доменов с URL-страницы"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}8.${NC} Посмотреть все файлы отчетов в папке"
        echo -e " ${RED}0.${NC} ↩️ Назад"
        
        read -p ">> " s_choice
        case $s_choice in
            1) 
                read -p "Введите цель (IP или домен): " target
                [[ -n "$target" ]] && run_scanner "addr" "$target" ;;
            2) 
                read -p "Введите подсеть (CIDR): " sub
                [[ -n "$sub" ]] && run_scanner "addr" "$sub" ;;
            3)
                read -p "Введите стартовый IP: " s_ip
                [[ -n "$s_ip" ]] && run_scanner "addr" "$s_ip" ;;
            4) manage_input_file ;;
            5)
                read -p "URL (например https://launchpad.net/ubuntu/+archivemirrors): " s_url
                [[ -n "$s_url" ]] && run_scanner "url" "$s_url" ;;
            8)
                clear
                echo -e "${MAGENTA}=== СОХРАНЕННЫЕ ОТЧЕТЫ ===${NC}"
                ls -lh "$SCANNER_DIR"/*.csv 2>/dev/null | awk '{print $5, $9}'
                echo ""
                read -p "Введите имя файла для просмотра (или Enter для выхода): " csv_file
                if [[ -n "$csv_file" && -f "$csv_file" ]]; then
                    column -t -s ',' "$csv_file" | less -S
                fi ;;
            0) return ;;
        esac
    done
}
