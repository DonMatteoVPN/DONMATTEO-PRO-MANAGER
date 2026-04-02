#!/bin/bash
# =============================================================================
# МОДУЛЬ TRAFFICGUARD: m_60_tg.sh
# =============================================================================
# TrafficGuard — инструмент для автоматической блокировки серверов-сканеров,
# которые проверяют твой VPN-трафик (ТСПУ, контролирующие системы РКН и т.д.)
#
# ДЛЯ ЧАЙНИКОВ: Когда ты используешь VPN, специальные серверы от провайдера
# могут «нюхать» твой трафик, пытаясь понять что ты делаешь. TrafficGuard
# автоматически вычисляет и блокирует такие серверы через iptables/ipset.
#
# ИСПРАВЛЕННЫЕ БАГИ:
#   - БАГ #4: Валидация IP перед добавлением в ipset
# =============================================================================

# --- Переменные модуля ---
TG_CONF=$(ensure_module_config "tg")
TG_LISTS_FILE="${TG_CONF}/lists.txt"
TG_MANUAL_BAN="${TG_CONF}/manual_ban.list"
TG_INSTALL_SCRIPT="/tmp/tg_install.sh"  # Временный файл (mktemp)

[[ ! -f "$TG_LISTS_FILE" ]] && echo "" > "$TG_LISTS_FILE"
[[ ! -f "$TG_MANUAL_BAN" ]] && echo "" > "$TG_MANUAL_BAN"

# =============================================================================
# УСТАНОВКА TRAFFICGUARD
# =============================================================================
install_trafficguard() {
    local tg_url="${TG_INSTALL_URL:-https://github.com/DonMatteoVPN/TrafficGuard/releases/latest/download/install.sh}"
    echo -e "${CYAN}[*] Скачивание установщика TrafficGuard...${NC}"
    echo -e "${GRAY}    URL: ${tg_url}${NC}"

    # Используем mktemp для безопасного временного файла (БАГ #8 FIX)
    local install_tmp; install_tmp=$(safe_tmp "tg_install")

    if ! smart_curl "$tg_url" "$install_tmp" 60; then
        rm -f "$install_tmp"
        echo -e "${RED}[!] Не удалось скачать установщик TrafficGuard.${NC}"
        ui_pause; return 1
    fi

    # Проверяем что файл не пустой и выглядит как bash-скрипт
    if [[ ! -s "$install_tmp" ]]; then
        rm -f "$install_tmp"
        echo -e "${RED}[!] Скачанный файл пуст.${NC}"
        ui_pause; return 1
    fi

    if ! head -1 "$install_tmp" | grep -q "^#!.*bash\|^#!.*sh"; then
        echo -e "${YELLOW}[!] ПРЕДУПРЕЖДЕНИЕ: Файл не похож на bash-скрипт.${NC}"
        echo -e "${YELLOW}    Продолжить установку? (y/N)${NC}"
        read -rp ">> " confirm < /dev/tty
        if [[ ! "${confirm,,}" =~ ^y ]]; then
            rm -f "$install_tmp"
            return 1
        fi
    fi

    chmod +x "$install_tmp"
    echo -e "${CYAN}[*] Запуск установщика TrafficGuard...${NC}"
    if bash "$install_tmp"; then
        log_audit "TG_INSTALL" "TrafficGuard установлен"
        echo -e "${GREEN}[✓] TrafficGuard установлен!${NC}"
    else
        echo -e "${RED}[!] Установка завершилась с ошибкой.${NC}"
    fi
    rm -f "$install_tmp"
    ui_pause
}

# =============================================================================
# ВАЛИДАЦИЯ IP (БАГ #4 FIX)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: Проверяем что IP реально является корректным IP-адресом,
# прежде чем добавить его в ipset. Это защита от случайных опечаток.
is_valid_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$ ]]; then
        local base_ip="${ip%%/*}"
        local IFS_save="$IFS"; IFS='.'
        read -ra parts <<< "$base_ip"
        IFS="$IFS_save"
        for part in "${parts[@]}"; do
            (( part > 255 )) && return 1
        done
        return 0
    fi
    return 1
}

# =============================================================================
# УПРАВЛЕНИЕ СПИСКАМИ СКАНЕРОВ
# =============================================================================
tg_add_source() {
    clear
    echo -e "${MAGENTA}=== ДОБАВЛЕНИЕ ИСТОЧНИКА В TRAFFICGUARD ===${NC}"
    echo -e "${GRAY}Ссылка на файл со списком IP-адресов сканеров (URL или путь к файлу).${NC}\n"
    read -rp ">> URL или путь: " new_source < /dev/tty
    [[ -z "$new_source" ]] && return

    if ! grep -qxF "$new_source" "$TG_LISTS_FILE" 2>/dev/null; then
        echo "$new_source" >> "$TG_LISTS_FILE"
        log_audit "TG_SOURCE_ADD" "$new_source"
        echo -e "${GREEN}[+] Источник добавлен!${NC}"
    else
        echo -e "${YELLOW}[!] Источник уже есть в списке.${NC}"
    fi
    sleep 1
}

