#!/bin/bash
# Модуль Очистки сервера и Умной Ротации

CLEANER_CONF=$(ensure_module_config "cleaner")
LIMITS_FILE="${CLEANER_CONF}/limits.txt"
[[ ! -f "$LIMITS_FILE" ]] && echo "50M 3" > "$LIMITS_FILE"

silent_cleaner_run() {
    journalctl --vacuum-time=3d >/dev/null 2>&1 || true
    journalctl --vacuum-size=200M >/dev/null 2>&1 || true
    apt-get clean >/dev/null 2>&1 || true
    apt-get autoremove --purge -y >/dev/null 2>&1 || true
    if command -v docker &>/dev/null; then docker system prune -a -f >/dev/null 2>&1 || true; fi
    rm -rf /tmp/* /var/tmp/* ~/.cache/* 2>/dev/null || true
    if command -v snap &>/dev/null; then snap set system refresh.retain=2 2>/dev/null || true; fi
}

get_cleaner_status() {
    if crontab -l 2>/dev/null | grep -q -F -- '--silent-clean'; then echo -e "${GREEN}[ВКЛЮЧЕНО]${NC}"; else echo -e "${RED}[ВЫКЛЮЧЕНО]${NC}"; fi
}

get_free_space() { df -k / | awk 'NR==2 {print $4}'; }

human_readable() {
    local size=$1
    if (( size > 1048576 )); then echo "$(awk "BEGIN {printf \"%.2f\", $size/1048576}") ГБ"
    elif (( size > 1024 )); then echo "$(awk "BEGIN {printf \"%.2f\", $size/1024}") МБ"
    else echo "$size КБ"; fi
}

run_with_diff() {
    local task_name=$1; shift; local space_before=$(get_free_space)
    echo -e "\n${CYAN}======================================================${NC}"
    echo -e "${BOLD} ⚙️ Запуск: $task_name${NC}"
    echo -e "${CYAN}======================================================${NC}"
    "$@"
    local space_after=$(get_free_space); local diff=$(( space_after - space_before ))
    echo -e "\n${MAGENTA}--- Итоги операции ---${NC}"
    if (( diff > 0 )); then echo -e "${GREEN}[✓] Успешно! Освобождено: $(human_readable $diff)${NC}"
    elif (( diff < 0 )); then echo -e "${YELLOW}[!] Свободного места убавилось (система пишет логи)${NC}"
    else echo -e "${BLUE}[i] Мусора не найдено.${NC}"; fi
    pause
}

file_interaction() {
    local FILE=$1; local MODE=$2
    while true; do
        clear; echo -e "${MAGENTA}=== РАБОТА С ФАЙЛОМ ===${NC}"
        echo -e "${CYAN}Файл:${NC} $FILE\n${CYAN}Размер:${NC} $(du -sh "$FILE" | awk '{print $1}')\n"
        echo -e " ${YELLOW}1.${NC} 👀 Посмотреть последние 50 строк (Безопасно)"
        if [[ "$MODE" == "truncate" ]]; then echo -e " ${RED}2.${NC} 🧹 Очистить файл (Сбросить до 0 байт)"; elif [[ "$MODE" == "rm" ]]; then echo -e " ${RED}2.${NC} 🗑️ Удалить файл навсегда"; fi
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " f_ch
        case $f_ch in
            1) clear; echo -e "${YELLOW}Последние 50 строк $FILE:${NC}\n"; if file "$FILE" | grep -qiE "text|empty"; then tail -n 50 "$FILE"; else echo -e "${RED}[!] Это бинарный файл. Вывод текста заблокирован.${NC}"; fi; pause ;;
            2) if [[ "$MODE" == "truncate" ]]; then > "$FILE"; echo -e "${GREEN}[+] Файл очищен!${NC}"; sleep 1; return; elif [[ "$MODE" == "rm" ]]; then rm -f "$FILE"; echo -e "${GREEN}[+] Файл удален!${NC}"; sleep 1; return; else echo -e "${RED}Удаление заблокировано.${NC}"; sleep 2; fi ;;
            0) return ;;
        esac
    done
}

inspect_directory() {
    local DIR=$1; local IS_SAFE_RM=$2 
    while true; do
        clear; echo -e "${MAGENTA}=== ИЗУЧЕНИЕ ДИРЕКТОРИИ ===${NC}"
        echo -e "${CYAN}Текущая папка:${NC} $DIR\n${GRAY}Топ-10 самых тяжелых элементов внутри:${NC}\n"
        du -sh "$DIR"/* 2>/dev/null | sort -hr | head -10 > /tmp/ad_tmp.txt
        if [ ! -s /tmp/ad_tmp.txt ]; then echo -e "  ${GRAY}(Пусто или нет прав доступа)${NC}"; declare -a PATHS=(); else
            local i=1; declare -a PATHS; declare -a TYPES
            while read -r line; do
                local size=$(echo "$line" | awk '{print $1}'); local fpath=$(echo "$line" | cut -f2-); local fname=$(basename "$fpath")
                if [ -d "$fpath" ]; then echo -e "  ${YELLOW}[$i]${NC} 📁 ${CYAN}${size}${NC}\t $fname/"; TYPES[$i]="dir"; else echo -e "  ${YELLOW}[$i]${NC} 📄 ${GREEN}${size}${NC}\t $fname"; TYPES[$i]="file"; fi
                PATHS[$i]="$fpath"; ((i++))
            done < /tmp/ad_tmp.txt; rm -f /tmp/ad_tmp.txt
        fi
        echo -e "\n${BLUE}------------------------------------------------------${NC}"
        [[ "$IS_SAFE_RM" == "block" ]] && echo -e "${RED}⚠️ ВНИМАНИЕ: Ручное удаление сломает систему! Только просмотр.${NC}\n${BLUE}------------------------------------------------------${NC}"
        echo -e " Введите ${YELLOW}НОМЕР${NC} чтобы открыть, или ${CYAN}0${NC} для возврата."
        read -p ">> " choice
        [[ "$choice" == "0" || -z "$choice" ]] && return
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -lt "$i" ] && [ "$choice" -gt 0 ]; then
            local TARGET="${PATHS[$choice]}"; local TYPE="${TYPES[$choice]}"
            [[ "$TYPE" == "dir" ]] && inspect_directory "$TARGET" "$IS_SAFE_RM" || file_interaction "$TARGET" "$IS_SAFE_RM"
        else echo -e "${RED}Неверный ввод.${NC}"; sleep 1; fi
    done
}

analyze_disk() {
    while true; do
        clear; echo -e "${MAGENTA}=== ИНТЕРАКТИВНЫЙ АНАЛИЗАТОР ДИСКА ===${NC}"
        echo -e "${GRAY}Выберите директорию, в которую хотите провалиться:${NC}\n"
        local S_LOG=$(du -sh /var/log 2>/dev/null | awk '{print $1}'); local S_DOCKER=$(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}')
        local S_APT=$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}'); local S_TMP=$(du -sh /tmp 2>/dev/null | awk '{print $1}')
        local S_NGINX=$(du -sh "/opt/remnawave/nginx_logs" 2>/dev/null | awk '{print $1}')
        echo -e " ${YELLOW}1.${NC} 📚 /var/log                 ${CYAN}[${S_LOG:-0}]${NC}  ${GRAY}(Безопасно очищать файлы)${NC}"
        echo -e " ${YELLOW}2.${NC} 🐳 /var/lib/docker          ${CYAN}[${S_DOCKER:-0}]${NC}  ${GRAY}(Только просмотр, удалять ОПАСНО)${NC}"
        echo -e " ${YELLOW}3.${NC} 📦 /var/cache/apt           ${CYAN}[${S_APT:-0}]${NC}  ${GRAY}(Безопасно удалять файлы)${NC}"
        echo -e " ${YELLOW}4.${NC} 🗑️  /tmp                     ${CYAN}[${S_TMP:-0}]${NC}  ${GRAY}(Безопасно удалять файлы)${NC}"
        echo -e " ${YELLOW}5.${NC} 🌐 /opt/remnawave/nginx_logs ${CYAN}[${S_NGINX:-0}]${NC}  ${GRAY}(Логи панели)${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " ad_choice
        case $ad_choice in
            1) inspect_directory "/var/log" "truncate" ;; 2) inspect_directory "/var/lib/docker" "block" ;;
            3) inspect_directory "/var/cache/apt" "rm" ;; 4) inspect_directory "/tmp" "rm" ;; 5) inspect_directory "/opt/remnawave/nginx_logs" "truncate" ;;
            0) return ;;
        esac
    done
}


clean_journal() {
    journalctl --vacuum-time=3d
    journalctl --vacuum-size=200M
}

clean_apt() {
    apt-get clean
    apt-get autoremove --purge -y
}

clean_docker() {
    if command -v docker &>/dev/null; then
        docker system prune -a -f
    else
        echo -e "${YELLOW}[!] Docker не установлен на этом сервере.${NC}"
    fi
}

clean_tmp() {
    rm -rf /tmp/* /var/tmp/* ~/.cache/* 2>/dev/null || true
}

clean_snap() {
    if command -v snap &>/dev/null; then
        snap set system refresh.retain=2 2>/dev/null || true
        while read -r snapname revision; do
            [[ -n "$snapname" ]] && snap remove "$snapname" --revision="$revision"
        done < <(snap list all 2>/dev/null | awk '/disabled/{print $1, $3}')
    else
        echo -e "${YELLOW}[!] Snap не установлен на этом сервере.${NC}"
    fi
}

clean_all_funcs() {
    echo -e "${BLUE}[i] Очистка логов...${NC}"; journalctl --vacuum-time=3d; journalctl --vacuum-size=200M
    echo -e "${BLUE}[i] Очистка APT...${NC}"; apt-get clean; apt-get autoremove --purge -y
    if command -v docker &>/dev/null; then echo -e "${BLUE}[i] Очистка Docker...${NC}"; docker system prune -a -f; fi
    echo -e "${BLUE}[i] Очистка /tmp...${NC}"; rm -rf /tmp/* /var/tmp/* ~/.cache/* 2>/dev/null || true
    if command -v snap &>/dev/null; then echo -e "${BLUE}[i] Очистка Snap...${NC}"; snap set system refresh.retain=2 2>/dev/null || true; while read -r snapname revision; do [[ -n "$snapname" ]] && snap remove "$snapname" --revision="$revision"; done < <(snap list all 2>/dev/null | awk '/disabled/{print $1, $3}'); fi
}

lr_create_rule() {
    local TARGET_PATH=$1; local SIZE=$2; local COUNT=$3
    local SAFE_NAME=$(echo "$TARGET_PATH" | sed -e 's/\//_/g' -e 's/^_//' -e 's/\*//g' -e 's/\.log//g')
    local RULE_FILE="/etc/logrotate.d/don_${SAFE_NAME}"

    cat << EOF > "$RULE_FILE"
${TARGET_PATH} {
    size ${SIZE}
    rotate ${COUNT}
    missingok
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
}

lr_auto_setup() {
    local limits=$(cat "$LIMITS_FILE")
    local D_SIZE=$(echo "$limits" | awk '{print $1}')
    local D_COUNT=$(echo "$limits" | awk '{print $2}')
    
    lr_create_rule "/opt/remnawave/nginx_logs/*.log" "$D_SIZE" "$D_COUNT"
    lr_create_rule "/var/log/remnanode/*.log" "$D_SIZE" "$D_COUNT"
}

lr_clean_dead_rules() {
    for r_file in /etc/logrotate.d/don_*; do
        if [ -f "$r_file" ]; then
            local target=$(head -n 1 "$r_file" | awk '{print $1}' | sed 's/\/\*\.log//')
            if [ ! -d "$target" ]; then
                rm -f "$r_file"
            fi
        fi
    done
}

lr_auto_scan() {
    local limits=$(cat "$LIMITS_FILE")
    local DEF_SIZE=$(echo "$limits" | awk '{print $1}')
    local DEF_COUNT=$(echo "$limits" | awk '{print $2}')
    
    clear; echo -e "${MAGENTA}=== ГЛУБОКОЕ СКАНИРОВАНИЕ ЛОГОВ (РАДАР) ===${NC}"
    echo -e "${GRAY}Ищем ВСЕ .log файлы в безопасных директориях (/opt, /var/log, /root)...${NC}"

    mapfile -t LOG_DIRS < <(
        find /opt /var/log /root -type f -name "*.log" 2>/dev/null | \
        grep -vE "/var/log/(journal|apt|installer|unattended-upgrades|private)" | \
        xargs -r dirname | \
        sort -u
    )

    if [ ${#LOG_DIRS[@]} -eq 0 ]; then
        echo -e "${GREEN}[✓] Диких логов не найдено! Сервер чист.${NC}"; pause; return
    fi

    echo -e "${GREEN}[✓] Найдено ${#LOG_DIRS[@]} папок с логами${NC}\n"
    
    local i=1; declare -a DIRS_ARRAY
    for dir in "${LOG_DIRS[@]}"; do
        if grep -qr "$dir" /etc/logrotate.d/ 2>/dev/null; then
            local STATUS="${GREEN}[УЖЕ В РОТАЦИИ]${NC}"
        else
            local STATUS="${RED}[ДИКИЕ ЛОГИ]${NC}"
        fi
        local SIZE=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        local FILE_COUNT=$(find "$dir" -maxdepth 1 -name "*.log" 2>/dev/null | wc -l)
        echo -e "  ${YELLOW}[$i]${NC} ${CYAN}$dir${NC} (Вес: $SIZE, Файлов: $FILE_COUNT) $STATUS"
        DIRS_ARRAY[$i]=$dir
        ((i++))
    done

    echo -e "\n Введите ${YELLOW}НОМЕР${NC} папки, чтобы взять её под управление."
    echo -e " Введите ${YELLOW}all${NC}, чтобы применить Глобальные настройки ко ВСЕМ диким папкам."
    echo -e " Или ${CYAN}0${NC} для выхода."
    read -p ">> " c_scan
    
    [[ "$c_scan" == "0" || -z "$c_scan" ]] && return

    if [[ "$c_scan" == "all" ]]; then
        echo -e "\n${CYAN}[*] Применяем правила ко всем диким логам...${NC}"
        local added=0
        for dir in "${DIRS_ARRAY[@]}"; do
            if ! grep -qr "$dir" /etc/logrotate.d/ 2>/dev/null; then
                lr_create_rule "${dir}/*.log" "$DEF_SIZE" "$DEF_COUNT"
                ((added++))
            fi
        done
        echo -e "${GREEN}[+] Успешно! Взято под управление: $added папок${NC}"; pause; return
    fi

    if [[ "$c_scan" =~ ^[0-9]+$ ]] && [ "$c_scan" -lt "$i" ] && [ "$c_scan" -gt 0 ]; then
        local TARGET_DIR="${DIRS_ARRAY[$c_scan]}"
        if grep -qr "$TARGET_DIR" /etc/logrotate.d/ 2>/dev/null; then
            echo -e "${YELLOW}Для этой папки уже есть правило. Сначала удалите его в меню управления.${NC}"; sleep 2; return
        fi
        
        echo -e "\n${CYAN}Настройка для: ${TARGET_DIR}/*.log${NC}"
        read -p "Размер (Enter = $DEF_SIZE): " u_size; [[ -z "$u_size" ]] && u_size="$DEF_SIZE"
        read -p "Количество архивов (Enter = $DEF_COUNT): " u_count; [[ -z "$u_count" ]] && u_count="$DEF_COUNT"
        
        lr_create_rule "${TARGET_DIR}/*.log" "$u_size" "$u_count"
        echo -e "${GREEN}[+] Правило создано! Теперь файлы в безопасности.${NC}"; pause
    fi
}

lr_manual_add() {
    local limits=$(cat "$LIMITS_FILE")
    local DEF_SIZE=$(echo "$limits" | awk '{print $1}')
    local DEF_COUNT=$(echo "$limits" | awk '{print $2}')
    
    clear; echo -e "${MAGENTA}=== РУЧНОЕ ДОБАВЛЕНИЕ ПУТИ ===${NC}"
    echo -e "Введите полный путь к файлу лога или папке (с /*.log на конце)."
    read -p ">> Путь: " manual_path
    
    if [[ -n "$manual_path" ]]; then
        read -p "Размер (Enter = $DEF_SIZE): " u_size; [[ -z "$u_size" ]] && u_size="$DEF_SIZE"
        read -p "Количество архивов (Enter = $DEF_COUNT): " u_count; [[ -z "$u_count" ]] && u_count="$DEF_COUNT"
        lr_create_rule "$manual_path" "$u_size" "$u_count"
        echo -e "${GREEN}[+] Правило создано!${NC}"; pause
    fi
}

lr_manage_rules() {
    while true; do
        clear; echo -e "${MAGENTA}=== АКТИВНЫЕ ПРАВИЛА РОТАЦИИ ===${NC}"
        local i=1; declare -a RULE_FILES
        
        for r_file in /etc/logrotate.d/don_*; do
            if [ -f "$r_file" ]; then
                local target=$(head -n 1 "$r_file" | awk '{print $1}')
                local size=$(grep "size" "$r_file" | awk '{print $2}' || echo "?")
                local count=$(grep "rotate" "$r_file" | awk '{print $2}' || echo "?")
                echo -e "  ${YELLOW}[$i]${NC} Папка: ${CYAN}$target${NC} | Лимит: ${GREEN}$size${NC} | Храним: ${GREEN}$count шт.${NC}"
                RULE_FILES[$i]="$r_file"
                ((i++))
            fi
        done
        
        if [ $i -eq 1 ]; then echo -e "  ${GRAY}(Правил не найдено)${NC}"; pause; return; fi
        
        echo -e "\n Введите ${YELLOW}НОМЕР${NC} правила для УДАЛЕНИЯ"
        echo -e " Введите ${RED}all${NC} чтобы удалить ВСЕ правила"
        echo -e " Или ${CYAN}0${NC} для выхода."
        read -p ">> " d_ch
        
        [[ "$d_ch" == "0" || -z "$d_ch" ]] && return
        
        if [[ "$d_ch" == "all" ]]; then
            echo -e "\n${RED}${BOLD}⚠️  ВНИМАНИЕ! Вы собираетесь удалить ВСЕ правила ротации!${NC}"
            read -p "Подтвердите удаление (введите YES): " confirm
            if [[ "$confirm" == "YES" ]]; then
                for r_file in /etc/logrotate.d/don_*; do
                    [ -f "$r_file" ] && rm -f "$r_file"
                done
                echo -e "${GREEN}[+] Все правила удалены!${NC}"; sleep 2
                return
            else
                echo -e "${YELLOW}[!] Отменено.${NC}"; sleep 1
            fi
        elif [[ "$d_ch" =~ ^[0-9]+$ ]] && [ "$d_ch" -lt "$i" ] && [ "$d_ch" -gt 0 ]; then
            rm -f "${RULE_FILES[$d_ch]}"
            echo -e "${GREEN}Правило удалено!${NC}"; sleep 1
        fi
    done
}

lr_set_global_limits() {
    local limits=$(cat "$LIMITS_FILE")
    local current_size=$(echo "$limits" | awk '{print $1}')
    local current_count=$(echo "$limits" | awk '{print $2}')
    
    clear
    echo -e "${MAGENTA}=== ГЛОБАЛЬНЫЕ ЛИМИТЫ РОТАЦИИ ===${NC}"
    echo -e "${GRAY}Настройте размер и количество архивов для новых правил.${NC}\n"
    
    echo -e " ${CYAN}Текущие настройки:${NC}"
    echo -e "   Размер файла: ${GREEN}${current_size}${NC}"
    echo -e "   Количество архивов: ${GREEN}${current_count} шт.${NC}\n"
    
    read -p "Введите новый размер (например, 100M или 1G) [Enter = без изменений]: " in_size
    [[ -n "$in_size" ]] && current_size="$in_size"
    
    read -p "Введите количество хранимых архивов (например, 5) [Enter = без изменений]: " in_count
    [[ "$in_count" =~ ^[0-9]+$ ]] && current_count="$in_count"
    
    echo -e "\n${GREEN}[+] Новые глобальные лимиты: ${current_size} / ${current_count} шт.${NC}"
    
    local existing_rules=$(ls /etc/logrotate.d/don_* 2>/dev/null | wc -l)
    
    if [ "$existing_rules" -gt 0 ]; then
        echo -e "\n${YELLOW}[?] Найдено ${existing_rules} существующих правил ротации.${NC}"
        echo -e "${YELLOW}    Применить новые лимиты ко ВСЕМ существующим правилам?${NC}"
        read -p "    (y/n): " apply_to_all
        
        if [[ "$apply_to_all" =~ ^[yYдД]$ ]]; then
            echo -e "\n${CYAN}[*] Применяем новые лимиты ко всем правилам...${NC}"
            local updated=0
            for r_file in /etc/logrotate.d/don_*; do
                if [ -f "$r_file" ]; then
                    sed -i "s/size .*/size $current_size/" "$r_file"
                    sed -i "s/rotate .*/rotate $current_count/" "$r_file"
                    ((updated++))
                fi
            done
            echo -e "${GREEN}[+] Обновлено правил: $updated${NC}"
        else
            echo -e "${CYAN}[i] Новые лимиты будут применяться только к новым правилам.${NC}"
        fi
    fi
    
    echo "$current_size $current_count" > "$LIMITS_FILE"
}

manage_logrotate() {
    lr_clean_dead_rules
    
    while true; do
        local limits=$(cat "$LIMITS_FILE")
        local D_SIZE=$(echo "$limits" | awk '{print $1}')
        local D_COUNT=$(echo "$limits" | awk '{print $2}')
        
        clear
        echo -e "${MAGENTA}=== УМНАЯ РОТАЦИЯ ЛОГОВ (ЛОКАТОР) ===${NC}"
        echo -e "${GRAY}Автоматически находит, архивирует и удаляет старые логи.${NC}"
        
        local RULES_COUNT=$(ls /etc/logrotate.d/don_* 2>/dev/null | wc -l)
        echo -e "\n 📊 Активных правил под вашим управлением: ${GREEN}${RULES_COUNT}${NC}\n"

        echo -e " ${GREEN}1.${NC} 🔍 Сканировать сервер на 'дикие' логи (Автопоиск)"
        echo -e " ${YELLOW}2.${NC} ➕ Вписать путь к логам вручную"
        echo -e " ${YELLOW}3.${NC} 📋 Управление активными правилами (Просмотр / Удаление)"
        echo -e " ${YELLOW}4.${NC} ⚙️ Задать глобальные лимиты (сейчас: ${CYAN}${D_SIZE} / ${D_COUNT} шт.${NC})"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${MAGENTA}5.${NC} 🚀 Принудительно запустить ротацию"
        echo -e " ${CYAN}0.${NC} ↩️ Назад"

        read -p ">> " lr_choice
        case $lr_choice in
            1) lr_auto_scan ;;
            2) lr_manual_add ;;
            3) lr_manage_rules ;;
            4) lr_set_global_limits; pause ;;
            5) echo -e "\n${CYAN}[*] Запуск принудительной ротации...${NC}"; logrotate -f /etc/logrotate.conf; echo -e "${GREEN}[+] Ротация выполнена! Проверьте архивы.${NC}"; pause ;;
            0) return ;;
        esac
    done
}

