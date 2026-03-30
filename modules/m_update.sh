#!/bin/bash
# Модуль автообновления (ПРО-ВЕРСИЯ С ОБХОДОМ КЭША И ЗАЩИТОЙ CURL)

run_auto_update() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 🚀 СКАЧИВАНИЕ ОБНОВЛЕНИЯ v${LATEST_VER}${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    smart_dns_fix
    # Поиск самого быстрого канала
    find_fastest_mirror
    
    # Пытаемся получить COMMIT_SHA для точной загрузки (если GitHub API доступен)
    local COMMIT_SHA=$(smart_curl_json "https://api.github.com/repos/DonMatteoVPN/DONMATTEO-PRO-MANAGER/commits/main" "sha")
    
    local DL_BASE
    if [[ -n "$COMMIT_SHA" && ${#COMMIT_SHA} -eq 40 ]]; then
        DL_BASE="https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/${COMMIT_SHA}"
        echo -e "${GREEN}[+] Хэш репозитория: ${COMMIT_SHA:0:7}${NC}"
    else
        DL_BASE="${REPO_RAW}"
        echo -e "${YELLOW}[!] Используется канал загрузки: Main (Fallback)${NC}"
    fi

    echo -e "${CYAN}[*] Создание резервной копии ядра...${NC}"
    cp /usr/local/bin/don /usr/local/bin/don.bak 2>/dev/null || true
    
    echo -e "${CYAN}[*] Обновление ядра (don)...${NC}"
    if smart_curl "${DL_BASE}/don" "/usr/local/bin/don"; then
        tr -d '\r' < /usr/local/bin/don > /usr/local/bin/don.tmp && mv /usr/local/bin/don.tmp /usr/local/bin/don
        chmod +x /usr/local/bin/don
        echo -e "${GREEN}[+] Ядро успешно обновлено.${NC}"
    else
        echo -e "${RED}[✗] Ошибка обновления ядра. Откат...${NC}"
        mv /usr/local/bin/don.bak /usr/local/bin/don 2>/dev/null
        pause; return
    fi

    echo -e "${CYAN}[*] Обновление манифеста модулей...${NC}"
    smart_curl "${DL_BASE}/modules.list" "$MOD_LIST_FILE"

    echo -e "${CYAN}[*] Загрузка обновленных модулей...${NC}"
    if [[ -f "$MOD_LIST_FILE" ]]; then
        while read -r mod; do
            [[ -z "$mod" ]] && continue
            echo -e " └─ Синхронизация ${mod}..."
            if smart_curl "${DL_BASE}/modules/${mod}" "${MOD_DIR}/${mod}"; then
                tr -d '\r' < "${MOD_DIR}/${mod}" > "${MOD_DIR}/${mod}.tmp" && mv "${MOD_DIR}/${mod}.tmp" "${MOD_DIR}/${mod}"
            else
                echo -e "${RED}    [!] Ошибка при скачивании модуля ${mod}${NC}"
            fi
        done < "$MOD_LIST_FILE"
    fi
    
    restore_dns
    echo -e "\n${GREEN}${BOLD}🎉 ОБНОВЛЕНИЕ УСПЕШНО ЗАВЕРШЕНО! 🎉${NC}"
    echo -e "${YELLOW}Скрипт будет перезапущен для применения изменений.${NC}"
    sleep 2
    
    # Полностью заменяем текущий процесс новым скриптом
    exec don
}
