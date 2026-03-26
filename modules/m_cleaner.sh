#!/bin/bash

silent_cleaner_run() {
    journalctl --vacuum-time=3d >/dev/null 2>&1 || true
    journalctl --vacuum-size=200M >/dev/null 2>&1 || true
    apt-get clean >/dev/null 2>&1 || true
    apt-get autoremove --purge -y >/dev/null 2>&1 || true
    if command -v docker &>/dev/null; then docker system prune -a -f >/dev/null 2>&1 || true; fi
    rm -rf /tmp/* /var/tmp/* ~/.cache/* 2>/dev/null || true
    if command -v snap &>/dev/null; then snap set system refresh.retain=2 2>/dev/null || true; fi
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

# ======================================================================
# ИНТЕРАКТИВНЫЙ БРАУЗЕР ФАЙЛОВ И ПАПОК
# ======================================================================

file_interaction() {
    local FILE=$1
    local MODE=$2
    
    while true; do
        clear
        echo -e "${MAGENTA}=== РАБОТА С ФАЙЛОМ ===${NC}"
        echo -e "${CYAN}Файл:${NC} $FILE"
        echo -e "${CYAN}Размер:${NC} $(du -sh "$FILE" | awk '{print $1}')\n"
        
        echo -e " ${YELLOW}1.${NC} 👀 Посмотреть последние 50 строк (Безопасно)"
        
        if [[ "$MODE" == "truncate" ]]; then
            echo -e " ${RED}2.${NC} 🧹 Очистить файл (Сбросить до 0 байт, безопасно для логов)"
        elif [[ "$MODE" == "rm" ]]; then
            echo -e " ${RED}2.${NC} 🗑️ Удалить файл навсегда"
        fi
        
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -p ">> " f_ch
        case $f_ch in
            1) 
                clear
                echo -e "${YELLOW}Последние 50 строк файла $FILE:${NC}\n"
                if file "$FILE" | grep -qiE "text|empty"; then
                    tail -n 50 "$FILE"
                else
                    echo -e "${RED}[!] Это бинарный файл или архив. Вывод текста невозможен, чтобы не сломать консоль.${NC}"
                fi
                pause
                ;;
            2)
                if [[ "$MODE" == "truncate" ]]; then
                    > "$FILE"
                    echo -e "${GREEN}[+] Файл очищен!${NC}"; sleep 1; return
                elif [[ "$MODE" == "rm" ]]; then
                    rm -f "$FILE"
                    echo -e "${GREEN}[+] Файл удален!${NC}"; sleep 1; return
                else
                    echo -e "${RED}Удаление заблокировано для вашей безопасности.${NC}"; sleep 2
                fi
                ;;
            0) return ;;
        esac
    done
}

inspect_directory() {
    local DIR=$1
    local IS_SAFE_RM=$2 # Режимы: "truncate", "rm", "block"
    
    while true; do
        clear
        echo -e "${MAGENTA}=== ИЗУЧЕНИЕ ДИРЕКТОРИИ ===${NC}"
        echo -e "${CYAN}Текущая папка:${NC} $DIR"
        echo -e "${GRAY}Топ-10 самых тяжелых элементов внутри:${NC}\n"
        
        # Получаем список файлов и папок с размерами
        du -sh "$DIR"/* 2>/dev/null | sort -hr | head -10 > /tmp/ad_tmp.txt
        
        if [ ! -s /tmp/ad_tmp.txt ]; then
            echo -e "  ${GRAY}(Пусто или нет прав доступа)${NC}"
            declare -a PATHS=()
        else
            local i=1
            declare -a PATHS
            declare -a TYPES
            while read -r line; do
                local size=$(echo "$line" | awk '{print $1}')
                local fpath=$(echo "$line" | cut -f2-)
                local fname=$(basename "$fpath")
                
                if [ -d "$fpath" ]; then
                    echo -e "  ${YELLOW}[$i]${NC} 📁 ${CYAN}${size}${NC}\t $fname/"
                    TYPES[$i]="dir"
                else
                    echo -e "  ${YELLOW}[$i]${NC} 📄 ${GREEN}${size}${NC}\t $fname"
                    TYPES[$i]="file"
                fi
                PATHS[$i]="$fpath"
                ((i++))
            done < /tmp/ad_tmp.txt
            rm -f /tmp/ad_tmp.txt
        fi
        
        echo -e "\n${BLUE}------------------------------------------------------${NC}"
        if [[ "$IS_SAFE_RM" == "block" ]]; then
            echo -e "${RED}⚠️ ВНИМАНИЕ: Ручное удаление файлов здесь сломает систему!${NC}"
            echo -e "${RED}Разрешен только просмотр папок.${NC}"
            echo -e "${BLUE}------------------------------------------------------${NC}"
        fi
        
        echo -e " Введите ${YELLOW}НОМЕР${NC} чтобы открыть, или ${CYAN}0${NC} для возврата."
        read -p ">> " choice
        
        if [[ "$choice" == "0" || -z "$choice" ]]; then return; fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -lt "$i" ] && [ "$choice" -gt 0 ]; then
            local TARGET="${PATHS[$choice]}"
            local TYPE="${TYPES[$choice]}"
            
            if [[ "$TYPE" == "dir" ]]; then
                inspect_directory "$TARGET" "$IS_SAFE_RM"
            else
                file_interaction "$TARGET" "$IS_SAFE_RM"
            fi
        else
            echo -e "${RED}Неверный ввод.${NC}"; sleep 1
        fi
    done
}

analyze_disk() {
    while true; do
        clear; echo -e "${MAGENTA}=== ИНТЕРАКТИВНЫЙ АНАЛИЗАТОР ДИСКА ===${NC}"
        echo -e "${GRAY}Выберите директорию, в которую хотите провалиться:${NC}\n"
        
        local S_LOG=$(du -sh /var/log 2>/dev/null | awk '{print $1}')
        local S_DOCKER=$(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}')
        local S_APT=$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')
        local S_TMP=$(du -sh /tmp 2>/dev/null | awk '{print $1}')
        
        echo -e " ${YELLOW}1.${NC} 📚 /var/log         ${CYAN}[${S_LOG:-0}]${NC}  ${GRAY}(Безопасно очищать файлы)${NC}"
        echo -e " ${YELLOW}2.${NC} 🐳 /var/lib/docker  ${CYAN}[${S_DOCKER:-0}]${NC}  ${GRAY}(Только просмотр, удалять ОПАСНО)${NC}"
        echo -e " ${YELLOW}3.${NC} 📦 /var/cache/apt   ${CYAN}[${S_APT:-0}]${NC}  ${GRAY}(Безопасно удалять файлы)${NC}"
        echo -e " ${YELLOW}4.${NC} 🗑️  /tmp             ${CYAN}[${S_TMP:-0}]${NC}  ${GRAY}(Безопасно удалять файлы)${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -p ">> " ad_choice
        case $ad_choice in
            1) inspect_directory "/var/log" "truncate" ;;
            2) inspect_directory "/var/lib/docker" "block" ;;
            3) inspect_directory "/var/cache/apt" "rm" ;;
            4) inspect_directory "/tmp" "rm" ;;
            0) return ;;
        esac
    done
}

# ======================================================================

clean_all_funcs() {
    echo -e "${BLUE}[i] Очистка логов...${NC}"; journalctl --vacuum-time=3d; journalctl --vacuum-size=200M
    echo -e "${BLUE}[i] Очистка APT...${NC}"; apt-get clean; apt-get autoremove --purge -y
    if command -v docker &>/dev/null; then echo -e "${BLUE}[i] Очистка Docker...${NC}"; docker system prune -a -f; fi
    echo -e "${BLUE}[i] Очистка /tmp...${NC}"; rm -rf /tmp/* /var/tmp/* ~/.cache/* 2>/dev/null || true
    if command -v snap &>/dev/null; then echo -e "${BLUE}[i] Очистка Snap...${NC}"; snap set system refresh.retain=2 2>/dev/null || true; while read -r snapname revision; do [[ -n "$snapname" ]] && snap remove "$snapname" --revision="$revision"; done < <(snap list all 2>/dev/null | awk '/disabled/{print $1, $3}'); fi
}

setup_cron() {
    clear; echo -e "${MAGENTA}=== ИНТЕРАКТИВНАЯ НАСТРОЙКА АВТООЧИСТКИ ===${NC}"
    echo -e "${GRAY}Скрипт будет сам запускать тихую очистку по вашему расписанию.${NC}\n"

    local existing_job=$(crontab -l 2>/dev/null | grep '/usr/local/bin/don --silent-clean')
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
            2) crontab -l 2>/dev/null | grep -v -- '--silent-clean' | crontab -; echo -e "\n${GREEN}[+] Автоочистка успешно отключена!${NC}"; pause; return ;;
            0) return ;;
            1) echo -e "\n${CYAN}--- Настройка нового расписания ---${NC}" ;;
            *) return ;;
        esac
    fi
    
    echo -e "Выберите дни недели для запуска:"
    echo -e " ${GRAY}(Можно указать несколько через запятую, например: 1,3,5)${NC}"
    echo -e " 1 - Понедельник   5 - Пятница"
    echo -e " 2 - Вторник       6 - Суббота"
    echo -e " 3 - Среда         0 - Воскресенье"
    echo -e " 4 - Четверг       * - Каждый день"
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
    
    crontab -l 2>/dev/null | grep -v -- '--silent-clean' | crontab -
    (crontab -l 2>/dev/null; echo "$job") | crontab -
    
    echo -e "\n${GREEN}[✓] Автоочистка успешно настроена!${NC}"
    echo -e "Время: ${CYAN}$(printf "%02d:%02d" "$c_hour" "$c_min" 2>/dev/null || echo "$c_hour:$c_min")${NC}, Дни недели: ${CYAN}${c_day}${NC}"
    pause
}

menu_cleaner() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🧹 ОЧИСТКА СЕРВЕРА (МЕСТО НА ДИСКЕ)${NC}"
        echo -e "${GRAY} Безопасное удаление системного мусора и логов.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " 💾 Текущее свободное место: ${GREEN}$(human_readable $(get_free_space))${NC}\n"
        echo -e " ${GREEN}1.${NC} 🧹 Полная уборка (Максимум свободного места)"
        echo -e " ${YELLOW}2.${NC} 📦 Очистить кэш APT"
        echo -e " ${YELLOW}3.${NC} 📚 Очистить системные логи (Systemd)"
        echo -e " ${YELLOW}4.${NC} 🐳 Очистить мусор Docker"
        echo -e " ${YELLOW}5.${NC} 🗑️ Очистить временные файлы (/tmp)"
        echo -e " ${YELLOW}6.${NC} 🧩 Очистить старые Snap пакеты"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${CYAN}7.${NC} 🔍 Интерактивный Анализатор Диска (Smart Explorer)"
        
        if crontab -l 2>/dev/null | grep -q -- '--silent-clean'; then
            echo -e " ${MAGENTA}8.${NC} ⏰ Настроить Автоочистку ${GREEN}[АКТИВНА]${NC}"
        else
            echo -e " ${MAGENTA}8.${NC} ⏰ Настроить Автоочистку (в Cron)"
        fi
        
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) run_with_diff "ПОЛНАЯ ОЧИСТКА СЕРВЕРА" clean_all_funcs ;;
            2) run_with_diff "ОЧИСТКА КЭША APT" clean_apt ;; 3) run_with_diff "ОЧИСТКА ЖУРНАЛОВ" clean_journal ;;
            4) run_with_diff "ОЧИСТКА DOCKER" clean_docker ;; 5) run_with_diff "ОЧИСТКА /TMP" clean_tmp ;;
            6) run_with_diff "ОЧИСТКА SNAP" clean_snap ;; 7) analyze_disk ;; 8) setup_cron ;; 0) return ;;
        esac
    done
}
