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
    
    echo -e "Выберите дни недели для запуска (введите цифру):"
    echo -e " 1 - Понедельник   5 - Пятница"
    echo -e " 2 - Вторник       6 - Суббота"
    echo -e " 3 - Среда         0 - Воскресенье"
    echo -e " 4 - Четверг       * - Каждый день"
    read -p ">> Ваш выбор: " c_day
    [[ ! "$c_day" =~ ^[0-6\*]$ ]] && { echo -e "${YELLOW}Неверный ввод. Установлено: Каждый день (*)${NC}"; c_day="*"; }
    
    echo -e "\nВведите ЧАС запуска (от 0 до 23):"
    read -p ">> " c_hour
    [[ ! "$c_hour" =~ ^([0-1]?[0-9]|2[0-3])$ ]] && { echo -e "${YELLOW}Неверный ввод. Установлено: 04:00${NC}"; c_hour="4"; }
    
    echo -e "\nВведите МИНУТЫ (от 0 до 59):"
    read -p ">> " c_min
    [[ ! "$c_min" =~ ^([0-5]?[0-9])$ ]] && c_min="0"

    local job="$c_min $c_hour * * $c_day /usr/local/bin/don --silent-clean > /dev/null 2>&1"
    
    # Удаляем старое задание, если было, и ставим новое
    crontab -l 2>/dev/null | grep -v '--silent-clean' | crontab -
    (crontab -l 2>/dev/null; echo "$job") | crontab -
    
    echo -e "\n${GREEN}[✓] Автоочистка успешно настроена!${NC}"
    echo -e "Время: ${CYAN}${c_hour}:${c_min}${NC}, День недели: ${CYAN}${c_day}${NC}"
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
        echo -e " ${CYAN}7.${NC} 🔍 Анализ диска (Что занимает место?)"
        echo -e " ${MAGENTA}8.${NC} ⏰ Настроить Автоочистку (в Cron интерактивно)"
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