setup_cron() {
    clear; echo -e "${MAGENTA}=== ИНТЕРАКТИВНАЯ НАСТРОЙКА АВТООЧИСТКИ ===${NC}"
    echo -e "${GRAY}Скрипт будет сам запускать тихую очистку по вашему расписанию.${NC}\n"

    local existing_job=$(crontab -l 2>/dev/null | grep -F -- '--silent-clean')
    if [[ -n "$existing_job" ]]; then
        local e_min=$(echo "$existing_job" | awk '{print $1}')
        local e_hour=$(echo "$existing_job" | awk '{print $2}')
        local e_dow=$(echo "$existing_job" | awk '{print $5}')
        
        echo -e " ${GREEN}✅ Текущее активное расписание:${NC}"
        echo -e "    Дни недели: ${CYAN}$e_dow${NC} | Время запуска: ${CYAN}$(printf "%02d:%02d" "$e_hour" "$e_min" 2>/dev/null || echo "$e_hour:$e_min")${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${YELLOW}1.${NC} 🔄 Изменить расписание"
        echo -e " ${RED}2.${NC} 🗑️  Отключить и удалить автоочистку"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " action
        case $action in
            2) crontab -l 2>/dev/null | grep -v -F -- '--silent-clean' | crontab -; echo -e "\n${GREEN}[+] Автоочистка успешно отключена!${NC}"; pause; return ;;
            0) return ;;
            1) echo -e "\n${CYAN}--- Настройка нового расписания ---${NC}" ;;
            *) return ;;
        esac
    fi
    
    echo -e "Выберите дни недели для запуска:"
    echo -e " 1,3,5 - Пн, Ср, Пт | * - Каждый день"
    read -p ">> Ваш выбор: " c_day
    [[ ! "$c_day" =~ ^([0-6\*](,[0-6])*)$ ]] && { echo -e "${YELLOW}Неверный формат. Установлено: Каждый день (*)${NC}"; c_day="*"; }
    [[ -z "$c_day" ]] && c_day="*"
    
    echo -e "\nВведите ЧАС запуска (от 0 до 23):"
    read -p ">> " c_hour
    [[ ! "$c_hour" =~ ^([0-1]?[0-9]|2[0-3])$ ]] && { echo -e "${YELLOW}Неверный ввод. Установлено: 04${NC}"; c_hour="4"; }
    
    echo -e "\nВведите МИНУТЫ (от 0 до 59):"
    read -p ">> " c_min
    [[ ! "$c_min" =~ ^([0-5]?[0-9])$ ]] && { echo -e "${YELLOW}Неверный ввод. Установлено: 00${NC}"; c_min="0"; }

    local job="$c_min $c_hour * * $c_day /usr/local/bin/don --silent-clean > /dev/null 2>&1"
    
    crontab -l 2>/dev/null | grep -v -F -- '--silent-clean' | crontab -
    (crontab -l 2>/dev/null; echo "$job") | crontab -
    
    echo -e "\n${GREEN}[✓] Автоочистка успешно настроена!${NC}"
    pause
}

