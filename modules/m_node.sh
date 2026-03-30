#!/bin/bash
# Модуль Remna-Node & Xray Assets

# Пути
export XRAY_ASSETS_DIR="${BASE_DIR}/xray/share"
export UPDATE_SCRIPT="${BASE_DIR}/update_assets.sh"

# --- ФУНКЦИЯ СТАТУСА АВТООБНОВЛЕНИЯ ---
get_node_autoupdate_status() {
    if crontab -l 2>/dev/null | grep -q "update_assets.sh"; then
        echo -e "${GREEN}[ВКЛЮЧЕНО]${NC}"
    else
        echo -e "${RED}[ВЫКЛЮЧЕНО]${NC}"
    fi
}

# --- ФУНКЦИИ ЛОГОВ ---
view_node_logs() {
    local log_type=$1
    local email=${2:-""}
    local path=""

    case $log_type in
        "node_err") path="/var/log/remnanode/error.log" ;;
        "node_acc") path="/var/log/remnanode/access.log" ;;
        "nginx_acc") path="${BASE_DIR}/nginx_logs/access.log" ;;
        "nginx_err") path="${BASE_DIR}/nginx_logs/error.log" ;;
        "nginx_stream") path="${BASE_DIR}/nginx_logs/stream_scanners.log" ;;
    esac

    clear
    echo -e "${YELLOW}Просмотр логов: $path${NC}"
    [[ -n "$email" ]] && echo -e "${CYAN}Фильтр по Email: $email${NC}"
    echo -e "${GRAY}Нажмите Ctrl+C для выхода...${NC}\n"

    if [[ -n "$email" ]]; then
        tail -f "$path" 2>/dev/null | grep --line-buffered "email: $email" || echo -e "${RED}Лог пуст или недоступен.${NC}"
    else
        tail -f "$path" 2>/dev/null || echo -e "${RED}Лог пуст или недоступен.${NC}"
    fi
}

menu_logs() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  📋 ЦЕНТР УПРАВЛЕНИЯ ЛОГАМИ${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} Нода: Ошибки (Error Log)"
        echo -e " ${YELLOW}2.${NC} Нода: Трафик (Access Log)"
        echo -e " ${YELLOW}3.${NC} Нода: Поиск по EMAIL пользователя"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${GREEN}4.${NC} Nginx: Доступ (Сайт / XHTTP)"
        echo -e " ${GREEN}5.${NC} Nginx: Ошибки"
        echo -e " ${GREEN}6.${NC} Nginx: Стрикер (TCP Сканеры)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " ch
        case $ch in
            1) view_node_logs "node_err" ;;
            2) view_node_logs "node_acc" ;;
            3) read -p "Введите email пользователя: " em; view_node_logs "node_acc" "$em" ;;
            4) view_node_logs "nginx_acc" ;;
            5) view_node_logs "nginx_err" ;;
            6) view_node_logs "nginx_stream" ;;
            0) return ;;
        esac
    done
}

# --- ФУНКЦИИ АССЕТОВ (БАЗЫ) ---
install_assets() {
    echo -e "${CYAN}[*] Установка баз данных (GeoSite / GeoIP / Zapret)...${NC}"
    mkdir -p "$XRAY_ASSETS_DIR"
    
    # Проверяем и удаляем папки если они есть (должны быть файлы)
    for item in "$XRAY_ASSETS_DIR/zapret.dat" "$XRAY_ASSETS_DIR/mygeosite.dat" "$XRAY_ASSETS_DIR/mygeoip.dat"; do
        if [[ -d "$item" ]]; then
            echo -e "${YELLOW}[!] Найдена папка вместо файла: $(basename $item). Удаляю...${NC}"
            rm -rf "$item"
        fi
    done
    
    cd "$XRAY_ASSETS_DIR" || return

    echo -e "${YELLOW}[1/3] Скачивание Zapret (Антизапрет РФ)...${NC}"
    smart_curl "https://github.com/kutovoys/ru_gov_zapret/releases/latest/download/zapret.dat" "zapret.dat.tmp" 60
    [[ -s "zapret.dat.tmp" ]] && mv "zapret.dat.tmp" "zapret.dat" || rm -f "zapret.dat.tmp"
    
    echo -e "${YELLOW}[2/3] Скачивание MyGeoSite (Разблокировки)...${NC}"
    smart_curl "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat" "mygeosite.dat.tmp" 60
    [[ -s "mygeosite.dat.tmp" ]] && mv "mygeosite.dat.tmp" "mygeosite.dat" || rm -f "mygeosite.dat.tmp"
    
    echo -e "${YELLOW}[3/3] Скачивание MyGeoIP (Регионы)...${NC}"
    smart_curl "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat" "mygeoip.dat.tmp" 60
    [[ -s "mygeoip.dat.tmp" ]] && mv "mygeoip.dat.tmp" "mygeoip.dat" || rm -f "mygeoip.dat.tmp"

    if [[ -s "zapret.dat" && -s "mygeosite.dat" && -s "mygeoip.dat" ]]; then
        echo -e "${GREEN}[+] Базы успешно установлены в $XRAY_ASSETS_DIR${NC}"
        if command -v docker &>/dev/null; then
            echo -e "${CYAN}[*] Перезапуск ноды для применения изменений...${NC}"
            docker restart remnanode >/dev/null 2>&1 && echo -e "${GREEN}[+] Нода перезапущена.${NC}" || echo -e "${YELLOW}[!] Контейнер remnanode не запущен.${NC}"
        fi
    else
        echo -e "${RED}[!] Ошибка при скачивании баз. Проверьте сеть.${NC}"
    fi
    pause
}

