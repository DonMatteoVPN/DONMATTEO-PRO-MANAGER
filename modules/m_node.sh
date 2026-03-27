#!/bin/bash

# Пути
export XRAY_ASSETS_DIR="/opt/remnawave/xray/share"
export UPDATE_SCRIPT="/opt/remnawave/update_assets.sh"

# --- ФУНКЦИИ ЛОГОВ ---
view_node_logs() {
    local log_type=$1
    local email=${2:-""}
    local path=""

    case $log_type in
        "node_err") path="/var/log/remnanode/error.log" ;;
        "node_acc") path="/var/log/remnanode/access.log" ;;
        "nginx_acc") path="/opt/remnawave/nginx_logs/access.log" ;;
        "nginx_err") path="/opt/remnawave/nginx_logs/error.log" ;;
        "nginx_stream") path="/opt/remnawave/nginx_logs/stream_scanners.log" ;;
    esac

    clear
    echo -e "${YELLOW}Просмотр логов: $path${NC}"
    [[ -n "$email" ]] && echo -e "${CYAN}Фильтр по Email: $email${NC}"
    echo -e "${GRAY}Нажмите Ctrl+C для выхода...${NC}\n"

    if [[ -n "$email" ]]; then
        tail -f "$path" | grep --line-buffered "email: $email"
    else
        tail -f "$path"
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
    cd "$XRAY_ASSETS_DIR" || return

    echo -e "${YELLOW}[1/3] Скачивание Zapret (Антизапрет РФ)...${NC}"
    wget -q --show-progress -O zapret.dat https://github.com/kutovoys/ru_gov_zapret/releases/latest/download/zapret.dat
    
    echo -e "${YELLOW}[2/3] Скачивание MyGeoSite (Разблокировки)...${NC}"
    wget -q --show-progress -O mygeosite.dat https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat
    
    echo -e "${YELLOW}[3/3] Скачивание MyGeoIP (Регионы)...${NC}"
    wget -q --show-progress -O mygeoip.dat https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat

    if [[ -s "zapret.dat" && -s "mygeosite.dat" ]]; then
        echo -e "${GREEN}[+] Базы успешно установлены в $XRAY_ASSETS_DIR${NC}"
        docker restart remnanode >/dev/null 2>&1
    else
        echo -e "${RED}[!] Ошибка при скачивании баз.${NC}"
    fi
    pause
}

# --- ПЛАНИРОВЩИК ---
setup_assets_cron() {
    clear
    echo -e "${MAGENTA}=== НАСТРОЙКА АВТООБНОВЛЕНИЯ БАЗ ===${NC}"
    echo -e "Выберите дни недели для обновления:"
    echo -e " 1,3,5 - Пн, Ср, Пт | * - Каждый день | 0 - Вс"
    read -p ">> Ваш выбор: " days
    read -p "В какой час запускать (0-23) [4]: " hour
    hour=${hour:-4}
    
    # Создаем скрипт обновления
    cat << EOF > "$UPDATE_SCRIPT"
#!/bin/bash
DIR="$XRAY_ASSETS_DIR"
wget -q -O \$DIR/zapret.dat.new https://github.com/kutovoys/ru_gov_zapret/releases/latest/download/zapret.dat
wget -q -O \$DIR/mygeosite.dat.new https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat
wget -q -O \$DIR/mygeoip.dat.new https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat

if [ -s "\$DIR/zapret.dat.new" ] && [ -s "\$DIR/mygeosite.dat.new" ]; then
    mv \$DIR/zapret.dat.new \$DIR/zapret.dat
    mv \$DIR/mygeosite.dat.new \$DIR/mygeosite.dat
    mv \$DIR/mygeoip.dat.new \$DIR/mygeoip.dat
    docker restart remnanode
    echo "\$(date): Базы успешно обновлены" >> /var/log/xray_update.log
else
    rm -f \$DIR/*.new
    echo "\$(date): Ошибка обновления" >> /var/log/xray_update.log
fi
EOF
    chmod +x "$UPDATE_SCRIPT"

    # Удаляем старую задачу и добавляем новую
    (crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT") > /tmp/cron_tmp
    echo "0 $hour * * $days $UPDATE_SCRIPT" >> /tmp/cron_tmp
    crontab /tmp/cron_tmp
    rm /tmp/cron_tmp

    echo -e "${GREEN}[+] Расписание установлено: день[$days] час[$hour]${NC}"
    pause
}

show_node_instructions() {
    clear
    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${BOLD}${YELLOW} ⚠️  ИНСТРУКЦИЯ: КАК ПОДКЛЮЧИТЬ БАЗЫ И ЛОГИ К НОДЕ ⚠️${NC}"
    echo -e "${MAGENTA}======================================================================${NC}"
    
    echo -e "${GREEN}${BOLD} [ШАГ 1] Включение Логов (В Панели)${NC}"
    echo -e " Вставьте этот блок в самый верх конфига ноды в панели:"
    echo -e "${CYAN} \"log\": {
    \"error\": \"/var/log/remnanode/error.log\",
    \"access\": \"/var/log/remnanode/access.log\",
    \"loglevel\": \"warning\"
  },${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 2] Настройка Docker (${YELLOW}docker-compose.yml${GREEN})${NC}"
    echo -e " В блоке ${CYAN}remnanode -> volumes${NC} добавьте проброс баз и логов:"
    echo -e "${CYAN} - /var/log/remnanode:/var/log/remnanode
 - /opt/remnawave/xray/share/zapret.dat:/usr/local/bin/zapret.dat
 - /opt/remnawave/xray/share/mygeoip.dat:/usr/local/share/xray/mygeoip.dat
 - /opt/remnawave/xray/share/mygeosite.dat:/usr/local/share/xray/mygeosite.dat${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 3] Использование в Routing (Примеры)${NC}"
    echo -e " Для ${YELLOW}Антизапрет${NC}: \"ext:zapret.dat:zapret\""
    echo -e " Для ${YELLOW}То что недоступно в РФ${NC}: \"ext:zapret.dat:zapret-zapad\""
    echo -e " Для ${YELLOW}Roblox${NC}:      \"ext:mygeosite.dat:ROBLOX\""
    echo -e " Для ${YELLOW}Telegram${NC}:    \"ext:mygeosite.dat:TELEGRAM\" и \"ext:mygeoip.dat:TELEGRAM\"\n"

    echo -e "${MAGENTA}======================================================================${NC}"
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
        echo -e " ${YELLOW}3.${NC} ⏰ Настроить автообновление баз (Cron)"
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
