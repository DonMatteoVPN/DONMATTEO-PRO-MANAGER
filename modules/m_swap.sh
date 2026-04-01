#!/bin/bash

get_swap_status() {
    local swp=$(free -m | awk '/^Swap:/ {print $2}')
    local has_zram=$(lsblk 2>/dev/null | grep -i zram)
    
    if [[ -n "$has_zram" ]]; then
        echo -e "${GREEN}[ZRAM ВКЛЮЧЕН: ${swp} MB]${NC}"
    elif [[ "$swp" != "0" && -n "$swp" ]]; then 
        echo -e "${YELLOW}[DISK SWAP: ${swp} MB]${NC}"
    else 
        echo -e "${RED}[ВЫКЛЮЧЕН]${NC}"
    fi
}

show_memory_status() {
    clear
    echo -e "${MAGENTA}=== СТАТУС ОПЕРАТИВНОЙ ПАМЯТИ И SWAP ===${NC}"
    
    local mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/^Mem:/ {print $3}')
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

    echo -e "\n${CYAN}💽 Файл подкачки (ZRAM / Swap):${NC}"
    if [[ "$swap_total" == "0" ]]; then
        echo -e "  └─ ${RED}ВЫКЛЮЧЕН (Рекомендуется включить ZRAM!)${NC}"
    else
        if lsblk 2>/dev/null | grep -q zram; then
            echo -e "  └─ Тип:            ${GREEN}Умное сжатие (ZRAM)${NC}"
        else
            echo -e "  └─ Тип:            ${YELLOW}Жесткий диск (Disk Swap)${NC}"
        fi
        echo -e "  └─ Всего выделено: ${GREEN}${swap_total} MB${NC}"
        echo -e "  └─ Использовано:   ${RED}${swap_used} MB${NC}"
        echo -e "  └─ Свободно:       ${GREEN}${swap_free} MB${NC}"
    fi
    pause
}

