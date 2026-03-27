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
        
        if [[ -f "$SCANNER_BIN" ]]; then chmod +x "$SCANNER_BIN"; else echo -e "${RED}[!] ОШИБКА сборки.${NC}"; pause; return 1; fi
    fi

    if [[ ! -f "$GEO_DB" ]]; then
        echo -e "${YELLOW}[*] Загрузка MaxMind GeoLite2 (Country.mmdb)...${NC}"
        curl -L -o "$GEO_DB" "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb" >/dev/null 2>&1
    fi
}

show_geo_help() {
    echo -e "\n${CYAN}📋 СПРАВОЧНИК ПОПУЛЯРНЫХ КОДОВ СТРАН (ISO 3166-1 alpha-2):${NC}"
    echo -e "${GRAY}FI - Финляндия | NL - Нидерланды | DE - Германия | FR - Франция${NC}"
    echo -e "${GRAY}US - США       | GB - Великобрит.| RU - Россия   | PL - Польша${NC}"
    echo -e "${GRAY}SE - Швеция    | CH - Швейцария  | ES - Испания  | TR - Турция${NC}\n"
}

# --- 2. УМНЫЙ АНАЛИЗАТОР (СОРТИРОВКА И ВЕСА СЕРТИФИКАТОВ) ---
analyze_results() {
    local file=$1
    [[ ! -f "$file" ]] && { echo -e "${RED}[!] Файл $file не найден.${NC}"; return; }

    local total_lines=$(wc -l < "$file" 2>/dev/null)
    if [[ "$total_lines" -le 1 ]]; then
        echo -e "\n${RED}[!] В отчете пусто. Сканер ничего не нашел.${NC}"
        pause; return
    fi

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}🤖 АНАЛИЗАТОР: ОТБОР ИДЕАЛЬНЫХ SNI КАНДИДАТОВ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${CYAN}💡 На чем основывается наш ТОП?${NC}"
    echo -e "${GRAY}1. Корпоративные сертификаты (Google, Apple, DigiCert) - Высший приоритет.${NC}"
    echo -e "${GRAY}   Они сливаются с трафиком крупных IT-компаний и банков.${NC}"
    echo -e "${GRAY}2. Cloudflare / GlobalSign / Sectigo - Средний приоритет.${NC}"
    echo -e "${GRAY}3. Let's Encrypt / ZeroSSL - Низший приоритет (слишком часто банятся).${NC}\n"
    
    local my_ip=$(curl -s --max-time 3 ipinfo.io/ip 2>/dev/null)
    local my_geo=$(curl -s --max-time 3 ipinfo.io/country 2>/dev/null | tr -d '[:space:]')
    
    echo -e "${CYAN}[*] Ваш текущий сервер:${NC} $my_ip ${YELLOW}($my_geo)${NC}"
    show_geo_help
    
    read -p ">> Фильтр по Стране (Enter = Искать в $my_geo, 'n' = Искать везде): " user_geo
    
    local target_geo=""
    if [[ -z "$user_geo" ]]; then target_geo="$my_geo"
    elif [[ "$user_geo" != "n" && "$user_geo" != "N" ]]; then target_geo=$(echo "$user_geo" | tr '[:lower:]' '[:upper:]')
    fi

    echo -e "\n${CYAN}Анализ и сортировка файла: $(basename "$file")...${NC}"
    
    # МАГИЯ AWK: Читаем файл, назначаем веса сертификатам и сортируем
    # Вес 1 (Лучший), Вес 4 (Худший)
    local sorted_data=$(awk -F, -v target_geo="$target_geo" '
    NR>1 {
        issuer = tolower($4);
        weight = 5;
        if (issuer ~ /google|apple|microsoft/) weight = 1;
        else if (issuer ~ /digicert|globalsign|sectigo/) weight = 2;
        else if (issuer ~ /cloudflare/) weight = 3;
        else if (issuer ~ /let'\''s encrypt|zerossl/) weight = 4;
        
        # Если задан фильтр гео, и он не совпадает - пропускаем
        if (target_geo != "" && $5 != target_geo) next;
        
        # Печатаем вес в начало строки для сортировки
        if (weight < 5) {
            port = $6 ? $6 : "443";
            print weight "|" $3 "|" $1 "|" port "|" $5 "|" $4;
        }
    }' "$file" | sort -t'|' -k1,1n | uniq)

    local best=$(echo "$sorted_data" | head -n 15)

    if [[ -z "$best" ]]; then
        echo -e "${YELLOW}Идеальных целей (с нужным ГЕО и надежным сертификатом) не найдено.${NC}"
        echo -e "${GRAY}Все необработанные данные сохранены в файле (Пункт 8).${NC}"
    else
        echo -e "\n${GREEN}🏆 ТОП-15 ИДЕАЛЬНЫХ SNI КАНДИДАТОВ:${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        
        echo "$best" | while IFS='|' read -r weight domain ip port geo issuer; do
            # Подкрашиваем вывод в зависимости от веса (качества сертификата)
            if [[ "$weight" == "1" ]]; then
                echo -e "💎 \033[1;36m$domain\033[0m" # Голубой для элиты
            elif [[ "$weight" == "2" || "$weight" == "3" ]]; then
                echo -e "📍 \033[1;32m$domain\033[0m" # Зеленый для хороших
            else
                echo -e "🔸 \033[0;32m$domain\033[0m" # Темно-зеленый для Let's Encrypt
            fi
            echo -e "   └─ IP: $ip (Порт: \033[1;36m$port\033[0m) | ГЕО: \033[1;33m$geo\033[0m | Издатель: $issuer\n"
        done
    fi
    pause
}

