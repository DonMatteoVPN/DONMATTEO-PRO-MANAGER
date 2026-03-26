#!/bin/bash
# Модуль автообновления скрипта

run_auto_update() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 🚀 СКАЧИВАНИЕ ОБНОВЛЕНИЯ v${LATEST_VER}${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    echo -e "${CYAN}[*] Создание резервных копий...${NC}"
    cp /usr/local/bin/don /usr/local/bin/don.bak 2>/dev/null || true
    
    echo -e "${CYAN}[*] Загрузка нового ядра...${NC}"
    if curl -sL "${REPO_RAW}/don" -o /usr/local/bin/don; then
        sed -i 's/\r$//' /usr/local/bin/don # <--- АВТООЧИСТКА
        chmod +x /usr/local/bin/don
        echo -e "${GREEN}[+] Ядро успешно обновлено.${NC}"
    else
        echo -e "${RED}[✗] Ошибка скачивания ядра. Отмена.${NC}"
        mv /usr/local/bin/don.bak /usr/local/bin/don
        pause
        return
    fi

    echo -e "${CYAN}[*] Загрузка новых модулей...${NC}"
    local MODULES=("m_ufw.sh" "m_ssh.sh" "m_f2b.sh" "m_tg.sh" "m_swap.sh" "m_cleaner.sh" "m_installer.sh" "m_update.sh")
    
    for mod in "${MODULES[@]}"; do
        echo -e " └─ Скачивание ${mod}..."
        curl -sL "${REPO_RAW}/modules/${mod}" -o "/opt/remnawave/modules/${mod}"
        sed -i 's/\r$//' "/opt/remnawave/modules/${mod}" # <--- АВТООЧИСТКА
    done
    
    echo -e "\n${GREEN}${BOLD}🎉 ОБНОВЛЕНИЕ УСПЕШНО ЗАВЕРШЕНО! 🎉${NC}"
    echo -e "${YELLOW}Скрипт будет перезапущен для применения изменений.${NC}"
    sleep 3
    
    # Полностью заменяем текущий процесс новым скриптом
    exec don
}