# --- ПЛАНИРОВЩИК ---
setup_assets_cron() {
    clear
    echo -e "${MAGENTA}=== НАСТРОЙКА АВТООБНОВЛЕНИЯ БАЗ ===${NC}"
    echo -e "${GRAY}Скрипт будет автоматически обновлять базы по вашему расписанию.${NC}\n"
    
    # Проверяем существующее расписание
    local existing_job=$(crontab -l 2>/dev/null | grep -F -- 'update_assets.sh')
    if [[ -n "$existing_job" ]]; then
        local e_min=$(echo "$existing_job" | awk '{print $1}')
        local e_hour=$(echo "$existing_job" | awk '{print $2}')
        local e_dow=$(echo "$existing_job" | awk '{print $5}')
        
        # Преобразуем дни недели в читаемый формат
        local days_text=""
        case "$e_dow" in
            "*") days_text="Каждый день" ;;
            "0") days_text="Воскресенье" ;;
            "1") days_text="Понедельник" ;;
            "2") days_text="Вторник" ;;
            "3") days_text="Среда" ;;
            "4") days_text="Четверг" ;;
            "5") days_text="Пятница" ;;
            "6") days_text="Суббота" ;;
            "1,3,5") days_text="Пн, Ср, Пт" ;;
            "0,6") days_text="Сб, Вс" ;;
            *) days_text="$e_dow" ;;
        esac
        
        echo -e " ${GREEN}✅ Текущее активное расписание:${NC}"
        echo -e "    Дни недели: ${CYAN}${days_text}${NC} | Время запуска: ${CYAN}$(printf "%02d:%02d" "$e_hour" "$e_min" 2>/dev/null || echo "$e_hour:$e_min")${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${YELLOW}1.${NC} 🔄 Изменить расписание"
        echo -e " ${RED}2.${NC} 🗑️  Отключить и удалить автообновление"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " action
        case $action in
            2) 
                crontab -l 2>/dev/null | grep -v -F -- 'update_assets.sh' | crontab -
                echo -e "\n${GREEN}[+] Автообновление баз успешно отключено!${NC}"
                pause
                return
                ;;
            0) return ;;
            1) echo -e "\n${CYAN}--- Настройка нового расписания ---${NC}" ;;
            *) return ;;
        esac
    fi
    
    echo -e "Выберите дни недели для обновления:"
    echo -e " ${YELLOW}1,3,5${NC} - Пн, Ср, Пт | ${YELLOW}*${NC} - Каждый день | ${YELLOW}0${NC} - Вс | ${YELLOW}0,6${NC} - Сб, Вс"
    read -p ">> Ваш выбор: " days
    [[ -z "$days" ]] && days="*"
    
    echo -e "\nВведите ЧАС запуска (от 0 до 23) [по умолчанию: 4]:"
    read -p ">> " hour
    hour=${hour:-4}
    [[ ! "$hour" =~ ^([0-1]?[0-9]|2[0-3])$ ]] && { echo -e "${YELLOW}Неверный ввод. Установлено: 04${NC}"; hour="4"; }
    
    echo -e "\nВведите МИНУТЫ (от 0 до 59) [по умолчанию: 0]:"
    read -p ">> " min
    min=${min:-0}
    [[ ! "$min" =~ ^([0-5]?[0-9])$ ]] && { echo -e "${YELLOW}Неверный ввод. Установлено: 00${NC}"; min="0"; }
    
    # Создаем скрипт обновления
    cat << 'EOF' > "$UPDATE_SCRIPT"
#!/bin/bash
# Автоматическое обновление ассетов TrafficGuard
export BASE_DIR="/opt/remnawave/DONMATTEO-PRO-MANAGER"
source "${BASE_DIR}/modules/m_core.sh" 2>/dev/null || true

DIR="${BASE_DIR}/xray/share"
mkdir -p "$DIR"

# Удаляем папки если они есть (должны быть файлы)
for item in "$DIR/zapret.dat" "$DIR/mygeosite.dat" "$DIR/mygeoip.dat"; do
    [[ -d "$item" ]] && rm -rf "$item"
done

# Скачиваем во временные файлы
curl -fsSL --connect-timeout 10 --max-time 60 \
    "https://github.com/kutovoys/ru_gov_zapret/releases/latest/download/zapret.dat" \
    -o "$DIR/zapret.dat.new" 2>/dev/null

