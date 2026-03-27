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
        
        echo -e "${CYAN}[*] Загрузка актуального Go (1.22+)...${NC}"
        wget -q https://go.dev/dl/go1.22.1.linux-amd64.tar.gz -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        export PATH=/usr/local/go/bin:$PATH

        rm -rf "$SCANNER_DIR"
        git clone https://github.com/xtls/RealiTLScanner "$SCANNER_DIR"
        
        cd "$SCANNER_DIR" || return
        echo -e "${CYAN}[*] Компиляция Go-бинарника...${NC}"
        go build -o RealiTLScanner
        
        if [[ -f "$SCANNER_BIN" ]]; then
            chmod +x "$SCANNER_BIN"
        else
            echo -e "${RED}[!] ОШИБКА: Не удалось собрать бинарник.${NC}"
            pause; return 1
        fi
    fi

    # Авто-загрузка GeoIP
    if [[ ! -f "$GEO_DB" ]]; then
        echo -e "${YELLOW}[*] Загрузка базы GeoIP (Country.mmdb)...${NC}"
        curl -L -o "$GEO_DB" "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb" >/dev/null 2>&1
    fi
}

# --- 2. УМНЫЙ АНАЛИЗАТОР (С АВТО-ОПРЕДЕЛЕНИЕМ ГЕО) ---
analyze_results() {
    local file=$1
    [[ ! -f "$file" ]] && { echo -e "${RED}[!] Файл $file не найден.${NC}"; return; }

    echo -e "\n${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}🤖 АНАЛИЗАТОР: РЕКОМЕНДАЦИИ ПО ВЫБОРУ ЦЕЛИ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    echo -e "${GRAY}Для максимальной маскировки домен должен находиться${NC}"
    echo -e "${GRAY}в той же стране, что и ваш VPN-сервер.${NC}"
    
    local server_geo=$(curl -s --max-time 3 ipinfo.io/country 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
    local my_geo=""

    if [[ -n "$server_geo" && ${#server_geo} -eq 2 ]]; then
        echo -e "${CYAN}[*] Автоопределение: Ваш сервер находится в ${YELLOW}${server_geo}${NC}"
        read -p ">> Использовать ГЕО [${server_geo}]? (Enter = Да, 'n' = Отключить фильтр, или введите свой код): " user_input
        
        if [[ -z "$user_input" ]]; then
            my_geo="$server_geo"
        elif [[ "$user_input" == "n" || "$user_input" == "N" ]]; then
            my_geo=""
        else
            my_geo="$user_input"
        fi
    else
        read -p ">> Страна (например FI, NL, DE, RU) [Enter = пропустить фильтр]: " my_geo
    fi
    
    my_geo=$(echo "$my_geo" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')

    echo -e "\n${CYAN}Анализируем файл: $(basename "$file")...${NC}"
    
    local filtered=$(tail -n +2 "$file" | grep -iE "Let's Encrypt|Google|DigiCert|Cloudflare|Sectigo|ZeroSSL|GlobalSign")

    if [[ -n "$my_geo" ]]; then
        local geo_matched=$(echo "$filtered" | grep ",$my_geo$")
        if [[ -n "$geo_matched" ]]; then
            filtered="$geo_matched"
            echo -e "${GREEN}[+] Найдены идеальные домены в стране $my_geo!${NC}"
        else
            echo -e "${RED}[!] Доменов с геопозицией ($my_geo) в этом отчете не найдено.${NC}"
            echo -e "${YELLOW}Показываю лучшие варианты из других стран...${NC}"
        fi
    fi

    local best=$(echo "$filtered" | head -n 7)

    if [[ -z "$best" ]]; then
        echo -e "${RED}Подходящих целей (TLS 1.3 + HTTP/2 + Надежный сертификат) не найдено.${NC}"
    else
        echo -e "\n${GREEN}🏆 ТОП РЕКОМЕНДУЕМЫХ ДОМЕНОВ:${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo "$best" | awk -F',' '{print "📍 Домен: \033[1;32m" $3 "\033[0m\n   └─ IP: " $1 " | ГЕО: \033[1;33m" $5 "\033[0m | Издатель: " $4 "\n"}'
    fi
    pause
}

# --- 3. ИНТЕРАКТИВНЫЙ ЗАПУСК С ПОДРОБНЫМИ ПОДСКАЗКАМИ ---
run_scanner() {
    local mode=$1
    local target=$2
    
    local safe_target=$(echo "$target" | sed 's/[^a-zA-Z0-9]/_/g' | cut -c 1-20)
    local out_file="scan_${safe_target}_$(date +%s).csv"

    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} ⚙️  НАСТРОЙКА ПАРАМЕТРОВ СКАНИРОВАНИЯ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${GRAY}Настройте параметры ниже или просто нажимайте Enter,${NC}"
    echo -e "${GRAY}чтобы использовать оптимальные значения по умолчанию.${NC}\n"

    echo -e "${CYAN}1. Целевой Порт (-port)${NC}"
    echo -e "   По умолчанию Reality работает через HTTPS порт 443."
    read -p ">> Порт (Enter = 443): " s_port; s_port=${s_port:-443}
    echo ""

    echo -e "${CYAN}2. Количество потоков (-thread)${NC}"
    echo -e "   Сколько адресов проверять одновременно. Больше потоков = быстрее скан,"
    echo -e "   но слишком высокое значение может перегрузить ваш сервер."
    read -p ">> Потоков (Enter = 10): " s_thread; s_thread=${s_thread:-10}
    echo ""

    echo -e "${CYAN}3. Таймаут (-timeout)${NC}"
    echo -e "   Сколько секунд ждать ответа от сервера. Меньше = быстрее скан,"
    echo -e "   но вы можете пропустить рабочие, но медленные сервера."
    read -p ">> Таймаут в сек (Enter = 10): " s_timeout; s_timeout=${s_timeout:-10}
    echo ""

    echo -e "${CYAN}4. Поддержка IPv6 (-46)${NC}"
    echo -e "   Если ваш сервер поддерживает IPv6, сканер будет искать цели и в этой сети."
    read -p ">> Включить сканирование IPv6? (y/N): " s_ipv6
    echo ""

    echo -e "${CYAN}5. Подробный вывод логов (-v)${NC}"
    echo -e "   Показывать на экране абсолютно все попытки, включая неудачные,"
    echo -e "   закрытые порты и сервера с плохими сертификатами."
    read -p ">> Включить Verbose? (y/N): " s_verb

    local extra_args=""
    [[ "$s_ipv6" == "y" || "$s_ipv6" == "Y" ]] && extra_args+=" -46"
    [[ "$s_verb" == "y" || "$s_verb" == "Y" ]] && extra_args+=" -v"

    echo -e "\n${GREEN}[*] Запуск сканирования...${NC}"
    echo -e "${YELLOW}(Нажмите Ctrl+C, когда захотите прервать скан)${NC}\n"
    
    cd "$SCANNER_DIR" || return
    export PATH=/usr/local/go/bin:$PATH
    
    # Строгий запуск с одним из режимов: -addr, -in или -url
    ./RealiTLScanner -"$mode" "$target" -port "$s_port" -thread "$s_thread" -timeout "$s_timeout" -out "$out_file" $extra_args

    echo -e "\n${GREEN}[+] Сканирование завершено!${NC}"
    echo -e "Файл сохранен как: ${CYAN}$out_file${NC}"
    analyze_results "$SCANNER_DIR/$out_file"
}

# --- 4. МЕНЕДЖЕР ОТЧЕТОВ ---
manage_reports() {
    while true; do
        clear
        echo -e "${MAGENTA}=== 📂 МЕНЕДЖЕР СОХРАНЕННЫХ ОТЧЕТОВ ===${NC}"
        
        mapfile -t CSV_FILES < <(ls -1 "$SCANNER_DIR"/*.csv 2>/dev/null)
        
        if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
            echo -e "${YELLOW}Отчетов пока нет. Запустите сканирование.${NC}"
            pause; return
        fi

        for i in "${!CSV_FILES[@]}"; do
            local f_size=$(du -sh "${CSV_FILES[$i]}" | awk '{print $1}')
            local f_name=$(basename "${CSV_FILES[$i]}")
            echo -e " ${YELLOW}$((i+1)).${NC} ${CYAN}$f_name${NC} ${GRAY}($f_size)${NC}"
        done

        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " Управление:"
        echo -e " 👉 Введите ${YELLOW}НОМЕР${NC} файла, чтобы посмотреть всю таблицу."
        echo -e " 👉 Введите ${GREEN}aНОМЕР${NC} (например, ${BOLD}a1${NC}), чтобы запустить Умный Анализ."
        echo -e " 👉 Введите ${RED}dНОМЕР${NC} (например, ${BOLD}d1${NC}), чтобы удалить отчет."
        echo -e " ${CYAN}0.${NC} Назад"
        
        read -p ">> " r_choice

        if [[ "$r_choice" == "0" ]]; then return; fi
        
        if [[ "$r_choice" =~ ^d([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            if [[ -n "${CSV_FILES[$idx]}" ]]; then
                rm -f "${CSV_FILES[$idx]}"
                echo -e "${GREEN}Файл удален!${NC}"; sleep 1
            fi
        elif [[ "$r_choice" =~ ^a([0-9]+)$ ]]; then
            local idx=$((${BASH_REMATCH[1]}-1))
            if [[ -n "${CSV_FILES[$idx]}" ]]; then
                analyze_results "${CSV_FILES[$idx]}"
            fi
        elif [[ "$r_choice" =~ ^[0-9]+$ ]]; then
            local idx=$((r_choice-1))
            if [[ -n "${CSV_FILES[$idx]}" ]]; then
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
    echo -e " ${YELLOW}1.${NC} 📝 Редактировать список (Откроется в nano)"
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
        echo -e "  Умный поиск идеальных доменов для маскировки."
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${GRAY} ВАЖНО: Сканер принимает только один режим за раз.${NC}"
        echo -e "${GRAY} Выберите, откуда брать цели для проверки:${NC}\n"

        echo -e " ${YELLOW}1.${NC} Строгий скан одного IP / Домена   ${GRAY}(-addr)${NC}"
        echo -e "    └─ Быстрая разовая проверка конкретного узла."
        
        echo -e " ${YELLOW}2.${NC} Скан подсети (CIDR)               ${GRAY}(-addr)${NC}"
        echo -e "    └─ Проверка пула адресов, например 104.21.0.0/24."
        
        echo -e " ${YELLOW}3.${NC} Бесконечный поиск (Infinity Mode) ${GRAY}(-addr)${NC}"
        echo -e "    └─ Скрипт берет стартовый IP и сканирует бесконечно вверх и вниз."
        
        echo -e " ${YELLOW}4.${NC} 📂 Работа со списком (in.txt)     ${GRAY}(-in)${NC}"
        echo -e "    └─ Читает цели из файла (каждый IP/Домен с новой строки)."
        
        echo -e " ${YELLOW}5.${NC} Сбор доменов с веб-страницы       ${GRAY}(-url)${NC}"
        echo -e "    └─ Вытаскивает домены с указанного URL (например, списки зеркал)."
        
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}8.${NC} 📂 Менеджер Отчетов (Просмотр / Анализ / Удаление)"
        echo -e " ${RED}0.${NC} ↩️ Назад"
        
        read -p ">> " s_choice
        case $s_choice in
            1) 
                read -p "Введите цель (IP или домен): " target
                # Добавляем /32 к IP, чтобы отключить бесконечный режим (Infinity Mode)
                if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    target="${target}/32"
                fi
                [[ -n "$target" ]] && run_scanner "addr" "$target" ;;
            2) 
                read -p "Введите подсеть (CIDR): " sub
                [[ -n "$sub" ]] && run_scanner "addr" "$sub" ;;
            3)
                read -p "Введите стартовый IP: " s_ip
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
