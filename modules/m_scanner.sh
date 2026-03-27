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

# --- 2. РЕЖИМ "РЕНТГЕН" ДЛЯ ОДНОЙ ЦЕЛИ (ПУНКТ 1) ---
run_single_scan() {
    local target=$1
    if [[ -z "$target" ]]; then
        read -p ">> Введите цель (IP или Домен): " target
        [[ -z "$target" ]] && return
    fi

    if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then target="${target}/32"; fi

    read -p ">> Порт(ы) через запятую (Enter = 443): " s_port
    s_port=${s_port:-443}
    IFS=',' read -ra PORT_ARRAY <<< "${s_port// /}"

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 📄 ПОЛНОЕ ДОСЬЕ НА ЦЕЛЬ: ${target%/*}${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    cd "$SCANNER_DIR" || return
    export PATH=/usr/local/go/bin:$PATH
    
    for current_port in "${PORT_ARRAY[@]}"; do
        echo -e "\n${CYAN}>>> СКАНИРОВАНИЕ ПОРТА: ${current_port} <<<${NC}"
        
        ./RealiTLScanner -addr "$target" -port "$current_port" -timeout 5 -v 2>&1 | while read -r line; do
            if [[ "$line" == *"Connected to target"* ]]; then
                local feas=$(echo "$line" | grep -oP 'feasible=\K[^ ]+')
                local ip=$(echo "$line" | grep -oP 'ip=\K[^ ]+')
                local tls=$(echo "$line" | grep -oP 'tls="?\K[^"]+' | tr -d '"')
                local alpn=$(echo "$line" | grep -oP 'alpn="?\K[^" ]+' | tr -d '"')
                local dom=$(echo "$line" | grep -oP 'cert-domain="?\K[^"]+' | tr -d '"')
                local iss=$(echo "$line" | grep -oP 'cert-issuer="?\K[^"]+' | tr -d '"')
                local geo=$(echo "$line" | grep -oP 'geo=\K[^ ]+')

                echo -e "\n 🌐 ${CYAN}IP-адрес:${NC}  ${ip:-Неизвестно}"
                if [[ "$feas" == "true" ]]; then
                    echo -e " ✅ ${CYAN}Статус:${NC}    \033[1;32mПОДХОДИТ ДЛЯ REALITY\033[0m"
                else
                    echo -e " ❌ ${CYAN}Статус:${NC}    \033[1;31mНЕ ПОДХОДИТ (См. параметры ниже)\033[0m"
                fi
                echo -e " 🔒 ${CYAN}TLS Версия:${NC} ${tls:-Отсутствует}"
                echo -e " ⚡ ${CYAN}ALPN:${NC}       ${alpn:-Отсутствует}"
                echo -e " 📍 ${CYAN}Домен (SNI):${NC} ${dom:-Отсутствует}"
                echo -e " 🏢 ${CYAN}Издатель:${NC}  ${iss:-Отсутствует}"
                echo -e " 🌍 ${CYAN}Локация:${NC}   ${geo:-N/A}"
                echo -e "${GRAY}------------------------------------------------------${NC}"
            
            elif [[ "$line" == *"TLS handshake failed"* ]]; then
                local tip=$(echo "$line" | grep -oP 'target=\K[^ ]+')
                echo -e " ❌ ${RED}[$tip] ОШИБКА: TLS Handshake не удался (Не HTTPS сервер или плохой SSL)${NC}"
            elif [[ "$line" == *"Cannot dial"* ]]; then
                local tip=$(echo "$line" | grep -oP 'target=\K[^ ]+')
                echo -e " ❌ ${RED}[$tip] ОШИБКА: Сервер не отвечает (Порт закрыт или таймаут)${NC}"
            elif [[ "$line" == *"Failed to get IP"* || "$line" == *"no IP found"* ]]; then
                echo -e " ❌ ${RED}ОШИБКА: Домен не резолвится (Нет IP-адреса)${NC}"
            fi
        done
    done
    
    echo -e "\n${BLUE}======================================================${NC}"
    pause
}

# --- 3. УМНЫЙ АНАЛИЗАТОР (ДЛЯ МАССОВЫХ СКАНОВ) ---
analyze_results() {
    local file=$1
    [[ ! -f "$file" ]] && { echo -e "${RED}[!] Файл $file не найден.${NC}"; return; }

    local total_lines=$(wc -l < "$file" 2>/dev/null)
    if [[ "$total_lines" -le 1 ]]; then
        echo -e "\n${RED}[!] В отчете пусто. Сканер ничего не нашел.${NC}"
        return
    fi

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}🤖 АНАЛИЗАТОР: ОТБОР ИДЕАЛЬНЫХ SNI КАНДИДАТОВ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${CYAN}💡 На чем основывается наш ТОП?${NC}"
    echo -e "${GRAY}1. Корпоративные сертификаты (Google, Apple, DigiCert) - Высший приоритет.${NC}"
    echo -e "${GRAY}2. Cloudflare / GlobalSign / Sectigo - Средний приоритет.${NC}"
    echo -e "${GRAY}3. Let's Encrypt / ZeroSSL - Низший приоритет.${NC}\n"
    
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
    
    local sorted_data=$(awk -F, -v target_geo="$target_geo" '
    NR>1 {
        issuer = tolower($4);
        weight = 5;
        if (issuer ~ /google|apple|microsoft/) weight = 1;
        else if (issuer ~ /digicert|globalsign|sectigo/) weight = 2;
        else if (issuer ~ /cloudflare/) weight = 3;
        else if (issuer ~ /let'\''s encrypt|zerossl/) weight = 4;
        
        if (target_geo != "" && $5 != target_geo) next;
        
        if (weight < 5) {
            port = $6 ? $6 : "443";
            print weight "|" $3 "|" $1 "|" port "|" $5 "|" $4;
        }
    }' "$file" | sort -t'|' -k1,1n | uniq)

    local best=$(echo "$sorted_data" | head -n 15)

    if [[ -z "$best" ]]; then
        echo -e "${YELLOW}Идеальных целей (с нужным ГЕО и надежным сертификатом) не найдено.${NC}"
    else
        echo -e "\n${GREEN}🏆 ТОП-15 ИДЕАЛЬНЫХ SNI КАНДИДАТОВ:${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        
        echo "$best" | while IFS='|' read -r weight domain ip port geo issuer; do
            if [[ "$weight" == "1" ]]; then echo -e "💎 \033[1;36m$domain\033[0m"
            elif [[ "$weight" == "2" || "$weight" == "3" ]]; then echo -e "📍 \033[1;32m$domain\033[0m"
            else echo -e "🔸 \033[0;32m$domain\033[0m"
            fi
            echo -e "   └─ IP: $ip (Порт: \033[1;36m$port\033[0m) | ГЕО: \033[1;33m$geo\033[0m | Издатель: $issuer\n"
        done
    fi
}

# --- 4. МАССОВЫЙ СКАНЕР С ЛИМИТАМИ И СОХРАНЕНИЕМ (ДЛЯ ПУНКТОВ 2-5) ---
run_scanner() {
    local mode=$1
    local target=$2
    
    local safe_target=$(echo "$target" | sed 's/[^a-zA-Z0-9]/_/g' | cut -c 1-15)
    local out_file="scan_${mode}_${safe_target}_$(date +%s).csv"

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
    read -p ">> Сколько SNI найти? (Enter = 0, искать бесконечно / до конца списка): " s_limit
    s_limit=${s_limit:-0}

    echo -e "\n${YELLOW}💡 Имя файла (Тег)${NC}"
    read -p ">> Добавить метку к имени файла (напр. Hetzner, FI) [Enter = пропустить]: " s_tag
    
    local safe_tag=$(echo "$s_tag" | sed 's/[^a-zA-Z0-9]/_/g')
    if [[ -n "$safe_tag" ]]; then out_file="scan_${safe_tag}_${safe_target}_$(date +%s).csv"; fi

    echo -e "\n${GREEN}[*] Запуск сканирования...${NC}"
    echo -e "${YELLOW}(Нажмите Ctrl+C, когда захотите прервать скан)${NC}\n"
    
    cd "$SCANNER_DIR" || return
    export PATH=/usr/local/go/bin:$PATH
    
    echo "IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE,PORT" > "$SCANNER_DIR/$out_file"

    for current_port in "${PORT_ARRAY[@]}"; do
        echo -e "${MAGENTA}>>> СКАНИРОВАНИЕ ПОРТА: ${current_port} <<<${NC}"
        local tmp_csv="tmp_scan_${current_port}.csv"
        
        ./RealiTLScanner -"$mode" "$target" -port "$current_port" -thread "$s_thread" -timeout "$s_timeout" -out "$tmp_csv" >/dev/null 2>&1 &
        local SCAN_PID=$!
        
        trap 'kill $SCAN_PID 2>/dev/null; echo -e "\n${YELLOW}Остановлено пользователем.${NC}"; break' INT

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
        trap - INT

        if [[ -f "$tmp_csv" ]]; then
            tail -n +2 "$tmp_csv" | awk -v p="$current_port" -F',' '{print $0","p}' >> "$SCANNER_DIR/$out_file"
            rm -f "$tmp_csv"
        fi
    done

    echo -e "\n${GREEN}[+] Сканирование завершено!${NC}"
    
    # Сначала анализируем
    analyze_results "$SCANNER_DIR/$out_file"

    # Затем спрашиваем про сохранение
    echo -e "\n${BLUE}======================================================${NC}"
    read -p ">> Сохранить этот отчет в Менеджере Отчетов? (Y/n): " keep_report
    if [[ "$keep_report" == "n" || "$keep_report" == "N" ]]; then
        rm -f "$SCANNER_DIR/$out_file" 2>/dev/null
        echo -e "${YELLOW}Отчет удален.${NC}"
    else
        echo -e "${GREEN}Отчет успешно сохранен!${NC} (Имя: $out_file)"
    fi
    pause
}

# --- 5. МЕНЕДЖЕР ОТЧЕТОВ ---
manage_reports() {
    while true; do
        clear
        echo -e "${MAGENTA}=== 📂 МЕНЕДЖЕР СОХРАНЕННЫХ ОТЧЕТОВ ===${NC}"
        
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
        echo -e " 👉 ${RED}D${NC} - Удалить ВСЕ отчеты разом."
        echo -e " ${CYAN}0.${NC} Назад"
        
        read -p ">> " r_choice

        if [[ "$r_choice" == "0" ]]; then return; fi
        
        if [[ "$r_choice" == "D" || "$r_choice" == "d" ]]; then
            echo -e "\n${RED}⚠️ ВНИМАНИЕ: Вы собираетесь удалить ВСЕ сохраненные отчеты!${NC}"
            read -p "Вы уверены? (y/N): " confirm_del
            if [[ "$confirm_del" == "y" || "$confirm_del" == "Y" ]]; then
                rm -f "$SCANNER_DIR"/*.csv 2>/dev/null
                echo -e "${GREEN}Все отчеты успешно удалены!${NC}"
            fi
            sleep 1
        elif [[ "$r_choice" =~ ^d([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            [[ -n "${CSV_FILES[$idx]}" ]] && rm -f "${CSV_FILES[$idx]}" && echo -e "${GREEN}Файл удален!${NC}" && sleep 1
        elif [[ "$r_choice" =~ ^a([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            if [[ -n "${CSV_FILES[$idx]}" ]]; then
                analyze_results "${CSV_FILES[$idx]}"
                pause
            fi
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
    
    local my_ip=$(curl -s --max-time 3 ipinfo.io/ip 2>/dev/null)
    local my_subnet=$(echo "$my_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')

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
            1) 
                run_single_scan "" 
                ;;
            2) 
                echo -e "\n${CYAN}[*] Ваша подсеть: ${YELLOW}$my_subnet${NC}"
                read -p ">> Введите подсеть (CIDR) [Enter = $my_subnet]: " sub
                sub=${sub:-$my_subnet}
                run_scanner "addr" "$sub" 
                ;;
            3)
                echo -e "\n${CYAN}[*] Ваш IP-адрес: ${YELLOW}$my_ip${NC}"
                echo -e "${GRAY}Скрипт будет бесконечно проверять соседние IP адреса вверх и вниз.${NC}"
                read -p ">> Введите стартовый IP [Enter = $my_ip]: " s_ip
                s_ip=${s_ip:-$my_ip}
                run_scanner "addr" "$s_ip" 
                ;;
            4) manage_input_file ;;
            5)
                echo -e "\n${GRAY}Пример: https://launchpad.net/ubuntu/+archivemirrors${NC}"
                read -p ">> URL со списком: " s_url
                [[ -n "$s_url" ]] && run_scanner "url" "$s_url" 
                ;;
            8) manage_reports ;;
            0) return ;;
        esac
    done
}