curl -fsSL --connect-timeout 10 --max-time 60 \
    "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat" \
    -o "$DIR/mygeosite.dat.new" 2>/dev/null

curl -fsSL --connect-timeout 10 --max-time 60 \
    "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat" \
    -o "$DIR/mygeoip.dat.new" 2>/dev/null

# Проверяем и заменяем
if [[ -s "$DIR/zapret.dat.new" && -s "$DIR/mygeosite.dat.new" && -s "$DIR/mygeoip.dat.new" ]]; then
    mv "$DIR/zapret.dat.new" "$DIR/zapret.dat"
    mv "$DIR/mygeosite.dat.new" "$DIR/mygeosite.dat"
    mv "$DIR/mygeoip.dat.new" "$DIR/mygeoip.dat"
    
    # Перезапускаем ноду
    if command -v docker &>/dev/null; then
        docker restart remnanode >/dev/null 2>&1
    fi
    echo "$(date): Базы успешно обновлены" >> /var/log/xray_update.log
else
    rm -f "$DIR"/*.new
    echo "$(date): Ошибка обновления" >> /var/log/xray_update.log
fi
EOF
    chmod +x "$UPDATE_SCRIPT"

    # Удаляем старую задачу и добавляем новую
    crontab -l 2>/dev/null | grep -v -F -- 'update_assets.sh' | crontab -
    (crontab -l 2>/dev/null; echo "$min $hour * * $days $UPDATE_SCRIPT") | crontab -

    echo -e "\n${GREEN}[✓] Автообновление баз успешно настроено!${NC}"
    echo -e "${CYAN}[i] Расписание: Дни[$days] Время[$(printf "%02d:%02d" "$hour" "$min")]${NC}"
    echo -e "${CYAN}[i] Скрипт: $UPDATE_SCRIPT${NC}"
    pause
}

show_node_instructions() {
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${MAGENTA}  📖 ИНСТРУКЦИЯ: ПОДКЛЮЧЕНИЕ БАЗ И ЛОГОВ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${GRAY} Настройте ноду для работы с базами и логированием.${NC}"
    echo -e "${BLUE}======================================================${NC}\n"
    
    echo -e "${GREEN}${BOLD} [ШАГ 1] Включение Логов (В Панели)${NC}"
    echo -e " Вставьте этот блок в самый верх конфига ноды в панели:\n"
    echo -e "${CYAN} \"log\": {
     \"error\": \"/var/log/remnanode/error.log\",
     \"access\": \"/var/log/remnanode/access.log\",
     \"loglevel\": \"warning\"
   },${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 2] Настройка Docker (${YELLOW}docker-compose.yml${GREEN})${NC}"
    echo -e " В блоке ${CYAN}remnanode -> volumes${NC} добавьте проброс баз и логов:\n"
    echo -e "${CYAN} - /var/log/remnanode:/var/log/remnanode
 - ${BASE_DIR}/xray/share/zapret.dat:/usr/local/bin/zapret.dat
 - ${BASE_DIR}/xray/share/mygeoip.dat:/usr/local/share/xray/mygeoip.dat
 - ${BASE_DIR}/xray/share/mygeosite.dat:/usr/local/share/xray/mygeosite.dat${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 3] Использование в Routing (Примеры)${NC}"
    echo -e " Для ${YELLOW}Антизапрет${NC}:           \"ext:zapret.dat:zapret\""
    echo -e " Для ${YELLOW}Недоступно в РФ${NC}:      \"ext:zapret.dat:zapret-zapad\""
    echo -e " Для ${YELLOW}Roblox${NC}:               \"ext:mygeosite.dat:ROBLOX\""
    echo -e " Для ${YELLOW}Telegram${NC}:             \"ext:mygeosite.dat:TELEGRAM\" и \"ext:mygeoip.dat:TELEGRAM\"\n"

    echo -e "${BLUE}======================================================${NC}"
    echo -e "${YELLOW} 💡 После настройки перезапустите контейнер:${NC}"
    echo -e "${CYAN}    docker compose down && docker compose up -d${NC}"
    echo -e "${BLUE}======================================================${NC}"
    pause
}

menu_node() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🛰️  УПРАВЛЕНИЕ REMNA-NODE & XRAY ASSETS${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 📋 Просмотр Логов (Нода / Nginx / Email)"
        echo -e " ${YELLOW}2.${NC} 📥 Установить базы (Zapret / GeoIP / GeoSite)"
        echo -e " ${YELLOW}3.${NC} ⏰ Настроить автообновление баз (Cron) $(get_node_autoupdate_status)"
        echo -e " ${YELLOW}4.${NC} 📖 Инструкция по подключению к панели"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) menu_logs ;;
            2) install_assets ;;
            3) setup_assets_cron ;;
            4) show_node_instructions ;;
            0) return ;;
        esac
    done
}
