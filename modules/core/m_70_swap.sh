#!/bin/bash
# =============================================================================
# МОДУЛЬ ПАМЯТИ: m_70_swap.sh
# =============================================================================
# Управление виртуальной памятью (ZRAM + Swap).
# Оптимизация памяти особенно важна для слабых серверов (1-2 ГБ RAM).
#
# ДЛЯ ЧАЙНИКОВ: Если на сервере кончается оперативная память, он зависает.
# Этот модуль настраивает умное сжатие памяти (ZRAM) и страховку на диске (Swap),
# чтобы сервер работал стабильно под любыми нагрузками.
# =============================================================================

# get_swap_status теперь находится централизованно в m_10_helpers.sh

show_memory_status() {
    clear
    ui_header "📊" "СТАТУС ОПЕРАТИВНОЙ ПАМЯТИ И SWAP"
    
    local mem_total; mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    local mem_used; mem_used=$(free -m | awk '/^Mem:/ {print $3}')
    local mem_cache; mem_cache=$(free -m | awk '/^Mem:/ {print $6}')
    local mem_avail; mem_avail=$(free -m | awk '/^Mem:/ {print $7}')
    
    local swap_total; swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    local swap_used; swap_used=$(free -m | awk '/^Swap:/ {print $3}')
    local swap_free; swap_free=$(free -m | awk '/^Swap:/ {print $4}')

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
    ui_pause
}

show_memory_instructions() {
    clear
    ui_header "📖" "ИНСТРУКЦИЯ: ОПТИМИЗАЦИЯ ПАМЯТИ" "Защита сервера от OOM (нехватки памяти)."
    
    echo -e "${CYAN}${BOLD}[ ЧАСТЬ 1 ] ЧТО ВЫБРАТЬ: ZRAM ИЛИ DISK SWAP?${NC}"
    echo -e " ${GREEN}🌪️ ZRAM (Сжатие в ОЗУ):${NC} Идеально для VPN. Работает со скоростью ОЗУ."
    echo -e "    Сжимает неактивные данные. ${YELLOW}Обязателен для серверов 1-2 ГБ!${NC}"
    echo -e " ${RED}💽 Disk Swap (На диске):${NC} Работает в 10-50 раз медленнее ZRAM."
    echo -e "    Использовать ТОЛЬКО если у сервера меньше 512 МБ ОЗУ.\n"

    echo -e "${CYAN}${BOLD}[ ЧАСТЬ 2 ] НАСТРОЙКА DOCKER-COMPOSE.YML${NC}"
    echo -e " Разработчик должен жестко ограничивать аппетит ${YELLOW}remnanode${NC}."
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

    ui_sep
    echo -e "${YELLOW} 💡 ВАЖНО: После изменения docker-compose.yml выполните:${NC}"
    echo -e "${CYAN}    docker compose down && docker compose up -d${NC}"
    ui_sep
    ui_pause
}

make_zram_smart() {
    local PERCENT="$1"
    echo -e "${CYAN}[*] Установка и настройка ZRAM (${PERCENT}% от RAM)...${NC}"
    
    swapoff -a 2>/dev/null || true
    rm -f /swapfile 2>/dev/null
    sed -i '/^\/swapfile/d' /etc/fstab

    smart_apt_install "zram-tools" "bc" >/dev/null 2>&1

    cat << EOF > /etc/default/zramswap
ALGO=lz4
PERCENT=${PERCENT}
PRIORITY=100
EOF

    systemctl restart zramswap >/dev/null 2>&1
    systemctl enable zramswap >/dev/null 2>&1
    
    log_audit "SWAP" "ZRAM включён (${PERCENT}%)"
    echo -e "\n${GREEN}[+] ZRAM успешно активирован! ОЗУ теперь сжимается на лету.${NC}"
}

# --- ГИБРИДНАЯ ОПТИМИЗАЦИЯ (ZRAM + SWAP) ---
install_hybrid_memory_optimization() {
    echo -e "${CYAN}[*] Настройка гибридной памяти (ZRAM + Disk Swap)...${NC}"
    
    # 1. Сначала ZRAM (50% RAM, высокий приоритет)
    smart_apt_install "zram-tools" "bc" >/dev/null 2>&1
    
    cat << EOF > /etc/default/zramswap
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF
    systemctl restart zramswap >/dev/null 2>&1
    systemctl enable zramswap >/dev/null 2>&1

    # 2. Затем Disk Swap (2GB, низкий приоритет -2)
    if [[ ! -f /swapfile ]]; then
        echo -e "${YELLOW}[*] Создание файла подкачки 2GB в качестве страховки...${NC}"
        fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon -p -2 /swapfile 2>/dev/null || swapon /swapfile
        grep -qE '^/swapfile\s' /etc/fstab || echo '/swapfile none swap sw,pri=-2 0 0' | tee -a /etc/fstab
    else
        # Если файл есть, просто убеждаемся что приоритет верный
        swapoff /swapfile 2>/dev/null || true
        swapon -p -2 /swapfile 2>/dev/null || true
        sed -i 's|.*/swapfile.*|/swapfile none swap sw,pri=-2 0 0|' /etc/fstab
    fi
    
    log_audit "SWAP" "Гибридная оптимизация (ZRAM+Swap) установлена"
    echo -e "${GREEN}[✓] Гибридная память настроена: ZRAM (Priority 100) + Disk Swap (Priority -2).${NC}"
}

