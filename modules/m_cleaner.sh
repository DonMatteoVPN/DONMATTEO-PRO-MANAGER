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

analyze_disk() {
    clear; echo -e "${MAGENTA}=== АНАЛИЗ ЗАНЯТОГО МЕСТА ===${NC}"
    echo -e "${GRAY}Поиск самых тяжелых папок...${NC}\n"
    du -sh /var/log /var/lib/docker /tmp /var/cache/apt /var/lib/snapd 2>/dev/null | sort -hr | while read -r size path; do
        echo -e " ${YELLOW}${size}${NC}\t ${CYAN}${path}${NC}"
    done
    echo -e "\n${GREEN}Завершено.${NC}"; pause
}

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

    # --- ПРОВЕРКА АКТИВНОГО ЗАДАНИЯ ---
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
            2)
                crontab -l 2>/dev/null | grep -v '--silent-clean' | crontab -
                echo -e "\n${GREEN}[+] Автоочистка успешно отключена!${NC}"
                pause; return
                ;;
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
    
    # Регулярка для проверки (только цифры от 0 до 6, запятые или звездочка)
    [[ ! "$c_day" =~ ^([0-6\*](,[0-6])*)$ ]] && { echo -e "${YELLOW}Неверный формат. Установлено: Каждый день (*)${NC}"; c_day="*"; }
    [[ -z "$c_day" ]] && c_day="*"
    
    echo -e "\nВведите ЧАС запуска (от 0 до 23):"
    read -p ">> " c_hour
    [[ ! "$c_hour" =~ ^([0-1]?[0-9]|2[0-3])$ ]] && { echo -e "${YELLOW}Неверный ввод. Установлено: 04${NC}"; c_hour="4"; }
    
    echo -e "\nВведите МИНУТЫ (от 0 до 59):"
    read -p ">> " c_min
    [[ ! "$c_min" =~ ^([0-5]?[0-9])$ ]] && { echo -e "${YELLOW}Неверный ввод. Установлено: 00${NC}"; c_min="0"; }

    local job="$c_min $c_hour * * $c_day /usr/local/bin/don --silent-clean > /dev/null 2>&1"
    
    # Удаляем старое задание и ставим новое
    crontab -l 2>/dev/null | grep -v '--silent-clean' | crontab -
    (crontab -l 2
