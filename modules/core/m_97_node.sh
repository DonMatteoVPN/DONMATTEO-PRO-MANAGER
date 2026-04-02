#!/bin/bash
# =============================================================================
# МОДУЛЬ НОДЫ: m_97_node.sh
# =============================================================================
# Управление Remna-Node, логами Nginx и базами Xray Assets (Zapret/GeoIP).
# =============================================================================

export XRAY_ASSETS_DIR="/opt/remnawave/xray/share"
export UPDATE_SCRIPT="${BASE_DIR}/update_assets.sh"
export NGINX_LOGS_DIR="${BASE_DIR}/nginx_logs"

NODE_CONF=$(ensure_module_config "node")
ZAPRET_URL_FILE="${NODE_CONF}/zapret_url.txt"
GEOSITE_URL_FILE="${NODE_CONF}/geosite_url.txt"
GEOIP_URL_FILE="${NODE_CONF}/geoip_url.txt"

[[ ! -f "$ZAPRET_URL_FILE" ]] && echo "https://github.com/kutovoys/ru_gov_zapret/releases/latest/download/zapret.dat" > "$ZAPRET_URL_FILE"
[[ ! -f "$GEOSITE_URL_FILE" ]] && echo "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat" > "$GEOSITE_URL_FILE"
[[ ! -f "$GEOIP_URL_FILE" ]] && echo "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat" > "$GEOIP_URL_FILE"

get_node_autoupdate_status() {
    if crontab -l 2>/dev/null | grep -q "update_assets.sh"; then 
        echo -e "${GREEN}[ВКЛЮЧЕНО]${NC}"
    else 
        echo -e "${RED}[ВЫКЛЮЧЕНО]${NC}"
    fi
}

view_node_logs() {
    local log_type="$1"
    local email="${2:-}"
    local path=""
    
    case "$log_type" in
        "node_err")    path="/var/log/remnanode/error.log" ;;
        "node_acc")    path="/var/log/remnanode/access.log" ;;
        "nginx_acc")   path="${NGINX_LOGS_DIR}/access.log" ;;
        "nginx_err")   path="${NGINX_LOGS_DIR}/error.log" ;;
        "nginx_stream") path="${NGINX_LOGS_DIR}/stream_scanners.log" ;;
    esac

    clear
    ui_header "📄" "ПРОСМОТР ЛОГОВ"
    echo -e " ${CYAN}Файл:${NC} $path"
    [[ -n "$email" ]] && echo -e " ${CYAN}Фильтр по Email:${NC} $email"
    echo -e " ${YELLOW}Нажмите Ctrl+C для выхода...${NC}"
    ui_sep

    if [[ -n "$email" ]]; then 
        tail -f "$path" 2>/dev/null | grep --line-buffered "email: $email" || echo -e "${RED}Лог пуст или недоступен.${NC}"
    else 
        tail -f "$path" 2>/dev/null || echo -e "${RED}Лог пуст или недоступен.${NC}"
    fi
}

menu_logs() {
    while true; do
        clear
        ui_header "📋" "ЦЕНТР УПРАВЛЕНИЯ ЛОГАМИ"
        
        echo -e " ${YELLOW}1.${NC} Нода: Ошибки (Error Log)"
        echo -e " ${YELLOW}2.${NC} Нода: Трафик (Access Log)"
        echo -e " ${YELLOW}3.${NC} Нода: Поиск по EMAIL пользователя"
        ui_sep
        echo -e " ${GREEN}4.${NC} Nginx: Доступ (Сайт / XHTTP)"
        echo -e " ${GREEN}5.${NC} Nginx: Ошибки"
        echo -e " ${GREEN}6.${NC} Nginx: Стрикер (TCP Сканеры)"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1) view_node_logs "node_err" ;; 
            2) view_node_logs "node_acc" ;;
            3) 
                local em; em=$(ui_input "Введите email пользователя")
                [[ -n "$em" ]] && view_node_logs "node_acc" "$em" 
                ;;
            4) view_node_logs "nginx_acc" ;; 
            5) view_node_logs "nginx_err" ;; 
            6) view_node_logs "nginx_stream" ;;
            0) return ;;
        esac
    done
}