get_logrotate_status() {
    local rules_count=$(ls /etc/logrotate.d/don_* 2>/dev/null | wc -l)
    if [ "$rules_count" -gt 0 ]; then echo -e "${GREEN}[Активно: ${rules_count} правил]${NC}"; else echo -e "${RED}[НЕ НАСТРОЕНО]${NC}"; fi
}

menu_cleaner() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🧹 ОЧИСТКА СЕРВЕРА (МЕСТО НА ДИСКЕ)${NC}"
        echo -e "${GRAY} Безопасное удаление системного мусора и логов.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " 💾 Текущее свободное место: ${GREEN}$(human_readable $(get_free_space))${NC}\n"
        echo -e " ${GREEN}1.${NC} 🧹 Полная уборка"
        echo -e " ${YELLOW}2.${NC} 📦 Очистить кэш APT"
        echo -e " ${YELLOW}3.${NC} 📚 Очистить системные логи"
        echo -e " ${YELLOW}4.${NC} 🐳 Очистить мусор Docker"
        echo -e " ${YELLOW}5.${NC} 🗑️ Очистить временные файлы (/tmp)"
        echo -e " ${YELLOW}6.${NC} 🧩 Очистить старые Snap пакеты"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}7.${NC} 🔍 Интерактивный Анализатор Диска"
        echo -e " ${MAGENTA}8.${NC} ⏰ Настроить Автоочистку $(get_cleaner_status)"
        echo -e " ${MAGENTA}9.${NC} 🔄 Умная Ротация логов $(get_logrotate_status)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) run_with_diff "ПОЛНАЯ ОЧИСТКА СЕРВЕРА" clean_all_funcs ;;
            2) run_with_diff "ОЧИСТКА КЭША APT" clean_apt ;; 3) run_with_diff "ОЧИСТКА ЖУРНАЛОВ" clean_journal ;;
            4) run_with_diff "ОЧИСТКА DOCKER" clean_docker ;; 5) run_with_diff "ОЧИСТКА /TMP" clean_tmp ;;
            6) run_with_diff "ОЧИСТКА SNAP" clean_snap ;; 7) analyze_disk ;; 8) setup_cron ;; 9) manage_logrotate ;; 0) return ;;
        esac
    done
}
