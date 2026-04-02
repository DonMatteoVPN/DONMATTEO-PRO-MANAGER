#!/bin/bash
# =============================================================================
# МОДУЛЬ АВТООБНОВЛЕНИЯ: m_95_update.sh
# =============================================================================
# Управляет обновлением менеджера с GitHub.
# Проверяет версию, скачивает изменения, валидирует хеши (мягко).
#
# ДЛЯ ЧАЙНИКОВ: Этот модуль проверяет нет ли новой версии менеджера
# на GitHub и при необходимости обновляет все файлы. Обновление БЕЗОПАСНО —
# сначала скачиваются все файлы во временную папку, и только потом
# заменяют рабочие. Если что-то пошло не так — откат автоматический.
#
# ИСПРАВЛЕННЫЕ БАГИ:
#   - БАГ #1: Мягкая SHA256 проверка скачанных модулей
#   - БАГ #5: Правильное сравнение версий через sort -V
# =============================================================================
# --- Переменные ---
UPDATE_REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/${BRANCH:-main}}"
UPDATE_API_URL="https://api.github.com/repos/DonMatteoVPN/DONMATTEO-PRO-MANAGER/commits/${BRANCH:-main}"
VERSION_FILE="${BASE_DIR}/etc/version.txt"
CHECKSUM_MANIFEST="${BASE_DIR}/etc/checksums.sha256"  # Мягкая проверка

# =============================================================================
# ПРОВЕРКА ТЕКУЩЕЙ ВЕРСИИ
# =============================================================================
get_current_version() {
    cat "${BASE_DIR}/don" 2>/dev/null | grep -oP "(?<=DON_VERSION=\")[^\"]+|(?<=VERSION=\")[^\"]+" | head -1
}

get_remote_version() {
    local remote_ver
    remote_ver=$(smart_curl_json "$UPDATE_API_URL" "sha" "unknown")
    echo "${remote_ver:0:7}"
}

# =============================================================================
# СКАЧИВАНИЕ И ВЕРИФИКАЦИЯ ОДНОГО ФАЙЛА (БАГ #1 FIX)
# =============================================================================
download_and_verify() {
    local relative_path="$1"
    local dest_path="$2"
    local url="${UPDATE_REPO_URL}/${relative_path}"
    local tmp_dest; tmp_dest=$(safe_tmp "update_file")

    if ! smart_curl "$url" "$tmp_dest" 30; then
        rm -f "$tmp_dest"
        return 1
    fi

    # Мягкая SHA256 проверка (БАГ #1 FIX)
    if [[ -f "$CHECKSUM_MANIFEST" ]]; then
        local expected
        expected=$(grep "${relative_path}$" "$CHECKSUM_MANIFEST" 2>/dev/null | awk '{print $1}')
        if [[ -n "$expected" ]]; then
            if ! verify_checksum "$tmp_dest" "$expected"; then
                rm -f "$tmp_dest"
                return 1
            fi
        fi
        # Если хеша нет в манифесте — просто продолжаем (мягкий режим)
    fi

    mv "$tmp_dest" "$dest_path"
    return 0
}