edit_asset_urls() {
    while true; do
        clear
        ui_header "🔗" "ИСТОЧНИКИ БАЗ ДАННЫХ (URL)"
        echo -e " ${GRAY}Здесь вы можете заменить тяжелые базы на LITE-версии.${NC}\n"
        
        echo -e " ${YELLOW}1.${NC} Zapret URL:  ${CYAN}$(cat "$ZAPRET_URL_FILE" | cut -c 1-60)...${NC}"
        echo -e " ${YELLOW}2.${NC} GeoSite URL: ${CYAN}$(cat "$GEOSITE_URL_FILE" | cut -c 1-60)...${NC}"
        echo -e " ${YELLOW}3.${NC} GeoIP URL:   ${CYAN}$(cat "$GEOIP_URL_FILE" | cut -c 1-60)...${NC}"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -rp ">> Выберите номер для изменения: " ch < /dev/tty
        case "$ch" in
            1) 
                local n_url; n_url=$(ui_input "Новый URL для Zapret")
                [[ -n "$n_url" ]] && echo "$n_url" > "$ZAPRET_URL_FILE" && echo -e "${GREEN}Сохранено!${NC}" && sleep 1
                ;;
            2) 
                local n_url; n_url=$(ui_input "Новый URL для GeoSite")
                [[ -n "$n_url" ]] && echo "$n_url" > "$GEOSITE_URL_FILE" && echo -e "${GREEN}Сохранено!${NC}" && sleep 1
                ;;
            3) 
                local n_url; n_url=$(ui_input "Новый URL для GeoIP")
                [[ -n "$n_url" ]] && echo "$n_url" > "$GEOIP_URL_FILE" && echo -e "${GREEN}Сохранено!${NC}" && sleep 1
                ;;
            0) return ;;
        esac
    done
}

install_assets() {
    echo -e "\n${CYAN}[*] Установка баз данных (GeoSite / GeoIP / Zapret)...${NC}"
    mkdir -p "$XRAY_ASSETS_DIR"
    
    # Удаляем старые базы если это папки
    for item in "$XRAY_ASSETS_DIR/zapret.dat" "$XRAY_ASSETS_DIR/mygeosite.dat" "$XRAY_ASSETS_DIR/mygeoip.dat"; do
        if [[ -d "$item" ]]; then rm -rf "$item"; fi
    done
    
    cd "$XRAY_ASSETS_DIR" || return

    local Z_URL; Z_URL=$(cat "$ZAPRET_URL_FILE")
    local GS_URL; GS_URL=$(cat "$GEOSITE_URL_FILE")
    local GI_URL; GI_URL=$(cat "$GEOIP_URL_FILE")

    echo -e "${YELLOW}[1/3] Скачивание Zapret...${NC}"
    smart_curl "$Z_URL" "zapret.dat.tmp" 60
    [[ -s "zapret.dat.tmp" ]] && mv "zapret.dat.tmp" "zapret.dat" || rm -f "zapret.dat.tmp"
    
    echo -e "${YELLOW}[2/3] Скачивание MyGeoSite...${NC}"
    smart_curl "$GS_URL" "mygeosite.dat.tmp" 60
    [[ -s "mygeosite.dat.tmp" ]] && mv "mygeosite.dat.tmp" "mygeosite.dat" || rm -f "mygeosite.dat.tmp"
    
    echo -e "${YELLOW}[3/3] Скачивание MyGeoIP...${NC}"
    smart_curl "$GI_URL" "mygeoip.dat.tmp" 60
    [[ -s "mygeoip.dat.tmp" ]] && mv "mygeoip.dat.tmp" "mygeoip.dat" || rm -f "mygeoip.dat.tmp"

    if [[ -s "zapret.dat" && -s "mygeosite.dat" && -s "mygeoip.dat" ]]; then
        log_audit "NODE" "Установлены базы Xray (Zapret/GeoSite/GeoIP)"
        echo -e "\n${GREEN}[+] Базы успешно установлены в $XRAY_ASSETS_DIR${NC}"
        
        if command -v docker >/dev/null 2>&1; then
            echo -e "${CYAN}[*] Перезапуск ноды для применения изменений...${NC}"
            if docker restart remnanode >/dev/null 2>&1; then
                echo -e "${GREEN}[+] Нода перезапущена.${NC}"
            else
                echo -e "${YELLOW}[!] Контейнер remnanode не найден или не запущен.${NC}"
            fi
        fi
    else
        log_audit "NODE_ERR" "Не удалось скачать базы Xray (Zapret/GeoSite/GeoIP)"
        echo -e "\n${RED}[!] Ошибка при скачивании баз. Проверьте сеть или зеркала.${NC}"
    fi
    ui_pause
}

