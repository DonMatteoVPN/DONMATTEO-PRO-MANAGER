#!/bin/bash
# Модуль Reality TLS Scanner PRO (Ultimate Edition)

SCANNER_DIR="/opt/RealiTLScanner"
SCANNER_BIN="$SCANNER_DIR/RealiTLScanner"
GEO_DB="$SCANNER_DIR/Country.mmdb"
INPUT_FILE="$SCANNER_DIR/in.txt"

# --- 1. УСТАНОВКА И СБОРКА ---
check_scanner_install() {
    export PATH=/usr/local/go/bin:$PATH

    if [[ ! -f "$SCANNER_BIN" ]]; then
        echo -e "${YELLOW}[*] Сканер не найден. Начинаю установку (Go 1.22+)...${NC}"
        apt-get update >/dev/null 2>&1
        apt-get install git wget curl -y >/dev/null 2>&1
        
        wget -q https://go.dev/dl/go1.22.1.linux-amd64.tar.gz -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        export PATH=/usr/local/go/bin:$PATH

        rm -rf "$SCANNER_DIR"
        git clone https://github.com/xtls/RealiTLScanner "$SCANNER_DIR"
        
        cd "$SCANNER_DIR" || return
        echo -e "${CYAN}[*] Компиляция бинарника...${NC}"
        go build -o RealiTLScanner
        
        if [[ -f "$SCANNER_BIN" ]]; then
            chmod +x "$SCANNER_BIN"
        else
            echo -e "${RED}[!] ОШИБКА сборки.${NC}"; pause; return 1
        fi
    fi

    if [[ ! -f "$GEO_DB" ]]; then
        echo -e "${YELLOW}[*] Загрузка MaxMind GeoLite2 (Country.mmdb)...${NC}"
        curl -L -o "$GEO_DB" "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb" >/dev/null 2>&1
    fi
}

# --- 2. СПРАВОЧНИК СТРАН ---
show_geo_help() {
    echo -e "\n${CYAN}📋 СПРАВОЧНИК ПОПУЛЯРНЫХ КОДОВ СТРАН (ISO 3166-1 alpha-2):${NC}"
    echo -e "${GRAY}FI - Финляндия | NL - Нидерланды | DE - Германия | FR - Франция${NC}"
    echo -e "${GRAY}US - США       | GB - Великобрит.| RU - Россия   | PL - Польша${NC}"
    echo -e "${GRAY}SE - Швеция    | CH - Швейцария  | ES - Испания  | TR - Турция${NC}\n"
}