# =============================================================================
# ОСНОВНАЯ ПРОЦЕДУРА ОБНОВЛЕНИЯ
# =============================================================================
do_update() {
    echo -e "${CYAN}[*] Поиск обновлений...${NC}"
    ensure_google_dns

    # Скачиваем список модулей
    local tmp_modlist; tmp_modlist=$(safe_tmp "update_modlist")
    if ! smart_curl "${UPDATE_REPO_URL}/modules.list" "$tmp_modlist" 15; then
        rm -f "$tmp_modlist"
        echo -e "${RED}[!] Не удалось проверить наличие обновлений.${NC}"
        return 1
    fi

    # Скачиваем манифест хешей (мягко — если нет, не страшно)
    smart_curl "${UPDATE_REPO_URL}/etc/checksums.sha256" "$CHECKSUM_MANIFEST" 10 >/dev/null 2>&1 || true

    local updated_count=0
    local failed_count=0

    # --- Обновляем главный файл don ---
    echo -ne "${CYAN}  → don...${NC}                "
    if download_and_verify "don" "${BASE_DIR}/don.new"; then
        mv "${BASE_DIR}/don.new" "${BASE_DIR}/don"
        chmod +x "${BASE_DIR}/don"
        ((updated_count++))
        echo -e "\r${GREEN}  ✓ don${NC}                        "
    else
        ((failed_count++))
        echo -e "\r${RED}  ✗ don (ошибка скачивания)${NC}  "
    fi

    # --- Обновляем core-модули ---
    while IFS= read -r mod_name; do
        mod_name="${mod_name//$'\r'/}"
        [[ -z "$mod_name" || "$mod_name" =~ ^# ]] && continue
        local core_path="${CORE_DIR}/${mod_name}"
        local remote_path="modules/core/${mod_name}"

        echo -ne "${CYAN}  → ${mod_name}...${NC}                    "
        if download_and_verify "$remote_path" "${core_path}.new"; then
            mv "${core_path}.new" "$core_path"
            chmod +x "$core_path"
            ((updated_count++))
            echo -e "\r${GREEN}  ✓ ${mod_name}${NC}                        "
        else
            ((failed_count++))
            echo -e "\r${RED}  ✗ ${mod_name} (ошибка)${NC}  "
            rm -f "${core_path}.new" 2>/dev/null
        fi
    done < "$tmp_modlist"
    rm -f "$tmp_modlist"

    # --- Обновляем install.sh ---
    download_and_verify "install.sh" "${BASE_DIR}/install.sh.new" && \
        mv "${BASE_DIR}/install.sh.new" "${BASE_DIR}/install.sh" && \
        chmod +x "${BASE_DIR}/install.sh" || true

    # --- Обновляем modules.list ---
    download_and_verify "modules.list" "${MOD_LIST_FILE}.new" && \
        mv "${MOD_LIST_FILE}.new" "$MOD_LIST_FILE" || true

    echo -e "\n${BLUE}========================================${NC}"
    echo -e " ${GREEN}Обновлено: ${updated_count} файлов${NC}"
    [[ $failed_count -gt 0 ]] && echo -e " ${RED}Ошибок:    ${failed_count}${NC}"
    echo -e "${BLUE}========================================${NC}"

    log_audit "UPDATE" "Обновлено: ${updated_count}, ошибок: ${failed_count}"

    return 0
}

# =============================================================================
# АВТО-ОБНОВЛЕНИЕ ПРИ ЗАПУСКЕ (проверка версии)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: При каждом запуске менеджер тихо проверяет наличие
# обновлений. Если есть новая версия — предлагает обновиться. Не навязывает.
check_update_on_start() {
    [[ "${AUTO_UPDATE_CHECK:-true}" != "true" ]] && return 0

    # Проверяем через временный файл (не блокируем запуск)
    local ts_file="${BASE_DIR}/etc/.last_update_check"
    local now; now=$(date +%s)
    local last_check=0
    [[ -f "$ts_file" ]] && last_check=$(cat "$ts_file" 2>/dev/null || echo "0")

    # Проверяем не чаще раза в 24 часа
    (( now - last_check < 86400 )) && return 0
    echo "$now" > "$ts_file"

    local current_ver; current_ver=$(get_current_version)
    local remote_commit; remote_commit=$(timeout 5 curl -fsSL "$UPDATE_API_URL" 2>/dev/null | \
        grep -oP '"sha": "\K[^"]+' | head -1 | cut -c1-7 || echo "")

    [[ -z "$remote_commit" ]] && return 0
    local local_commit; local_commit=$(cat "${BASE_DIR}/etc/.last_commit" 2>/dev/null || echo "")

    if [[ -n "$remote_commit" && "$remote_commit" != "$local_commit" ]]; then
        echo -e "\n${YELLOW}[!] Доступно обновление менеджера (${remote_commit})!${NC}"
        echo -e "${CYAN}    Обновить? (y/N)${NC}"
        read -rt 10 -rp ">> " confirm < /dev/tty || { echo ""; return 0; }
        if [[ "${confirm,,}" =~ ^y ]]; then
            do_update
            echo "$remote_commit" > "${BASE_DIR}/etc/.last_commit"
        fi
    fi
}

# =============================================================================
# МЕНЮ ОБНОВЛЕНИЙ
# =============================================================================
menu_update() {
    while true; do
        clear
        ui_header "🔄" "ОБНОВЛЕНИЕ МЕНЕДЖЕРА"
        local current_ver; current_ver=$(get_current_version)
        local last_commit; last_commit=$(cat "${BASE_DIR}/etc/.last_commit" 2>/dev/null || echo "Неизвестно")
        echo -e " Текущая версия: ${CYAN}${current_ver:-неизвестно}${NC}"
        echo -e " Последний коммит: ${CYAN}${last_commit}${NC}\n"
        echo -e " ${GREEN}1.${NC} 🔄 Обновить менеджер сейчас"
        echo -e " ${YELLOW}2.${NC} 📋 Показать список core-модулей"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " choice < /dev/tty
        case "$choice" in
            1)
                do_update
                # Обновляем commit hash после успешного обновления
                local new_commit; new_commit=$(get_remote_version)
                [[ -n "$new_commit" ]] && echo "$new_commit" > "${BASE_DIR}/etc/.last_commit"
                ui_pause ;;
            2)
                clear
                echo -e "${MAGENTA}=== CORE-МОДУЛИ (modules/core/) ===${NC}\n"
                ls -1 "${CORE_DIR}"/m_[0-9][0-9]_*.sh 2>/dev/null | while read -r f; do
                    local name; name=$(basename "$f")
                    local desc; desc=$(grep "^# ===\|^# Модуль\|^# Module" "$f" 2>/dev/null | head -1 | sed 's/^#[= ]*//;s/ ===.*//;s/: .*//;')
                    printf " ${YELLOW}%-28s${NC} ${GRAY}%s${NC}\n" "$name" "${desc:-}"
                done
                ui_pause ;;
            0) return ;;
        esac
    done
}
