#!/bin/bash
# Модуль автообновления (ПРО-ВЕРСИЯ С ОБХОДОМ КЭША)

run_auto_update() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 🚀 СКАЧИВАНИЕ ОБНОВЛЕНИЯ v${LATEST_VER}${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    echo -e "${CYAN}[*] Получение прямого хэша последнего коммита...${NC}"
    # Хэш коммита уникален! Скачивание по нему ГАРАНТИРУЕТ отсутствие кэша.
    local LATEST_SHA=$(curl -s --max-time 3 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/DonMatteoVPN/DONMATTEO-PRO-MANAGER/commits/main" | grep -m 1 '"sha":' | cut -d'"' -f4)
    
    local DL_BASE
    if [[ -n "$LATEST_SHA" && ${#LATEST_SHA} -eq 40 ]]; then
        DL_BASE="https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/${LATEST_SHA}"
        echo -e "${GREEN}[+] Идентификатор версии получен: ${LATEST_SHA:0:7}${NC}"
    else
        DL_BASE="${REPO_RAW}"
        echo -e "${YELLOW}[!] Используется стандартный канал загрузки.${NC}"
    fi

    echo -e "${CYAN}[*] Создание резервных копий...${NC}"
    cp /usr/local/bin/don /usr/local/bin/don.bak 2>/dev/null || true
    
    echo -e "${CYAN}[*] Загрузка нового ядра...${NC}"
    if curl -sL "${DL_BASE}/don" -o /usr/local/bin/don; then
        sed -i 's/\r$//' /usr/local/bin/don
        chmod +x /usr/local/bin/don
        echo -e "${GREEN}[+] Ядро успешно обновлено.${NC}"
    else
        echo -e "${RED}[✗] Ошибка скачивания ядра. Отмена.${NC}"
        mv /usr/local/bin/don.bak /usr/local/bin/don
        pause
        return
    fi

    echo -e "${CYAN}[*] Загрузка новых модулей...${NC}"
    local MODULES=("m_ufw.sh" "m_ssh.sh" "m_f2b.sh" "m_tg.sh" "m_swap.sh" "m_cleaner.sh" "m_installer.sh" "m_update.sh" "m_scanner.sh")
    
    for mod in "${MODULES[@]}"; do
        echo -e " └─ Скачивание ${mod}..."
        curl -sL "${DL_BASE}/modules/${mod}" -o "/opt/remnawave/modules/${mod}"
        sed -i 's/\r$//' "/opt/remnawave/modules/${mod}"
    done
    
    echo -e "\n${GREEN}${BOLD}🎉 ОБНОВЛЕНИЕ УСПЕШНО ЗАВЕРШЕНО! 🎉${NC}"
    echo -e "${YELLOW}Скрипт будет перезапущен для применения изменений.${NC}"
    sleep 2
    
    # Полностью заменяем текущий процесс новым скриптом
    exec don
}