setup_assets_cron() {
    clear
    ui_header "⏰" "АВТООБНОВЛЕНИЕ БАЗ"
    echo -e " ${GRAY}Скрипт будет автоматически обновлять базы по вашему расписанию.${NC}\n"
    
    local existing_job; existing_job=$(crontab -l 2>/dev/null | grep -F -- 'update_assets.sh')
    if [[ -n "$existing_job" ]]; then
        local e_min; e_min=$(echo "$existing_job" | awk '{print $1}')
        local e_hour; e_hour=$(echo "$existing_job" | awk '{print $2}')
        local e_dow; e_dow=$(echo "$existing_job" | awk '{print $5}')
        
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
        
        echo -e " ${GREEN}✅ Текущее расписание:${NC}"
        echo -e "    Дни недели: ${CYAN}${days_text}${NC} | Время: ${CYAN}$(printf "%02d:%02d" "$e_hour" "$e_min" 2>/dev/null || echo "$e_hour:$e_min")${NC}"
        ui_sep
        echo -e " ${YELLOW}1.${NC} 🔄 Изменить расписание"
        echo -e " ${RED}2.${NC} 🗑️  Отключить и удалить автообновление"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -rp ">> " action < /dev/tty
        case "$action" in
            2) 
                crontab -l 2>/dev/null | grep -v -F -- 'update_assets.sh' | crontab -
                log_audit "CRON" "Автообновление баз отключено"
                echo -e "\n${GREEN}[+] Автообновление баз успешно отключено!${NC}"
                ui_pause; return 
                ;;
            0) return ;;
            1) echo -e "\n${CYAN}--- Настройка нового расписания ---${NC}" ;;
            *) return ;;
        esac
    fi
    
    local days; days=$(ui_input "Дни (1,3,5=Пн,Ср,Пт | *=Каждый день | 0,6=Сб,Вс)" "*")
    local hour; hour=$(ui_input "Час запуска (0-23)" "4")
    local min; min=$(ui_input "Минуты (0-59)" "0")
    
    local UPDATE_SH="${BASE_DIR}/update_assets.sh"
    
    # Генерируем скрипт обновления
    cat << EOF > "$UPDATE_SH"
#!/bin/bash
DIR="/opt/remnawave/xray/share"
mkdir -p "\$DIR"

Z_URL="\$(cat "${ZAPRET_URL_FILE}")"
GS_URL="\$(cat "${GEOSITE_URL_FILE}")"
GI_URL="\$(cat "${GEOIP_URL_FILE}")"

for item in "\$DIR/zapret.dat" "\$DIR/mygeosite.dat" "\$DIR/mygeoip.dat"; do
    [[ -d "\$item" ]] && rm -rf "\$item"
done

curl -fsSLk --connect-timeout 10 --max-time 60 "\$Z_URL" -o "\$DIR/zapret.dat.new" 2>/dev/null || true
curl -fsSLk --connect-timeout 10 --max-time 60 "\$GS_URL" -o "\$DIR/mygeosite.dat.new" 2>/dev/null || true
curl -fsSLk --connect-timeout 10 --max-time 60 "\$GI_URL" -o "\$DIR/mygeoip.dat.new" 2>/dev/null || true

if [[ -s "\$DIR/zapret.dat.new" && -s "\$DIR/mygeosite.dat.new" && -s "\$DIR/mygeoip.dat.new" ]]; then
    mv -f "\$DIR/zapret.dat.new" "\$DIR/zapret.dat"
    mv -f "\$DIR/mygeosite.dat.new" "\$DIR/mygeosite.dat"
    mv -f "\$DIR/mygeoip.dat.new" "\$DIR/mygeoip.dat"
    if command -v docker >/dev/null 2>&1; then docker restart remnanode >/dev/null 2>&1 || true; fi
    echo "\$(date): Базы успешно обновлены" >> /var/log/xray_update.log
else
    rm -f "\$DIR"/*.new
    echo "\$(date): Ошибка обновления баз" >> /var/log/xray_update.log
fi
EOF
    chmod +x "$UPDATE_SH"

    local job="$min $hour * * $days $UPDATE_SH"
    crontab -l 2>/dev/null | grep -v -F -- 'update_assets.sh' | crontab -
    (crontab -l 2>/dev/null; echo "$job") | crontab -

    log_audit "CRON" "Автообновление баз включено ($job)"
    echo -e "\n${GREEN}[✓] Автообновление баз успешно настроено!${NC}"
    ui_pause
}

menu_node() {
    while true; do
        clear
        ui_header "🛰️" "УПРАВЛЕНИЕ REMNA-NODE И XRAY"
        echo -e " ${GRAY}Управление логами, базами данных и автообновлением.${NC}"
        
        echo -e " ${GREEN}1.${NC} 📋 Просмотр Логов (Нода / Nginx / Email)"
        echo -e " ${GREEN}2.${NC} 📥 Обновить базы Xray вручную (Zapret / GeoIP / GeoSite)"
        echo -e " ${GREEN}3.${NC} ⏰ Настроить автообновление баз (Cron) $(get_node_autoupdate_status)"
        ui_sep
        echo -e " ${YELLOW}4.${NC} 🔗 Изменить ссылки на базы (URL)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -rp ">> " choice < /dev/tty
        case "$choice" in
            1) menu_logs ;;
            2) install_assets ;;
            3) setup_assets_cron ;;
            4) edit_asset_urls ;;
            0) return ;;
        esac
    done
}