# --- 3. ИНТЕРАКТИВНЫЙ ЗАПУСК С ЛИМИТАМИ И ТЕГАМИ ---
run_scanner() {
    local mode=$1
    local target=$2
    
    local my_ip=$(curl -s --max-time 3 ipinfo.io/ip 2>/dev/null)
    local my_subnet=$(echo "$my_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
    
    if [[ -z "$target" ]]; then
        echo -e "\n${CYAN}[*] Ваш IP-адрес: ${YELLOW}$my_ip${NC}"
        echo -e "${GRAY}💡 Чтобы найти SNI, сканируйте подсеть ваших соседей: ${GREEN}$my_subnet${NC}"
        read -p ">> Введите цель (Enter = сканировать соседей $my_subnet): " input_target
        target=${input_target:-$my_subnet}
    fi

    if [[ "$mode" == "addr" && "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then target="${target}/32"; fi

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} ⚙️  ТОНКАЯ НАСТРОЙКА СКАНИРОВАНИЯ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${CYAN}Цель:${NC} $target (Режим: -$mode)\n"

    read -p ">> Порт(ы) через запятую (Enter = 443): " s_port
    s_port=${s_port:-443}
    IFS=',' read -ra PORT_ARRAY <<< "${s_port// /}"

    read -p ">> Потоков (Enter = 10, макс 50): " s_thread; s_thread=${s_thread:-10}
    read -p ">> Таймаут в сек (Enter = 5): " s_timeout; s_timeout=${s_timeout:-5}
    
    echo -e "\n${YELLOW}💡 Лимит поиска${NC}"
    echo -e "${GRAY}Чтобы не сканировать бесконечно, скрипт может остановиться, когда найдет нужное${NC}"
    echo -e "${GRAY}количество рабочих доменов (например, 50).${NC}"
    read -p ">> Сколько SNI найти? (Enter = 50, 0 = Без лимита): " s_limit
    s_limit=${s_limit:-50}

    echo -e "\n${YELLOW}💡 Имя файла (Тег)${NC}"
    read -p ">> Добавить метку к имени файла (напр. Hetzner, FI) [Enter = пропустить]: " s_tag
    
    local safe_target=$(echo "$target" | sed 's/[^a-zA-Z0-9]/_/g' | cut -c 1-15)
    local safe_tag=$(echo "$s_tag" | sed 's/[^a-zA-Z0-9]/_/g')
    local out_file=""
    if [[ -n "$safe_tag" ]]; then out_file="scan_${safe_tag}_${safe_target}_$(date +%s).csv"
    else out_file="scan_${safe_target}_$(date +%s).csv"; fi

    echo -e "\n${GREEN}[*] Запуск сканирования...${NC}"
    echo -e "${YELLOW}(Нажмите Ctrl+C, когда захотите прервать скан)${NC}\n"
    
    cd "$SCANNER_DIR" || return
    export PATH=/usr/local/go/bin:$PATH
    
    echo "IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE,PORT" > "$SCANNER_DIR/$out_file"

    for current_port in "${PORT_ARRAY[@]}"; do
        echo -e "${MAGENTA}>>> СКАНИРОВАНИЕ ПОРТА: ${current_port} <<<${NC}"
        local tmp_csv="tmp_scan_${current_port}.csv"
        
        # Запускаем сканер в ФОНОВОМ режиме
        ./RealiTLScanner -"$mode" "$target" -port "$current_port" -thread "$s_thread" -timeout "$s_timeout" -out "$tmp_csv" >/dev/null 2>&1 &
        local SCAN_PID=$!
        
        # Перехват Ctrl+C
        trap 'kill $SCAN_PID 2>/dev/null; echo -e "\n${YELLOW}Остановлено пользователем.${NC}"; break' INT

        # Процесс-наблюдатель для лимита
        if [[ "$s_limit" -gt 0 ]]; then
            while kill -0 $SCAN_PID 2>/dev/null; do
                local current_count=$(wc -l < "$tmp_csv" 2>/dev/null || echo 0)
                if [[ "$current_count" -ge "$s_limit" ]]; then
                    echo -e "${GREEN}[+] Лимит ($s_limit) достигнут! Останавливаем сканер...${NC}"
                    kill $SCAN_PID 2>/dev/null
                    break
                fi
                sleep 2
            done
        else
            wait $SCAN_PID
        fi
        trap - INT # Сброс перехвата Ctrl+C

        # Склеиваем временный файл с основным, добавляя порт
        if [[ -f "$tmp_csv" ]]; then
            tail -n +2 "$tmp_csv" | awk -v p="$current_port" -F',' '{print $0","p}' >> "$SCANNER_DIR/$out_file"
            rm -f "$tmp_csv"
        fi
    done

    echo -e "\n${GREEN}[+] Сканирование завершено! Все сырые данные сохранены.${NC}"
    echo -e "Файл: ${CYAN}$out_file${NC}"
    analyze_results "$SCANNER_DIR/$out_file"
}

# --- 4. МЕНЕДЖЕР ОТЧЕТОВ ---
manage_reports() {
    while true; do
        clear
        echo -e "${MAGENTA}=== 📂 МЕНЕДЖЕР СОХРАНЕННЫХ ОТЧЕТОВ ===${NC}"
        echo -e "${GRAY}Файлы содержат АБСОЛЮТНО ВСЕ результаты сканирования.${NC}"
        echo -e "${GRAY}Вы можете прогонять Умный Анализ (a1, a2) по ним сколько угодно раз.${NC}\n"
        
        mapfile -t CSV_FILES < <(ls -1t "$SCANNER_DIR"/*.csv 2>/dev/null)
        
        if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
            echo -e "${YELLOW}Отчетов пока нет. Запустите сканирование.${NC}"; pause; return
        fi

        for i in "${!CSV_FILES[@]}"; do
            local f_size=$(du -sh "${CSV_FILES[$i]}" | awk '{print $1}')
            local f_name=$(basename "${CSV_FILES[$i]}")
            echo -e " ${YELLOW}$((i+1)).${NC} ${CYAN}$f_name${NC} ${GRAY}($f_size)${NC}"
        done

        echo -e "\n${BLUE}------------------------------------------------------${NC}"
        echo -e " 👉 ${YELLOW}НОМЕР${NC} - Посмотреть сырую таблицу CSV."
        echo -e " 👉 ${GREEN}aНОМЕР${NC} (напр. ${BOLD}a1${NC}) - Запустить Умный Анализ SNI (Фильтрация)."
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
            if [[ -n "${CSV_FILES[$idx]}" ]]; then
                echo -e "${YELLOW}💡 Подсказка: Для выхода из просмотра таблицы нажмите клавишу 'q' на клавиатуре.${NC}"
                sleep 2
                column -t -s ',' "${CSV_FILES[$idx]}" | less -S
            fi
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