# --- 3. УМНЫЙ АНАЛИЗАТОР (ПОИСК SNI) ---
analyze_results() {
    local file=$1
    [[ ! -f "$file" ]] && { echo -e "${RED}[!] Файл $file не найден.${NC}"; return; }

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}🤖 АНАЛИЗАТОР: ОТБОР ИДЕАЛЬНЫХ SNI КАНДИДАТОВ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    local my_ip=$(curl -s --max-time 3 ipinfo.io/ip 2>/dev/null)
    local my_geo=$(curl -s --max-time 3 ipinfo.io/country 2>/dev/null | tr -d '[:space:]')
    
    echo -e "${CYAN}[*] Ваш текущий сервер:${NC} $my_ip ${YELLOW}($my_geo)${NC}"
    show_geo_help
    
    echo -e "${GRAY}Для лучшей маскировки укажите код страны, чтобы отфильтровать мусор.${NC}"
    read -p ">> Страна (Enter = Использовать $my_geo, 'n' = Без фильтра): " user_geo
    
    local target_geo=""
    if [[ -z "$user_geo" ]]; then target_geo="$my_geo"
    elif [[ "$user_geo" != "n" && "$user_geo" != "N" ]]; then target_geo=$(echo "$user_geo" | tr '[:lower:]' '[:upper:]')
    fi

    echo -e "\n${CYAN}Фильтрация файла: $(basename "$file")...${NC}"
    
    # Фильтруем доверенных издателей через awk, как в инструкции
    local filtered=$(awk -F, 'NR>1 && $4 ~ /Let'\''s Encrypt|Google|DigiCert|Cloudflare|Sectigo|GlobalSign/' "$file")

    # Жесткий фильтр по ГЕО
    if [[ -n "$target_geo" ]]; then
        filtered=$(echo "$filtered" | awk -F, -v geo="$target_geo" '$5 == geo')
        [[ -n "$filtered" ]] && echo -e "${GREEN}[+] Найдены домены в локации: $target_geo${NC}" || echo -e "${RED}[!] В локации $target_geo ничего не найдено.${NC}"
    fi

    local best=$(echo "$filtered" | head -n 10)

    if [[ -z "$best" ]]; then
        echo -e "${YELLOW}Подходящих целей (TLS 1.3 + HTTP/2 + Trusted Issuer) не найдено.${NC}"
    else
        echo -e "\n${GREEN}🏆 ТОП-10 ИДЕАЛЬНЫХ SNI КАНДИДАТОВ:${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo "$best" | awk -F',' '{print "📍 \033[1;32m" $3 "\033[0m\n   └─ IP: " $1 " | ГЕО: \033[1;33m" $5 "\033[0m | Издатель: " $4 "\n"}'
    fi
    pause
}

# --- 4. ИНТЕРАКТИВНЫЙ ЗАПУСК С ОПЦИЯМИ ---
run_scanner() {
    local mode=$1
    local target=$2
    
    # Автоопределение для подсказки
    local my_ip=$(curl -s --max-time 3 ipinfo.io/ip 2>/dev/null)
    
    if [[ -z "$target" ]]; then
        echo -e "\n${CYAN}[*] Ваш текущий IP-адрес: ${YELLOW}$my_ip${NC}"
        read -p ">> Введите цель (Enter = сканировать ВАШ IP): " input_target
        target=${input_target:-$my_ip}
    fi

    # Хак для отключения Infinity Mode для одиночного IP
    if [[ "$mode" == "addr" && "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        target="${target}/32"
    fi

    # Безопасное имя файла
    local safe_target=$(echo "$target" | sed 's/[^a-zA-Z0-9]/_/g' | cut -c 1-20)
    local out_file="scan_${mode}_${safe_target}_$(date +%s).csv"

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} ⚙️  ТОНКАЯ НАСТРОЙКА СКАНИРОВАНИЯ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${CYAN}Цель:${NC} $target (Режим: -$mode)\n"

    read -p ">> Порт (Enter = 443): " s_port; s_port=${s_port:-443}
    read -p ">> Потоков (Enter = 10, макс 50): " s_thread; s_thread=${s_thread:-10}
    read -p ">> Таймаут в сек (Enter = 5, для дохлых сетей 10): " s_timeout; s_timeout=${s_timeout:-5}
    read -p ">> Включить сканирование IPv6? (-46) (y/N): " s_ipv6
    read -p ">> Подробный вывод всех логов (-v)? (y/N): " s_verb

    local extra_args=""
    [[ "$s_ipv6" == "y" || "$s_ipv6" == "Y" ]] && extra_args+=" -46"
    [[ "$s_verb" == "y" || "$s_verb" == "Y" ]] && extra_args+=" -v"

    echo -e "\n${GREEN}[*] Запуск сканирования...${NC}"
    echo -e "${YELLOW}(Нажмите Ctrl+C, когда захотите прервать скан)${NC}\n"
    
    cd "$SCANNER_DIR" || return
    export PATH=/usr/local/go/bin:$PATH
    
    ./RealiTLScanner -"$mode" "$target" -port "$s_port" -thread "$s_thread" -timeout "$s_timeout" -out "$out_file" $extra_args

    echo -e "\n${GREEN}[+] Сканирование завершено!${NC}"
    echo -e "Результат сохранен в файл: ${CYAN}$out_file${NC}"
    analyze_results "$SCANNER_DIR/$out_file"
}

# --- 5. МЕНЕДЖЕР ОТЧЕТОВ ---
manage_reports() {
    while true; do
        clear
        echo -e "${MAGENTA}=== 📂 МЕНЕДЖЕР СОХРАНЕННЫХ ОТЧЕТОВ ===${NC}"
        
        mapfile -t CSV_FILES < <(ls -1t "$SCANNER_DIR"/*.csv 2>/dev/null)
        
        if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
            echo -e "${YELLOW}Отчетов пока нет.${NC}"; pause; return
        fi

        for i in "${!CSV_FILES[@]}"; do
            local f_size=$(du -sh "${CSV_FILES[$i]}" | awk '{print $1}')
            local f_name=$(basename "${CSV_FILES[$i]}")
            echo -e " ${YELLOW}$((i+1)).${NC} ${CYAN}$f_name${NC} ${GRAY}($f_size)${NC}"
        done

        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " 👉 ${YELLOW}НОМЕР${NC} - Посмотреть сырую таблицу CSV."
        echo -e " 👉 ${GREEN}aНОМЕР${NC} (напр. ${BOLD}a1${NC}) - Запустить Умный Анализ SNI."
        echo -e " 👉 ${RED}dНОМЕР${NC} (напр. ${BOLD}d1${NC}) - Удалить отчет."
        echo -e " ${CYAN}0.${NC} Назад"
        
        read -p ">> " r_choice

        if [[ "$r_choice" == "0" ]]; then return; fi
        
        if [[ "$r_choice" =~ ^d([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            [[ -n "${CSV_FILES[$idx]}" ]] && rm -f "${CSV_FILES[$idx]}" && echo -e "${GREEN}Файл удален!${NC}" && sleep 1
        elif [[ "$r_choice" =~ ^a([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            [[ -n "${CSV_FILES[$idx]}" ]] && analyze_results "${CSV_FILES[$idx]}"
        elif [[ "$r_choice" =~ ^[0-9]+$ ]]; then
            local idx=$((r_choice-1))
            [[ -n "${CSV_FILES[$idx]}" ]] && column -t -s ',' "${CSV_FILES[$idx]}" | less -S
        else
            echo -e "${RED}Неверный ввод.${NC}"; sleep 1
        fi
    done
}

manage_input_file() {
    clear
    echo -e "${MAGENTA}=== УПРАВЛЕНИЕ СПИСКОМ ЦЕЛЕЙ (in.txt) ===${NC}"
    if [[ ! -f "$INPUT_FILE" ]]; then touch "$INPUT_FILE"; fi
    echo -e " ${YELLOW}1.${NC} 📝 Редактировать список (nano)"
    echo -e " ${YELLOW}2.${NC} 🔍 Запустить скан по списку"
    echo -e " ${CYAN}0.${NC} ↩️  Назад"
    read -p ">> " in_choice
    case $in_choice in
        1) nano "$INPUT_FILE" ;;
        2) [[ ! -s "$INPUT_FILE" ]] && echo "Файл пуст!" || run_scanner "in" "$INPUT_FILE" ;;
        0) return ;;
    esac
}

menu_scanner() {
    check_scanner_install || return
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}  🔍 REALITY - TLS - SCANNER${NC}"
        echo -e "  Комплексный инструмент для разведки и подбора SNI."
        echo -e "${BLUE}======================================================${NC}"

        echo -e " ${YELLOW}1.${NC} Строгий скан одного IP / Домена   ${GRAY}(-addr)${NC}"
        echo -e " ${YELLOW}2.${NC} Скан подсети (CIDR, напр. /24)    ${GRAY}(-addr)${NC}"
        echo -e " ${YELLOW}3.${NC} Бесконечный поиск (Infinity Mode) ${GRAY}(-addr)${NC}"
        echo -e " ${YELLOW}4.${NC} 📂 Скан по списку из файла        ${GRAY}(-in)${NC}"
        echo -e " ${YELLOW}5.${NC} Сбор и скан доменов по URL        ${GRAY}(-url)${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}8.${NC} 📂 Менеджер Отчетов (Анализ / Просмотр CSV)"
        echo -e " ${RED}0.${NC} ↩️ Назад"
        
        read -p ">> " s_choice
        case $s_choice in
            1) run_scanner "addr" "" ;;
            2) 
                read -p "Введите подсеть (CIDR, например 104.21.0.0/24): " sub
                [[ -n "$sub" ]] && run_scanner "addr" "$sub" ;;
            3)
                read -p "Введите стартовый IP для Infinity Mode: " s_ip
                [[ -n "$s_ip" ]] && run_scanner "addr" "$s_ip" ;;
            4) manage_input_file ;;
            5)
                echo -e "${GRAY}Пример: https://launchpad.net/ubuntu/+archivemirrors${NC}"
                read -p "URL со списком: " s_url
                [[ -n "$s_url" ]] && run_scanner "url" "$s_url" ;;
            8) manage_reports ;;
            0) return ;;
        esac
    done
}
