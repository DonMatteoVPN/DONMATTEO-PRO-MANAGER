#!/bin/bash
# Модуль Reality TLS Scanner PRO (Ultimate Edition)

SCANNER_DIR="/opt/RealiTLScanner"
SCANNER_BIN="$SCANNER_DIR/RealiTLScanner"
GEO_DB="$SCANNER_DIR/Country.mmdb"
INPUT_FILE="$SCANNER_DIR/in.txt"
RECON_DIR="$SCANNER_DIR/recon" # Новая папка для досье

# --- 1. УСТАНОВКА И СБОРКА ---
check_scanner_install() {
    export PATH=/usr/local/go/bin:$PATH
    mkdir -p "$RECON_DIR" 2>/dev/null

    if [[ ! -f "$SCANNER_BIN" ]]; then
        echo -e "${YELLOW}[*] Сканер не найден. Начинаю установку (Go 1.22+)...${NC}"
        apt-get update >/dev/null 2>&1
        apt-get install git wget curl -y >/dev/null 2>&1
        
        wget -q https://go.dev/dl/go1.22.1.linux-amd64.tar.gz -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        export PATH=/usr/local/go/bin:$PATH

        rm -rf "$SCANNER_DIR/RealiTLScanner_src"
        git clone https://github.com/xtls/RealiTLScanner "$SCANNER_DIR/RealiTLScanner_src"
        
        cd "$SCANNER_DIR/RealiTLScanner_src" || return
        echo -e "${CYAN}[*] Компиляция бинарника...${NC}"
        go build -o "$SCANNER_BIN"
        
        if [[ -f "$SCANNER_BIN" ]]; then 
            chmod +x "$SCANNER_BIN"
            rm -rf "$SCANNER_DIR/RealiTLScanner_src"
        else 
            echo -e "${RED}[!] ОШИБКА сборки.${NC}"; pause; return 1
        fi
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

# --- 2. РЕЖИМ "РЕНТГЕН" И ПРОБИВ ПРОВАЙДЕРА (ПУНКТ 1) ---
run_single_scan() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 🔬 РЕЖИМ: СТРОГИЙ СКАН И ПРОБИВ ЦЕЛИ (OSINT)${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${CYAN}Для чего это нужно?${NC}"
    echo -e "${GRAY}Скрипт проверяет конкретный сервер, выдает его полное TLS-досье и${NC}"
    echo -e "${GRAY}ищет информацию о провайдере (чтобы вы могли арендовать сервер там же).${NC}\n"

    read -p ">> Введите цель (IP или Домен): " target
    [[ -z "$target" ]] && return

    # Хак: отключаем бесконечность для IPv4
    if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then 
        local safe_target=$target
        target="${target}/32"
    else
        local safe_target=$target
    fi

    read -p ">> Порт(ы) через запятую (Enter = 443): " s_port
    s_port=${s_port:-443}
    IFS=',' read -ra PORT_ARRAY <<< "${s_port// /}"

    echo -e "\n${GREEN}[*] Сбор данных...${NC}"
    
    # Переменная для хранения всего отчета, чтобы потом его сохранить
    local REPORT_OUTPUT=""
    local nl=$'\n'

    # Пробив провайдера (OSINT)
    local ip_to_check=$safe_target
    # Если ввели домен, пытаемся резолвить его в IP
    if [[ ! "$ip_to_check" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip_to_check=$(getent hosts "$safe_target" | awk '{ print $1 }' | head -n 1)
    fi

    REPORT_OUTPUT+="======================================================${nl}"
    REPORT_OUTPUT+=" 📄 ПОЛНОЕ ДОСЬЕ НА ЦЕЛЬ: ${safe_target}${nl}"
    REPORT_OUTPUT+="======================================================${nl}"

    if [[ -n "$ip_to_check" ]]; then
        local org_info=$(curl -s --max-time 3 ipinfo.io/${ip_to_check}/org 2>/dev/null)
        local city_info=$(curl -s --max-time 3 ipinfo.io/${ip_to_check}/city 2>/dev/null)
        local country_info=$(curl -s --max-time 3 ipinfo.io/${ip_to_check}/country 2>/dev/null)
        
        REPORT_OUTPUT+=" 📡 ИНФОРМАЦИЯ О ПРОВАЙДЕРЕ (OSINT)${nl}"
        REPORT_OUTPUT+="   └─ Провайдер (ASN): ${org_info:-Неизвестно}${nl}"
        REPORT_OUTPUT+="   └─ Город:           ${city_info:-Неизвестно} (${country_info:-N/A})${nl}"
        
        if [[ -n "$org_info" ]]; then
            # Генерируем ссылку на Google для поиска хостинга
            local search_query=$(echo "buy vps $org_info" | sed 's/ /+/g')
            REPORT_OUTPUT+="   └─ Поиск хостинга:  https://www.google.com/search?q=${search_query}${nl}"
        fi
        REPORT_OUTPUT+="------------------------------------------------------${nl}"
    fi
    
    cd "$SCANNER_DIR" || return
    export PATH=/usr/local/go/bin:$PATH
    
    for current_port in "${PORT_ARRAY[@]}"; do
        REPORT_OUTPUT+=" >>> СКАНИРОВАНИЕ ПОРТА: ${current_port} <<<${nl}"
        
        # Запускаем сканер и собираем лог
        local scan_log=$(./RealiTLScanner -addr "$target" -port "$current_port" -timeout 5 -v 2>&1)
        
        local found_info=false
        while read -r line; do
            if [[ "$line" == *"Connected to target"* ]]; then
                found_info=true
                local feas=$(echo "$line" | grep -oP 'feasible=\K[^ ]+')
                local ip=$(echo "$line" | grep -oP 'ip=\K[^ ]+')
                # Умный Regex, который идеально работает с кавычками и без них
                local tls=$(echo "$line" | grep -oP 'tls=\K([^ ]+|"[^"]+")' | tr -d '"')
                local alpn=$(echo "$line" | grep -oP 'alpn=\K([^ ]+|"[^"]+")' | tr -d '"')
                local dom=$(echo "$line" | grep -oP 'cert-domain=\K([^ ]+|"[^"]+")' | tr -d '"')
                local iss=$(echo "$line" | grep -oP 'cert-issuer=\K([^ ]+|"[^"]+")' | tr -d '"')
                local geo=$(echo "$line" | grep -oP 'geo=\K[^ ]+')

                REPORT_OUTPUT+="${nl} 🌐 IP-адрес:  ${ip:-Неизвестно}${nl}"
                if [[ "$feas" == "true" ]]; then
                    REPORT_OUTPUT+=" ✅ Статус:    ПОДХОДИТ ДЛЯ REALITY${nl}"
                else
                    REPORT_OUTPUT+=" ❌ Статус:    НЕ ПОДХОДИТ (См. параметры ниже)${nl}"
                fi
                REPORT_OUTPUT+=" 🔒 TLS Версия: ${tls:-Отсутствует}${nl}"
                REPORT_OUTPUT+=" ⚡ ALPN:       ${alpn:-Отсутствует}${nl}"
                REPORT_OUTPUT+=" 📍 Домен (SNI): ${dom:-Отсутствует}${nl}"
                REPORT_OUTPUT+=" 🏢 Издатель:  ${iss:-Отсутствует}${nl}"
                REPORT_OUTPUT+=" 🌍 Локация:   ${geo:-N/A}${nl}"
                REPORT_OUTPUT+="------------------------------------------------------${nl}"
            
            elif [[ "$line" == *"TLS handshake failed"* ]]; then
                found_info=true
                local tip=$(echo "$line" | grep -oP 'target=\K[^ ]+')
                REPORT_OUTPUT+=" ❌ [$tip] ОШИБКА: Сервер не поддерживает нужный HTTPS/TLS${nl}"
            elif [[ "$line" == *"Cannot dial"* ]]; then
                found_info=true
                local tip=$(echo "$line" | grep -oP 'target=\K[^ ]+')
                REPORT_OUTPUT+=" ❌ [$tip] ОШИБКА: Сервер мертв или порт закрыт${nl}"
            elif [[ "$line" == *"Failed to get IP"* || "$line" == *"no IP found"* ]]; then
                found_info=true
                REPORT_OUTPUT+=" ❌ ОШИБКА: Домен не существует (Невозможно получить IP)${nl}"
            fi
        done <<< "$scan_log"

        if [[ "$found_info" == false ]]; then
            REPORT_OUTPUT+=" ❌ Нет ответа. Возможно, цель блокирует сканирование.${nl}"
        fi
    done
    
    # Выводим отчет на экран
    clear
    # Красим ключевые слова для красивого вывода
    echo "$REPORT_OUTPUT" | sed -e "s/ПОДХОДИТ ДЛЯ REALITY/$(printf '\033[1;32m')&$(printf '\033[0m')/" \
                                -e "s/НЕ ПОДХОДИТ.*/$(printf '\033[1;31m')&$(printf '\033[0m')/" \
                                -e "s/ОШИБКА.*/$(printf '\033[1;31m')&$(printf '\033[0m')/" \
                                -e "s/ИНФОРМАЦИЯ О ПРОВАЙДЕРЕ/$(printf '\033[1;36m')&$(printf '\033[0m')/"

    echo -e "\n${BLUE}======================================================${NC}"
    read -p ">> Сохранить это досье в Менеджере Отчетов? (Y/n): " keep_recon
    if [[ "$keep_recon" != "n" && "$keep_recon" != "N" ]]; then
        local safe_name=$(echo "$safe_target" | sed 's/[^a-zA-Z0-9]/_/g')
        local recon_file="$RECON_DIR/recon_${safe_name}_$(date +%s).txt"
        echo "$REPORT_OUTPUT" > "$recon_file"
        echo -e "${GREEN}Досье успешно сохранено!${NC}"
    fi
    pause
}

# --- 3. УМНЫЙ АНАЛИЗАТОР (ДЛЯ МАССОВЫХ СКАНОВ) ---
analyze_results() {
    local file=$1
    [[ ! -f "$file" ]] && { echo -e "${RED}[!] Файл $file не найден.${NC}"; return; }

    local total_lines=$(wc -l < "$file" 2>/dev/null)
    if [[ "$total_lines" -le 1 ]]; then
        echo -e "\n${RED}[!] В отчете пусто. Сканер ничего не нашел.${NC}"; return
    fi

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}🤖 АНАЛИЗАТОР: ОТБОР ИДЕАЛЬНЫХ SNI КАНДИДАТОВ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
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

# --- 4. МАССОВЫЙ СКАНЕР (ДЛЯ ПУНКТОВ 2-5) ---
run_scanner() {
    local mode=$1
    local target=$2
    local title=$3
    local description=$4

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} $title${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${CYAN}Для чего это нужно?${NC}"
    echo -e "${GRAY}$description${NC}\n"

    if [[ -z "$target" ]]; then
        read -p ">> Введите цель: " target
        [[ -z "$target" ]] && return
    fi

    if [[ "$mode" == "addr" && "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then target="${target}/32"; fi

    local safe_target=$(echo "$target" | sed 's/[^a-zA-Z0-9]/_/g' | cut -c 1-15)
    local out_file="scan_${mode}_${safe_target}_$(date +%s).csv"

    echo -e "${BLUE}--- Настройка параметров сканирования ---${NC}"
    echo -e "${CYAN}Цель:${NC} $target (Режим: -$mode)\n"

    read -p ">> Порт(ы) через запятую (Enter = 443): " s_port; s_port=${s_port:-443}
    IFS=',' read -ra PORT_ARRAY <<< "${s_port// /}"
    read -p ">> Потоков (Enter = 10): " s_thread; s_thread=${s_thread:-10}
    read -p ">> Таймаут в сек (Enter = 5): " s_timeout; s_timeout=${s_timeout:-5}
    read -p ">> Сколько успешных SNI найти? (Enter = 0, бесконечно): " s_limit; s_limit=${s_limit:-0}
    read -p ">> Добавить метку к имени файла (напр. Hetzner) [Enter = пропустить]: " s_tag
    
    local safe_tag=$(echo "$s_tag" | sed 's/[^a-zA-Z0-9]/_/g')
    if [[ -n "$safe_tag" ]]; then out_file="scan_${safe_tag}_${safe_target}_$(date +%s).csv"; fi

    echo -e "\n${GREEN}[*] Запуск сканирования...${NC}"
    cd "$SCANNER_DIR" || return
    export PATH=/usr/local/go/bin:$PATH
    
    echo "IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE,PORT" > "$SCANNER_DIR/$out_file"

    for current_port in "${PORT_ARRAY[@]}"; do
        echo -e "${MAGENTA}>>> СКАНИРОВАНИЕ ПОРТА: ${current_port} <<<${NC}"
        local tmp_csv="tmp_scan_${current_port}.csv"
        
        ./RealiTLScanner -"$mode" "$target" -port "$current_port" -thread "$s_thread" -timeout "$s_timeout" -out "$tmp_csv" >/dev/null 2>&1 &
        local SCAN_PID=$!
        
        trap 'kill $SCAN_PID 2>/dev/null; echo -e "\n\n${YELLOW}Остановлено пользователем.${NC}"; break' INT

        while kill -0 $SCAN_PID 2>/dev/null; do
            if [[ -f "$tmp_csv" ]]; then
                local current_count=$(cat "$tmp_csv" 2>/dev/null | wc -l)
                local actual_count=$((current_count > 0 ? current_count - 1 : 0))
                local last_sni=$(tail -n 1 "$tmp_csv" 2>/dev/null | awk -F, '{print $3}')
                
                if [[ -n "$last_sni" && "$last_sni" != "CERT_DOMAIN" ]]; then
                    echo -ne "\r\033[K${CYAN}⏳ Сканирование... Найдено SNI: ${GREEN}${actual_count}${NC} | Последний: ${YELLOW}${last_sni}${NC}"
                else
                    echo -ne "\r\033[K${CYAN}⏳ Сканирование... Найдено SNI: ${GREEN}${actual_count}${NC}"
                fi
                
                if [[ "$s_limit" -gt 0 && "$actual_count" -ge "$s_limit" ]]; then
                    echo -e "\n\n${GREEN}[+] Лимит ($s_limit) достигнут!${NC}"
                    kill $SCAN_PID 2>/dev/null; break
                fi
            else
                echo -ne "\r\033[K${CYAN}⏳ Запуск потоков...${NC}"
            fi
            sleep 1
        done
        echo -e ""
        trap - INT

        if [[ -f "$tmp_csv" ]]; then
            tail -n +2 "$tmp_csv" | awk -v p="$current_port" -F',' '{print $0","p}' >> "$SCANNER_DIR/$out_file"
            rm -f "$tmp_csv"
        fi
    done

    echo -e "${GREEN}[+] Сканирование завершено!${NC}"
    analyze_results "$SCANNER_DIR/$out_file"

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

# --- 5. РАЗДЕЛЕННЫЙ МЕНЕДЖЕР ОТЧЕТОВ ---
manage_csv_reports() {
    while true; do
        clear
        echo -e "${MAGENTA}=== 📊 ОТЧЕТЫ МАССОВОГО СКАНИРОВАНИЯ (CSV) ===${NC}"
        
        mapfile -t CSV_FILES < <(ls -1t "$SCANNER_DIR"/*.csv 2>/dev/null)
        if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
            echo -e "${YELLOW}Отчетов CSV пока нет.${NC}"; pause; return
        fi

        for i in "${!CSV_FILES[@]}"; do
            local f_size=$(du -sh "${CSV_FILES[$i]}" | awk '{print $1}')
            local f_name=$(basename "${CSV_FILES[$i]}")
            echo -e " ${YELLOW}$((i+1)).${NC} ${CYAN}$f_name${NC} ${GRAY}($f_size)${NC}"
        done

        echo -e "\n${BLUE}------------------------------------------------------${NC}"
        echo -e " 👉 ${YELLOW}НОМЕР${NC} - Посмотреть сырую таблицу CSV."
        echo -e " 👉 ${GREEN}aНОМЕР${NC} (напр. ${BOLD}a1${NC}) - Запустить Умный Анализ."
        echo -e " 👉 ${RED}dНОМЕР${NC} (напр. ${BOLD}d1${NC}) - Удалить отчет."
        echo -e " 👉 ${RED}D${NC} - Удалить ВСЕ отчеты разом."
        echo -e " ${CYAN}0.${NC} Назад"
        
        read -p ">> " r_choice
        [[ "$r_choice" == "0" ]] && return
        
        if [[ "$r_choice" == "D" || "$r_choice" == "d" ]]; then
            read -p "Удалить ВСЕ CSV отчеты? (y/N): " confirm_del
            [[ "$confirm_del" == "y" || "$confirm_del" == "Y" ]] && rm -f "$SCANNER_DIR"/*.csv 2>/dev/null && echo -e "${GREEN}Очищено!${NC}" && sleep 1
        elif [[ "$r_choice" =~ ^d([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            [[ -n "${CSV_FILES[$idx]}" ]] && rm -f "${CSV_FILES[$idx]}" && echo -e "${GREEN}Удалено!${NC}" && sleep 1
        elif [[ "$r_choice" =~ ^a([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            [[ -n "${CSV_FILES[$idx]}" ]] && analyze_results "${CSV_FILES[$idx]}" && pause
        elif [[ "$r_choice" =~ ^[0-9]+$ ]]; then
            local idx=$((r_choice-1))
            [[ -n "${CSV_FILES[$idx]}" ]] && column -t -s ',' "${CSV_FILES[$idx]}" | less -S
        else
            echo -e "${RED}Неверный ввод.${NC}"; sleep 1
        fi
    done
}

manage_recon_reports() {
    while true; do
        clear
        echo -e "${MAGENTA}=== 📄 ДОСЬЕ НА КОНКРЕТНЫЕ ЦЕЛИ (TXT) ===${NC}"
        
        mapfile -t TXT_FILES < <(ls -1t "$RECON_DIR"/*.txt 2>/dev/null)
        if [[ ${#TXT_FILES[@]} -eq 0 ]]; then
            echo -e "${YELLOW}Сохраненных досье пока нет.${NC}"; pause; return
        fi

        for i in "${!TXT_FILES[@]}"; do
            local f_size=$(du -sh "${TXT_FILES[$i]}" | awk '{print $1}')
            local f_name=$(basename "${TXT_FILES[$i]}")
            echo -e " ${YELLOW}$((i+1)).${NC} ${CYAN}$f_name${NC} ${GRAY}($f_size)${NC}"
        done

        echo -e "\n${BLUE}------------------------------------------------------${NC}"
        echo -e " 👉 ${YELLOW}НОМЕР${NC} - Открыть досье."
        echo -e " 👉 ${RED}dНОМЕР${NC} - Удалить досье."
        echo -e " 👉 ${RED}D${NC} - Удалить ВСЕ досье разом."
        echo -e " ${CYAN}0.${NC} Назад"
        
        read -p ">> " r_choice
        [[ "$r_choice" == "0" ]] && return
        
        if [[ "$r_choice" == "D" || "$r_choice" == "d" ]]; then
            read -p "Удалить ВСЕ досье? (y/N): " confirm_del
            [[ "$confirm_del" == "y" || "$confirm_del" == "Y" ]] && rm -f "$RECON_DIR"/*.txt 2>/dev/null && echo -e "${GREEN}Очищено!${NC}" && sleep 1
        elif [[ "$r_choice" =~ ^d([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            [[ -n "${TXT_FILES[$idx]}" ]] && rm -f "${TXT_FILES[$idx]}" && echo -e "${GREEN}Удалено!${NC}" && sleep 1
        elif [[ "$r_choice" =~ ^[0-9]+$ ]]; then
            local idx=$((r_choice-1))
            [[ -n "${TXT_FILES[$idx]}" ]] && less -r "${TXT_FILES[$idx]}"
        else
            echo -e "${RED}Неверный ввод.${NC}"; sleep 1
        fi
    done
}

manage_reports_menu() {
    while true; do
        clear
        echo -e "${MAGENTA}======================================================${NC}"
        echo -e "${BOLD} 📂 МЕНЕДЖЕР ОТЧЕТОВ${NC}"
        echo -e "${MAGENTA}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 📊 Отчеты массового сканирования (CSV)"
        echo -e " ${GRAY}   └─ Результаты работы по подсетям, файлам и URL.${NC}"
        echo -e " ${YELLOW}2.${NC} 📄 Досье на конкретные цели (TXT)"
        echo -e " ${GRAY}   └─ Сохраненные пробивы провайдеров и рентген серверов.${NC}"
        echo -e " ${CYAN}0.${NC} ↩️ Назад"
        
        read -p ">> " rm_choice
        case $r_choice in
            1) manage_csv_reports ;;
            2) manage_recon_reports ;;
            0) return ;;
        esac
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
        2) 
            if [[ ! -s "$INPUT_FILE" ]]; then echo -e "${RED}Файл пуст!${NC}"; sleep 2
            else
                run_scanner "in" "$INPUT_FILE" "📂 РЕЖИМ: СКАН ПО СПИСКУ ЦЕЛЕЙ (IN.TXT)" "Скрипт проверяет все IP и домены из файла $INPUT_FILE."
            fi ;;
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
        echo -e "  Мощный радар для поиска идеальных доменов маскировки."
        echo -e "${BLUE}======================================================${NC}"

        echo -e " ${YELLOW}1.${NC} Строгий скан одного IP / Домена   ${GRAY}(-addr)${NC}"
        echo -e " ${GRAY}   └─ Пробив провайдера и полное досье (Рентген) на сервер.${NC}"
        echo -e " ${YELLOW}2.${NC} Массовый скан подсети (CIDR)      ${GRAY}(-addr)${NC}"
        echo -e " ${GRAY}   └─ Главный режим! Ищет лучшие домены среди ваших 'соседей'.${NC}"
        echo -e " ${YELLOW}3.${NC} Бесконечный поиск (Infinity Mode) ${GRAY}(-addr)${NC}"
        echo -e " ${GRAY}   └─ Ищет подходящие сервера во все стороны от стартового IP.${NC}"
        echo -e " ${YELLOW}4.${NC} 📂 Скан по списку из файла        ${GRAY}(-in)${NC}"
        echo -e " ${GRAY}   └─ Проверяет ваши заранее заготовленные списки.${NC}"
        echo -e " ${YELLOW}5.${NC} Сбор и скан доменов по URL        ${GRAY}(-url)${NC}"
        echo -e " ${GRAY}   └─ Вытаскивает и проверяет домены с любой веб-страницы.${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}8.${NC} 📂 Менеджер Отчетов (Анализ / Просмотр / Удаление)"
        echo -e " ${RED}0.${NC} ↩️ Назад"
        
        read -p ">> " s_choice
        case $s_choice in
            1) run_single_scan "" ;;
            2) 
                echo -e "\n${CYAN}[*] Ваша подсеть: ${YELLOW}$my_subnet${NC}"
                read -p ">> Введите подсеть (CIDR) [Enter = $my_subnet]: " sub
                run_scanner "addr" "${sub:-$my_subnet}" "🌐 РЕЖИМ: МАССОВЫЙ СКАН ПОДСЕТИ (CIDR)" "Проверяет пул адресов. Поиск SNI-кандидатов среди 'соседей'." ;;
            3)
                echo -e "\n${CYAN}[*] Ваш IP-адрес: ${YELLOW}$my_ip${NC}"
                read -p ">> Введите стартовый IP [Enter = $my_ip]: " s_ip
                run_scanner "addr" "${s_ip:-$my_ip}" "♾️ РЕЖИМ: БЕСКОНЕЧНЫЙ ПОИСК (INFINITY MODE)" "Бесконечно проверяет соседние адреса (+1/-1) от стартового IP." ;;
            4) manage_input_file ;;
            5)
                echo -e "\n${GRAY}Пример: https://launchpad.net/ubuntu/+archivemirrors${NC}"
                read -p ">> URL со списком: " s_url
                [[ -n "$s_url" ]] && run_scanner "url" "$s_url" "🕸️ РЕЖИМ: ВЕБ-КРАУЛЕР (СБОР ПО URL)" "Вытаскивает доменные имена со страницы и сканирует их." ;;
            8) manage_reports_menu ;;
            0) return ;;
        esac
    done
}
