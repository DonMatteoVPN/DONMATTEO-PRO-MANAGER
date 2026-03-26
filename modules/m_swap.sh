#!/bin/bash

get_swap_status() {
    local swp=$(free -m | awk '/^Swap:/ {print $2}')
    if [[ "$swp" != "0" && -n "$swp" ]]; then echo -e "${GREEN}[ВКЛЮЧЕНО: ${swp} MB]${NC}"; else echo -e "${RED}[ВЫКЛЮЧЕН]${NC}"; fi
}

show_memory_status() {
    clear
    echo -e "${MAGENTA}=== СТАТУС ОПЕРАТИВНОЙ ПАМЯТИ И SWAP ===${NC}"
    
    local mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/^Mem:/ {print $3}')
    local mem_free=$(free -m | awk '/^Mem:/ {print $4}')
    local mem_cache=$(free -m | awk '/^Mem:/ {print $6}')
    local mem_avail=$(free -m | awk '/^Mem:/ {print $7}')
    
    local swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    local swap_used=$(free -m | awk '/^Swap:/ {print $3}')
    local swap_free=$(free -m | awk '/^Swap:/ {print $4}')

    echo -e "${CYAN}💻 Оперативная память (RAM):${NC}"
    echo -e "  └─ Всего доступно: ${GREEN}${mem_total} MB${NC}"
    echo -e "  └─ Использовано:   ${YELLOW}${mem_used} MB${NC}"
    echo -e "  └─ Кэш/Буферы:     ${BLUE}${mem_cache} MB${NC}"
    echo -e "  └─ Свободно:       ${GREEN}${mem_avail} MB${NC}"

    echo -e "\n${CYAN}💽 Файл подкачки (Swap):${NC}"
    if [[ "$swap_total" == "0" ]]; then
        echo -e "  └─ ${RED}ВЫКЛЮЧЕН (Рекомендуется создать!)${NC}"
    else
        echo -e "  └─ Всего выделено: ${GREEN}${swap_total} MB${NC}"
        echo -e "  └─ Использовано:   ${RED}${swap_used} MB${NC}"
        echo -e "  └─ Свободно:       ${GREEN}${swap_free} MB${NC}"
    fi
    pause
}

make_swap() {
    local SIZE=$1
    echo -e "${CYAN}[*] Запуск Супер-команды v2.0 (Создание Swap на ${SIZE}GB)...${NC}"
    swapoff -a 2>/dev/null || true
    rm -f /swapfile 2>/dev/null
    
    fallocate -l ${SIZE}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    grep -qE '^/swapfile\s' /etc/fstab || echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    
    echo -e "\n${GREEN}[+] Файл подкачки на ${SIZE}GB успешно создан и активирован!${NC}"
    echo -e "${GRAY}(Внимание! Сообщение 'old swap signature' от mkswap — это норма, старая подпись просто перезаписана)${NC}"
}

manage_swap() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  ⚙️ СИСТЕМНЫЕ НАСТРОЙКИ (SWAP / ПАМЯТЬ) ${NC}$(get_swap_status)"
        echo -e "${GRAY} Файл подкачки. Спасает сервер от падения (OOM Killer),${NC}"
        echo -e "${GRAY} когда кончается физическая оперативная память.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        
        local RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local RAM_GB=$((RAM_KB / 1024 / 1024))
        [[ $RAM_GB -eq 0 ]] && RAM_GB=1 
        
        local REC_SWAP
        if [ "$RAM_GB" -le 2 ]; then REC_SWAP=$((RAM_GB * 2)); elif [ "$RAM_GB" -le 8 ]; then REC_SWAP=$RAM_GB; else REC_SWAP=4; fi

        echo -e "  Текущая RAM: ${GREEN}${RAM_GB} GB${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${GREEN}1.${NC} 🤖 Умный Анализ и Создание Swap (Рекомендуется)"
        echo -e "    ${GRAY}└─ Скрипт проверит железо и предложит лучший размер.${NC}"
        echo -e " ${RED}2.${NC} 🗑️  Удалить файл подкачки (Swap)"
        echo -e "    ${GRAY}└─ Выключает Swap и освобождает место на диске.${NC}"
        echo -e " ${YELLOW}3.${NC} 📊 Подробный статус оперативной памяти"
        echo -e "    ${GRAY}└─ Показывает, сколько памяти свободно прямо сейчас.${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice

        case $choice in
            1)
                clear
                echo -e "${MAGENTA}=== АНАЛИЗ СИСТЕМЫ И РЕКОМЕНДАЦИИ ===${NC}"
                echo -e "Физическая оперативная память (RAM): ${GREEN}${RAM_GB} GB${NC}"
                echo -e "Идеальный размер файла подкачки (Swap): ${GREEN}${REC_SWAP} GB${NC}\n"
                
                echo -e "${GRAY}ℹ️ Как работает Swap и стоит ли его завышать?${NC}"
                echo -e "Swap — это резервная память, которая находится на жестком диске."
                echo -e "Даже самый быстрый SSD диск работает ${YELLOW}в десятки раз медленнее${NC} оперативной памяти."
                echo -e "Поэтому делать Swap размером 10-20 ГБ абсолютно бессмысленно: если сервер забьет"
                echo -e "такой объем подкачки, он просто намертво зависнет от перегрузки диска."
                echo -e ""
                echo -e "Для VPN-ноды Swap нужен ИСКЛЮЧИТЕЛЬНО как ${GREEN}'страховочная сетка'${NC}."
                echo -e "Он спасает важные процессы от принудительного убийства (OOM Killer),"
                echo -e "если на сервер внезапно придет слишком много тяжелого трафика."
                echo -e "\n${CYAN}Формула Искусственного Интеллекта скрипта:${NC}"
                echo -e "• RAM до 2 GB -> Swap = RAM x 2"
                echo -e "• RAM от 2 до 8 GB -> Swap = RAM"
                echo -e "• RAM больше 8 GB -> Swap = 4 GB (этого достаточно для страховки)\n"
                
                echo -e "${YELLOW}Выберите нужное действие:${NC}"
                echo -e " 1. Применить рекомендацию: создать Swap на ${GREEN}${REC_SWAP} GB${NC}"
                echo -e " 2. Вписать свой размер вручную (в Гигабайтах)"
                echo -e " 0. Отмена"
                read -p ">> " swap_ch
                
                case $swap_ch in
                    1) make_swap "$REC_SWAP"; pause ;;
                    2) 
                       read -p "Введите желаемый размер в GB (только цифра, например 2): " custom_swap
                       if [[ "$custom_swap" =~ ^[0-9]+$ ]] && [ "$custom_swap" -gt 0 ]; then make_swap "$custom_swap"; else echo -e "${RED}Ошибка: введите целое положительное число.${NC}"; fi
                       pause ;;
                    0) continue ;;
                esac
                ;;
            2)
                clear; echo -e "${CYAN}[*] Процесс удаления файла подкачки...${NC}"
                swapoff -a 2>/dev/null || true; rm -f /swapfile; sed -i '/^\/swapfile/d' /etc/fstab
                echo -e "${GREEN}[+] Swap успешно отключен и полностью удален.${NC}"; pause ;;
            3) show_memory_status ;;
            0) return ;;
        esac
    done
}