tg_remove_source() {
    clear
    echo -e "${MAGENTA}=== УДАЛЕНИЕ ИСТОЧНИКА ===${NC}"
    local i=1
    declare -a LIST_ARRAY
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        echo -e "  ${YELLOW}[$i]${NC} $entry"
        LIST_ARRAY[$i]="$entry"
        ((i++))
    done < "$TG_LISTS_FILE" 2>/dev/null
    [[ $i -eq 1 ]] && { echo -e "${GRAY}(Список пуст)${NC}"; sleep 1; return; }

    read -rp ">> Номер для удаления (0=отмена): " num < /dev/tty
    [[ "$num" == "0" || -z "$num" ]] && return

    if [[ "$num" =~ ^[0-9]+$ ]] && [[ -n "${LIST_ARRAY[$num]:-}" ]]; then
        local to_del="${LIST_ARRAY[$num]}"
        local tmpf; tmpf=$(safe_tmp "tg_list")
        grep -v -x -F "$to_del" "$TG_LISTS_FILE" > "$tmpf" && mv "$tmpf" "$TG_LISTS_FILE"
        log_audit "TG_SOURCE_DEL" "$to_del"
        echo -e "${GREEN}[+] Удалено!${NC}"; sleep 1
    fi
}

# Ручной бан IP через ipset (с валидацией! БАГ #4 FIX)
tg_manual_ban() {
    local ip; ip=$(ui_input_ip "Введите IP для блокировки")
    [[ -z "$ip" ]] && return

    if ! is_valid_ip "$ip"; then
        echo -e "${RED}[!] Некорректный IP-адрес: ${ip}${NC}"
        sleep 1; return
    fi

    # Добавляем в ipset если существует
    if ipset list SCANNERS-BLOCK-V4 >/dev/null 2>&1; then
        ipset add SCANNERS-BLOCK-V4 "$ip" 2>/dev/null && \
            echo -e "${GREEN}[+] IP ${ip} заблокирован через ipset.${NC}" || \
            echo -e "${YELLOW}[!] IP ${ip} уже в списке.${NC}"
    else
        echo -e "${YELLOW}[!] Ipset SCANNERS-BLOCK-V4 не найден. TrafficGuard установлен?${NC}"
    fi

    # Сохраняем в файл ручного бана
    if ! grep -qxF "$ip" "$TG_MANUAL_BAN" 2>/dev/null; then
        echo "$ip" >> "$TG_MANUAL_BAN"
    fi
    log_audit "TG_BAN" "$ip"
    sleep 1
}

tg_manual_unban() {
    local ip; ip=$(ui_input_ip "Введите IP для разблокировки")
    [[ -z "$ip" ]] && return

    ipset del SCANNERS-BLOCK-V4 "$ip" 2>/dev/null && \
        echo -e "${GREEN}[+] IP ${ip} разблокирован.${NC}" || \
        echo -e "${YELLOW}[!] IP ${ip} не найден в списке.${NC}"

    local tmpf; tmpf=$(safe_tmp "tg_unban")
    grep -v -x -F "$ip" "$TG_MANUAL_BAN" > "$tmpf" && mv "$tmpf" "$TG_MANUAL_BAN"
    log_audit "TG_UNBAN" "$ip"
    sleep 1
}

# =============================================================================
# ГЛАВНОЕ МЕНЮ TRAFFICGUARD
# =============================================================================
menu_tg() {
    while true; do
        clear
        ui_header "🛡️" "TRAFFICGUARD — ЗАЩИТА ОТ СКАНЕРОВ" "$(get_tg_status)"
        echo -e " ${GREEN}1.${NC} 📥 Установить / Обновить TrafficGuard"
        echo -e " ${YELLOW}2.${NC} 📋 Управление источниками (списки IP сканеров)"
        echo -e " ${YELLOW}3.${NC} ➕ Список источников"
        echo -e " ${YELLOW}4.${NC} ➖ Удалить источник"
        ui_sep
        echo -e " ${RED}5.${NC} 🔨 Заблокировать IP вручную"
        echo -e " ${GREEN}6.${NC} 🔓 Разблокировать IP"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " choice < /dev/tty
        case "$choice" in
            1) install_trafficguard ;;
            2)
                clear
                echo -e "${MAGENTA}=== ИСТОЧНИКИ TRAFFICGUARD ===${NC}\n"
                cat "$TG_LISTS_FILE" 2>/dev/null | nl -ba || echo -e "${GRAY}(Список пуст)${NC}"
                ui_pause ;;
            3) tg_add_source ;;
            4) tg_remove_source ;;
            5) tg_manual_ban ;;
            6) tg_manual_unban ;;
            0) return ;;
        esac
    done
}
