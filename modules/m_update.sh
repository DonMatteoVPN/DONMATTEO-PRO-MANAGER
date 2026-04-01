#!/bin/bash
# Модуль автообновления (ПРО-ВЕРСИЯ С ОБХОДОМ КЭША И ЗАЩИТОЙ CURL)

run_auto_update() {
    clear
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${BOLD} 🚀 СКАЧИВАНИЕ ОБНОВЛЕНИЯ v${LATEST_VER}${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    smart_dns_fix
    
    # Счётчики и лог ошибок
    local FAILED_MODS=()
    local SUCCESS_MODS=()
    
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
        
        # Проверка: файл не пустой и не является HTML-ошибкой
        if [[ -s "/usr/local/bin/don" ]] && ! head -c 100 "/usr/local/bin/don" | grep -qiE "^<html|^<!DOCTYPE|404 Not Found"; then
            tr -d '\r' < /usr/local/bin/don > /usr/local/bin/don.tmp && mv /usr/local/bin/don.tmp /usr/local/bin/don
            chmod +x /usr/local/bin/don
            echo -e "${GREEN}[+] Ядро успешно обновлено.${NC}"
            SUCCESS_MODS+=("don (ядро)")
        else
            echo -e "${RED}[✗] Скачан повреждённый файл ядра! Откат...${NC}"
            mv /usr/local/bin/don.bak /usr/local/bin/don 2>/dev/null
            FAILED_MODS+=("don (ядро) — файл пустой или содержит HTML-ошибку")
        fi
    else
        echo -e "${RED}[✗] Ошибка скачивания ядра. Откат...${NC}"
        mv /usr/local/bin/don.bak /usr/local/bin/don 2>/dev/null
        FAILED_MODS+=("don (ядро) — ошибка соединения")
        
        # Показываем ошибки и выходим
        echo -e "\n${RED}======================================================${NC}"
        echo -e "${RED}${BOLD}  ❌ ОБНОВЛЕНИЕ ПРЕРВАНО: КРИТИЧЕСКАЯ ОШИБКА${NC}"
        echo -e "${RED}======================================================${NC}"
        for err in "${FAILED_MODS[@]}"; do
            echo -e "  ${RED}[ОШИБКА]${NC} $err"
        done
        echo -e "${RED}======================================================${NC}"
        echo -e "\n${CYAN}Нажмите [Enter] для возврата в меню...${NC}"
        read -r < /dev/tty
        return
    fi

    echo -e "${CYAN}[*] Обновление манифеста модулей...${NC}"
    if ! curl -fsSL --connect-timeout 5 --max-time 10 \
        -H "Cache-Control: no-cache" \
        "${DL_BASE}/modules.list" -o "$MOD_LIST_FILE" 2>/dev/null; then
        FAILED_MODS+=("modules.list — ошибка скачивания манифеста")
        echo -e "${RED}    [!] Ошибка при скачивании modules.list${NC}"
    elif head -c 100 "$MOD_LIST_FILE" | grep -qiE "^<html|^<!DOCTYPE|404 Not Found"; then
        FAILED_MODS+=("modules.list — скачан HTML вместо файла")
        echo -e "${RED}    [!] modules.list содержит HTML-ошибку${NC}"
    else
        echo -e "${GREEN}    [+] Манифест модулей обновлён.${NC}"
    fi

    echo -e "${CYAN}[*] Загрузка обновленных модулей...${NC}"
    if [[ -f "$MOD_LIST_FILE" ]]; then
        while read -r mod; do
            [[ -z "$mod" ]] && continue
            echo -ne " └─ Синхронизация ${mod}... "
            local tmp_mod="${MOD_DIR}/${mod}.download_tmp"
            
            if curl -fsSL --connect-timeout 5 --max-time 10 \
                -H "Cache-Control: no-cache" \
                "${DL_BASE}/modules/${mod}" -o "$tmp_mod" 2>/dev/null; then
                
                # Проверка: файл не пустой и не HTML
                if [[ -s "$tmp_mod" ]] && ! head -c 100 "$tmp_mod" | grep -qiE "^<html|^<!DOCTYPE|404 Not Found"; then
                    tr -d '\r' < "$tmp_mod" > "${MOD_DIR}/${mod}" 2>/dev/null
                    rm -f "$tmp_mod"
                    echo -e "${GREEN}[OK]${NC}"
                    SUCCESS_MODS+=("$mod")
                else
                    rm -f "$tmp_mod"
                    echo -e "${RED}[ОШИБКА: повреждённый файл]${NC}"
                    FAILED_MODS+=("$mod — скачан HTML или пустой файл")
                fi
            else
                rm -f "$tmp_mod" 2>/dev/null
                echo -e "${RED}[ОШИБКА: нет соединения]${NC}"
                FAILED_MODS+=("$mod — ошибка скачивания")
            fi
        done < "$MOD_LIST_FILE"
    fi
    
    restore_dns
    
    # =====================================================================
    # ИТОГОВЫЙ ОТЧЁТ ОБНОВЛЕНИЯ — ВСЕГДА ПОКАЗЫВАЕТСЯ ПЕРЕД EXIT
    # =====================================================================
    echo -e "\n${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}  📋 ИТОГОВЫЙ ОТЧЁТ ОБНОВЛЕНИЯ${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    if [[ ${#SUCCESS_MODS[@]} -gt 0 ]]; then
        echo -e "${GREEN}  ✅ Успешно обновлено (${#SUCCESS_MODS[@]}):${NC}"
        for ok in "${SUCCESS_MODS[@]}"; do
            echo -e "    ${GREEN}[OK]${NC} $ok"
        done
    fi
    
    if [[ ${#FAILED_MODS[@]} -gt 0 ]]; then
        echo -e "\n${RED}  ❌ ОШИБКИ ПРИ ОБНОВЛЕНИИ (${#FAILED_MODS[@]}/${#SUCCESS_MODS[@]}+${#FAILED_MODS[@]}):${NC}"
        for err in "${FAILED_MODS[@]}"; do
            echo -e "    ${RED}[ОШИБКА]${NC} $err"
        done
        echo -e "\n${YELLOW}  ⚠️  Некоторые модули не обновились. Рабочие копии сохранены.${NC}"
        echo -e "${YELLOW}  Проверьте интернет-соединение и попробуйте обновиться позже.${NC}"
    else
        echo -e "\n${GREEN}${BOLD}🎉 ВСЕ КОМПОНЕНТЫ ОБНОВЛЕНЫ УСПЕШНО! 🎉${NC}"
    fi
    
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${YELLOW}Скрипт будет перезапущен для применения изменений.${NC}"
    echo -e "\n${CYAN}Нажмите [Enter] для перезапуска скрипта...${NC}"
    read -r < /dev/tty
    
    # Очищаем кэш проверки обновлений перед перезапуском
    rm -f /tmp/don_update_check.cache 2>/dev/null
    
    # Полностью заменяем текущий процесс новым скриптом
    exec /usr/local/bin/don "$@"
}