show_memory_instructions() {
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${MAGENTA}  📖 ИНСТРУКЦИЯ: ОПТИМИЗАЦИЯ ПАМЯТИ И ЛИМИТЫ DOCKER${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${GRAY} Правильная настройка памяти защитит ноду от зависаний (OOM).${NC}"
    echo -e "${BLUE}======================================================${NC}\n"
    
    echo -e "${CYAN}${BOLD}[ ЧАСТЬ 1 ] ЧТО ВЫБРАТЬ: ZRAM ИЛИ DISK SWAP?${NC}"
    echo -e " ${GREEN}🌪️ ZRAM (Сжатие в ОЗУ):${NC} Идеально для VPN. Работает со скоростью ОЗУ."
    echo -e "    Сжимает неактивные данные. ${YELLOW}Обязателен для серверов 1-2 ГБ!${NC}"
    echo -e " ${RED}💽 Disk Swap (На диске):${NC} Работает в 10-50 раз медленнее ZRAM."
    echo -e "    Использовать ТОЛЬКО если у сервера меньше 512 МБ ОЗУ.\n"

    echo -e "${CYAN}${BOLD}[ ЧАСТЬ 2 ] НАСТРОЙКА DOCKER-COMPOSE.YML${NC}"
    echo -e " Для защиты сервера нужно жестко ограничить аппетит ${YELLOW}remnanode${NC}."
    echo -e " В файле ${GREEN}docker-compose.yml${NC} найдите блок ${YELLOW}remnanode${NC} и добавьте лимиты:\n"

    echo -e "${BOLD}▶ ДЛЯ СЕРВЕРА НА 1 ГБ RAM (Минимальный):${NC}"
    echo -e "${CYAN}    environment:
      - NODE_OPTIONS=--max-old-space-size=256
    deploy:
      resources:
        limits:
          memory: 768M
        reservations:
          memory: 256M${NC}\n"

    echo -e "${BOLD}▶ ДЛЯ СЕРВЕРА НА 2 ГБ RAM (Оптимальный):${NC}"
    echo -e "${CYAN}    environment:
      - NODE_OPTIONS=--max-old-space-size=512
    deploy:
      resources:
        limits:
          memory: 1536M
        reservations:
          memory: 512M${NC}\n"

    echo -e "${BOLD}▶ ДЛЯ СЕРВЕРА НА 4 ГБ RAM И БОЛЬШЕ (Максимальный):${NC}"
    echo -e "${CYAN}    environment:
      - NODE_OPTIONS=--max-old-space-size=1024
    deploy:
      resources:
        limits:
          memory: 3072M
        reservations:
          memory: 1024M${NC}\n"

    echo -e "${BLUE}======================================================${NC}"
    echo -e "${YELLOW} 💡 ВАЖНО: После изменения docker-compose.yml выполните:${NC}"
    echo -e "${CYAN}    docker compose down && docker compose up -d${NC}"
    echo -e "${BLUE}======================================================${NC}"
    pause
}

make_zram_smart() {
    local PERCENT=$1
    echo -e "${CYAN}[*] Установка и настройка ZRAM (${PERCENT}% от RAM)...${NC}"
    
    swapoff -a 2>/dev/null || true
    rm -f /swapfile 2>/dev/null
    sed -i '/^\/swapfile/d' /etc/fstab

    apt-get update -y >/dev/null 2>&1
    apt-get install zram-tools bc -y >/dev/null 2>&1

    cat << EOF > /etc/default/zramswap
ALGO=lz4
PERCENT=${PERCENT}
PRIORITY=100
EOF

    systemctl restart zramswap >/dev/null 2>&1
    systemctl enable zramswap >/dev/null 2>&1
    
    echo -e "\n${GREEN}[+] ZRAM успешно активирован! Ваша ОЗУ теперь сжимается на лету.${NC}"
}

make_swap() {
    local SIZE=$1
    echo -e "${CYAN}[*] Создание классического Disk Swap на ${SIZE}GB...${NC}"
    
    systemctl stop zramswap 2>/dev/null || true
    apt-get remove --purge zram-tools -y >/dev/null 2>&1 || true
    
    swapoff -a 2>/dev/null || true
    rm -f /swapfile 2>/dev/null
    
    fallocate -l ${SIZE}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile
    
    grep -qE '^/swapfile\s' /etc/fstab || echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    
    echo -e "\n${GREEN}[+] Файл подкачки (Disk Swap) на ${SIZE}GB успешно создан!${NC}"
}

remove_all_swap() {
    echo -e "${CYAN}[*] Полное удаление ZRAM и Disk Swap...${NC}"
    
    systemctl stop zramswap 2>/dev/null || true
    systemctl disable zramswap 2>/dev/null || true
    apt-get remove --purge zram-tools -y >/dev/null 2>&1 || true
    
    swapoff -a 2>/dev/null || true
    rm -f /swapfile 2>/dev/null
    sed -i '/^\/swapfile/d' /etc/fstab
    
    echo -e "${GREEN}[+] Все файлы подкачки и модули сжатия отключены и удалены.${NC}"
}

manage_swap() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  ⚙️ СИСТЕМНЫЕ НАСТРОЙКИ (SWAP / ПАМЯТЬ) ${NC}$(get_swap_status)"
        echo -e "${GRAY} Интеллектуальное управление оперативной памятью сервера.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        
        local RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local RAM_MB=$((RAM_KB / 1024))
        local RAM_GB=$((RAM_MB / 1024))
        [[ $RAM_GB -eq 0 ]] && RAM_GB=1 
        
        local REC_ZRAM_PERCENT
        if[ "$RAM_GB" -le 1 ]; then REC_ZRAM_PERCENT=60;
        elif[ "$RAM_GB" -eq 2 ]; then REC_ZRAM_PERCENT=50;
        else REC_ZRAM_PERCENT=25; fi

        local REC_DISK_SWAP
        if[ "$RAM_GB" -le 2 ]; then REC_DISK_SWAP=$((RAM_GB * 2)); elif [ "$RAM_GB" -le 8 ]; then REC_DISK_SWAP=$RAM_GB; else REC_DISK_SWAP=4; fi

        echo -e "  Текущая физическая RAM: ${GREEN}${RAM_GB} GB (${RAM_MB} MB)${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${GREEN}1.${NC} 🌪️ ${BOLD}Умная установка ZRAM (Турбо-сжатие ОЗУ)${NC} ${YELLOW}[ РЕКОМЕНДУЕТСЯ ]${NC}"
        echo -e "    ${GRAY}└─ Идеально для VPN. ИИ предлагает сжатие: ${GREEN}${REC_ZRAM_PERCENT}%${NC}"
        echo -e " ${YELLOW}2.${NC} 💽 Классический Disk Swap (На жестком диске)"
        echo -e "    ${GRAY}└─ ИИ предлагает размер: ${YELLOW}${REC_DISK_SWAP} GB${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${RED}3.${NC} 🗑️  Полностью отключить и удалить ZRAM / Swap"
        echo -e " ${CYAN}4.${NC} 📊 Подробный статус оперативной памяти"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${MAGENTA}${BOLD}5. 📖 ЧИТАТЬ ИНСТРУКЦИЮ (ЛИМИТЫ DOCKER И ПАМЯТЬ)${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice

        case $choice in
            1)
                clear
                echo -e "${MAGENTA}=== УСТАНОВКА УМНОГО ZRAM ===${NC}"
                echo -e "Скрипт проанализировал вашу ОЗУ (${GREEN}${RAM_MB} MB${NC})."
                echo -e "Рекомендуемый объем виртуального диска ZRAM: ${GREEN}${REC_ZRAM_PERCENT}% от ОЗУ${NC}\n"
                echo -e "${YELLOW}Выберите действие:${NC}"
                echo -e " 1. Применить ИИ-рекомендацию (${GREEN}${REC_ZRAM_PERCENT}%${NC})"
                echo -e " 2. Вписать процент вручную (Например: 50)"
                echo -e " 0. Отмена"
                read -p ">> " zram_ch
                case $zram_ch in
                    1) make_zram_smart "$REC_ZRAM_PERCENT"; pause ;;
                    2) 
                       read -p "Введите процент (10-100): " custom_zram
                       if [[ "$custom_zram" =~ ^[0-9]+$ ]] && [ "$custom_zram" -ge 10 ] &&[ "$custom_zram" -le 100 ]; then 
                           make_zram_smart "$custom_zram"; 
                       else 
                           echo -e "${RED}Ошибка: неверное значение.${NC}"; 
                       fi
                       pause ;;
                    0) continue ;;
                esac
                ;;
            2)
                clear
                echo -e "${MAGENTA}=== УСТАНОВКА DISK SWAP ===${NC}"
                echo -e "Рекомендуемый размер: ${GREEN}${REC_DISK_SWAP} GB${NC}\n"
                echo -e "${YELLOW}Выберите действие:${NC}"
                echo -e " 1. Применить ИИ-рекомендацию (${GREEN}${REC_DISK_SWAP} GB${NC})"
                echo -e " 2. Вписать свой размер вручную (в Гигабайтах)"
                echo -e " 0. Отмена"
                read -p ">> " swap_ch
                case $swap_ch in
                    1) make_swap "$REC_DISK_SWAP"; pause ;;
                    2) 
                       read -p "Введите размер в GB (только цифра): " custom_swap
                       if [[ "$custom_swap" =~ ^[0-9]+$ ]] && [ "$custom_swap" -gt 0 ]; then make_swap "$custom_swap"; else echo -e "${RED}Ошибка: введите целое положительное число.${NC}"; fi
                       pause ;;
                    0) continue ;;
                esac
                ;;
            3) remove_all_swap; pause ;;
            4) show_memory_status ;;
            5) show_memory_instructions ;;
            0) return ;;
        esac
    done
}