make_swap() {
    local SIZE="$1"
    echo -e "${CYAN}[*] Создание классического Disk Swap на ${SIZE}GB...${NC}"
    
    systemctl stop zramswap 2>/dev/null || true
    apt-get remove --purge zram-tools -y >/dev/null 2>&1 || true
    
    swapoff -a 2>/dev/null || true
    rm -f /swapfile 2>/dev/null
    
    fallocate -l "${SIZE}G" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile
    
    grep -qE '^/swapfile\s' /etc/fstab || echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    
    log_audit "SWAP" "Disk Swap включён (${SIZE}GB)"
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
    
    log_audit "SWAP" "Swap/ZRAM полностью отключены"
    echo -e "${GREEN}[+] Все файлы подкачки и модули сжатия отключены и удалены.${NC}"
}

# Переименовано для дона (menu_swap вместо manage_swap)
menu_swap() {
    while true; do
        clear
        ui_header "💾" "СИСТЕМНЫЕ НАСТРОЙКИ (ПАМЯТЬ)" "$(get_swap_status)"
        echo -e " ${CYAN}Интеллектуальное управление оперативной памятью сервера.${NC}\n"
        
        local RAM_KB; RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local RAM_MB=$((RAM_KB / 1024))
        local RAM_GB=$(( (RAM_MB + 512) / 1024 ))
        
        # Динамические рекомендации
        local REC_ZRAM REC_SWAP
        if [ "$RAM_MB" -le 1024 ]; then
            REC_ZRAM="60%"; REC_SWAP="2 GB"
        elif [ "$RAM_MB" -le 2048 ]; then
            REC_ZRAM="50%"; REC_SWAP="2 GB"
        elif [ "$RAM_MB" -le 4096 ]; then
            REC_ZRAM="40%"; REC_SWAP="4 GB"
        else
            REC_ZRAM="25%"; REC_SWAP="4 GB"
        fi
        
        echo -e "  Текущая физическая RAM: ${GREEN}${RAM_GB} GB (${RAM_MB} MB)${NC}"
        ui_sep
        echo -e " ${GREEN}1.${NC} 🌪️  ${BOLD}ГИБРИДНЫЙ режим (ZRAM + Swap)${NC} ${YELLOW}[РЕКОМЕНДУЕТСЯ]${NC}"
        echo -e "    ${GRAY}└─ ИИ предлагает: ZRAM (${REC_ZRAM}) + Swap (${REC_SWAP})${NC}"
        ui_sep
        echo -e " ${CYAN}2.${NC} 🧩 Только ZRAM (Турбо-сжатие в ОЗУ)"
        echo -e " ${CYAN}3.${NC} 💽 Только Disk Swap (На жестком диске)"
        ui_sep
        echo -e " ${RED}4.${NC} 🗑️  Полностью отключить и удалить ZRAM / Swap"
        echo -e " ${GREEN}5.${NC} 📊 Подробный статус оперативной памяти"
        echo -e " ${MAGENTA}6.${NC} 📖 ЧИТАТЬ ИНСТРУКЦИЮ (ЛИМИТЫ DOCKER)"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        
        read -rp ">> " choice < /dev/tty
        case "$choice" in
            1) 
                echo -e "\n${CYAN}[*] Запуск гибридной оптимизации...${NC}"
                install_hybrid_memory_optimization
                ui_pause ;;
            2)
                local custom_zram; custom_zram=$(ui_input "Процент сжатия (10-100)" "60")
                [[ "$custom_zram" =~ ^[0-9]+$ ]] && make_zram_smart "$custom_zram"
                ui_pause ;;
            3)
                local custom_swap; custom_swap=$(ui_input "Размер в GB (например, 2)" "2")
                [[ "$custom_swap" =~ ^[0-9]+$ ]] && make_swap "$custom_swap"
                ui_pause ;;
            4) 
                if ui_confirm "Точно отключить swap?"; then remove_all_swap; fi
                ui_pause ;;
            5) show_memory_status ;;
            6) show_memory_instructions ;;
            0) return ;;
        esac
    done
}
