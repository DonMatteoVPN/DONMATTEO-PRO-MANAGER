#!/bin/bash
# Модуль автообновления (ПРО-ВЕРСИЯ С ОБХОДОМ КЭША И ЗАЩИТОЙ CURL)

run_auto_update() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 🚀 СКАЧИВАНИЕ ОБНОВЛЕНИЯ v${LATEST_VER}${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    smart_dns_fix
    
    # АГРЕССИВНЫЙ ОБХОД КЭША: Получаем последний коммит через API
    echo -e "${CYAN}[*] Получение актуального хэша репозитория...${NC}"
    local COMMIT_SHA=$(curl -fsSL --connect-timeout 3 --max-time 5 \
        -H "Cache-Control: no-cache, no-store, must-revalidate" \
        -H "Pragma: no-cache" \
        -H "Expires: 0" \
        "https://api.github.com/repos/DonMatteoVPN/DONMATTEO-PRO-MANAGER/commits/main" 2>/dev/null | \
        grep -oP '"sha":\s*"\K[^"]+' | head -n1)
    
    local DL_BASE
    if [[ -n "$COMMIT_SHA" && ${#COMMIT_SHA} -eq 40 ]]; then
        DL_BASE="https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/${COMMIT_SHA}"
        echo -e "${GREEN}[+] Хэш репозитория: ${COMMIT_SHA:0:7} (Гарантия свежести!)${NC}"
    else
        # Fallback: используем main напрямую
        DL_BASE="${REPO_RAW}"
        echo -e "${YELLOW}[!] Используется канал загрузки: Main (Fallback)${NC}"
    fi

    echo -e "${CYAN}[*] Создание резервной копии ядра...${NC}"
    cp /usr/local/bin/don /usr/local/bin/don.bak 2>/dev/null || true
    
    echo -e "${CYAN}[*] Обновление ядра (don)...${NC}"
    # Используем прямой curl с обходом кэша
    if curl -fsSL --connect-timeout 5 --max-time 15 \
        -H "Cache-Control: no-cache, no-store, must-revalidate" \
        -H "Pragma: no-cache" \
        -H "Expires: 0" \
        "${DL_BASE}/don" -o "/usr/local/bin/don" 2>/dev/null; then
        tr -d '\r' < /usr/local/bin/don > /usr/local/bin/don.tmp && mv /usr/local/bin/don.tmp /usr/local/bin/don
        chmod +x /usr/local/bin/don
        echo -e "${GREEN}[+] Ядро успешно обновлено.${NC}"
    else
        echo -e "${RED}[✗] Ошибка обновления ядра. Откат...${NC}"
        mv /usr/local/bin/don.bak /usr/local/bin/don 2>/dev/null
        pause; return
    fi

    echo -e "${CYAN}[*] Обновление манифеста модулей...${NC}"
    curl -fsSL --connect-timeout 5 --max-time 10 \
        -H "Cache-Control: no-cache" \
        "${DL_BASE}/modules.list" -o "$MOD_LIST_FILE" 2>/dev/null

    echo -e "${CYAN}[*] Загрузка обновленных модулей...${NC}"
    if [[ -f "$MOD_LIST_FILE" ]]; then
        while read -r mod; do
            [[ -z "$mod" ]] && continue
            echo -e " └─ Синхронизация ${mod}..."
            if curl -fsSL --connect-timeout 5 --max-time 10 \
                -H "Cache-Control: no-cache" \
                "${DL_BASE}/modules/${mod}" -o "${MOD_DIR}/${mod}" 2>/dev/null; then
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
    
    # Очищаем кэш проверки обновлений перед перезапуском
    rm -f /tmp/don_update_check.cache 2>/dev/null
    
    # Полностью заменяем текущий процесс новым скриптом
    exec /usr/local/bin/don "$@"
}
