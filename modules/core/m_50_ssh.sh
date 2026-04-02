#!/bin/bash
# =============================================================================
# МОДУЛЬ SSH: m_50_ssh.sh
# =============================================================================
# Управление SSH-портами. SSH — это способ безопасного подключения к серверу.
#
# ДЛЯ ЧАЙНИКОВ: SSH-порт — это «номер двери» через которую ты заходишь
# на сервер. По умолчанию это порт 22, но для безопасности рекомендуется
# менять на нестандартный (например 2275). Менеджер автоматически обновляет
# UFW и Fail2Ban при изменении портов.
#
# ИСПРАВЛЕННЫЕ БАГИ:
#   - БАГ #20: sshd -t проверка конфига перед рестартом (нет потери SSH!)
# =============================================================================

# =============================================================================
# БЕЗОПАСНЫЙ РЕСТАРТ SSH (БАГ #20 FIX)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: Перед перезапуском SSH проверяем конфиг на ошибки.
# Это защищает от ситуации когда неправильная настройка SSH отключает тебя
# от сервера навсегда. "sshd -t" = Test mode (tест конфига).
ssh_safe_restart() {
    echo -ne "${CYAN}[*] Проверка конфигурации SSH (sshd -t)...${NC}"
    if sshd -t >/dev/null 2>&1; then
        echo -e " ${GREEN}[OK]${NC}"
    else
        echo -e " ${RED}[ОШИБКА!]${NC}"
        echo -e "${RED}[!] В конфиге SSH есть ошибки! Перезапуск отменён.${NC}"
        echo -e "${YELLOW}Подробности:${NC}"
        sshd -t 2>&1
        return 1
    fi

    # Определяем правильное имя сервиса (ssh или sshd)
    local ssh_service="ssh"
    systemctl is-active --quiet sshd 2>/dev/null && ssh_service="sshd"

    echo -ne "${CYAN}[*] Перезапуск SSH...${NC}"
    if systemctl restart "$ssh_service" 2>/dev/null; then
        sleep 1
        if systemctl is-active --quiet "$ssh_service"; then
            echo -e " ${GREEN}[OK]${NC}"
            return 0
        fi
    fi
    echo -e " ${RED}[ОШИБКА!]${NC}"
    echo -e "${RED}SSH не запустился. Паника? Нет! Текущее соединение активно.${NC}"
    echo -e "${YELLOW}Проверь: journalctl -u ssh -n 30${NC}"
    return 1
}

# =============================================================================
# ПОЛУЧЕНИЕ ТЕКУЩИХ SSH ПОРТОВ
# =============================================================================
get_ssh_ports() {
    grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tr '\n' ' '
}

# =============================================================================
# ДОБАВЛЕНИЕ SSH ПОРТА
# =============================================================================
ssh_add_port() {
    local newport; newport=$(ui_input_port "Введите новый SSH-порт")
    [[ -z "$newport" ]] && return

    local current_ports; current_ports=$(get_ssh_ports)

    # Проверяем что порт ещё не добавлен
    if echo "$current_ports" | grep -qw "$newport"; then
        echo -e "${YELLOW}[!] Порт ${newport} уже настроен в SSH.${NC}"
        sleep 1; return
    fi

    # Добавляем в sshd_config
    echo "Port ${newport}" >> /etc/ssh/sshd_config

    # Разрешаем в UFW (до перезапуска SSH!)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${newport}/tcp" comment "SSH-don" >/dev/null 2>&1
        echo -e "${GREEN}[+] UFW: порт ${newport}/tcp открыт.${NC}"
    fi

    # Обновляем Fail2Ban
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        f2b_safe_restart >/dev/null 2>&1 || true
    fi

    # Тестируем и рестартуем SSH
    if ssh_safe_restart; then
        log_audit "SSH_ADD_PORT" "${newport}"
        echo -e "${GREEN}[✓] SSH теперь слушает также на порту ${newport}${NC}"
        echo -e "${YELLOW}    ⚠️ Не закрывай текущий сеанс! Проверь подключение на новом порту.${NC}"
    else
        # Откатываем если рестарт не удался
        local tmpf; tmpf=$(safe_tmp "sshd_conf")
        grep -v "^Port ${newport}" /etc/ssh/sshd_config > "$tmpf"
        mv "$tmpf" /etc/ssh/sshd_config
        echo -e "${RED}[!] Откат: порт ${newport} удалён из конфига.${NC}"
    fi
    sleep 2
}

# =============================================================================
# УДАЛЕНИЕ SSH ПОРТА
# =============================================================================
ssh_remove_port() {
    local current_ports; current_ports=$(get_ssh_ports)
    local port_count; port_count=$(echo "$current_ports" | wc -w)

    # Минимум один порт должен остаться!
    if [[ $port_count -le 1 ]]; then
        echo -e "${RED}[!] Нельзя удалить — это единственный SSH порт!${NC}"
        echo -e "${YELLOW}    Сначала добавь другой порт, потом удаляй этот.${NC}"
        sleep 2; return
    fi

    echo -e "${CYAN}Текущие SSH порты: ${YELLOW}${current_ports}${NC}"
    local delport; delport=$(ui_input_port "Введите порт для удаления")
    [[ -z "$delport" ]] && return

    # Дополнительная защита — не удаляем порт 22 если он единственный
    if ! echo "$current_ports" | grep -qw "$delport"; then
        echo -e "${YELLOW}[!] Порт ${delport} не найден в конфиге SSH.${NC}"
        sleep 1; return
    fi

    # Удаляем из sshd_config атомарно
    local tmpf; tmpf=$(safe_tmp "sshd_conf")
    grep -v "^Port ${delport}" /etc/ssh/sshd_config > "$tmpf"
    mv "$tmpf" /etc/ssh/sshd_config

    if ssh_safe_restart; then
        # Закрываем в UFW
        if command -v ufw >/dev/null 2>&1; then
            ufw delete allow "${delport}/tcp" >/dev/null 2>&1 || true
        fi
        log_audit "SSH_DEL_PORT" "${delport}"
        echo -e "${GREEN}[✓] Порт ${delport} удалён из SSH.${NC}"
    else
        # Откат
        echo "Port ${delport}" >> /etc/ssh/sshd_config
        echo -e "${RED}[!] Откат: порт ${delport} восстановлен.${NC}"
    fi
    sleep 2
}

# =============================================================================
# ГЛАВНОЕ МЕНЮ SSH
# =============================================================================
menu_ssh() {
    while true; do
        clear
        ui_header "🔑" "УПРАВЛЕНИЕ SSH" "$(get_ssh_status)"
        local ports; ports=$(get_ssh_ports)
        echo -e " ${GRAY}Активные порты SSH: ${YELLOW}${ports:-22}${NC}\n"
        echo -e " ${GREEN}1.${NC} ➕ Добавить SSH-порт"
        echo -e " ${RED}2.${NC} ➖ Удалить SSH-порт"
        echo -e " ${YELLOW}3.${NC} 📋 Показать конфигурацию SSH"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " choice < /dev/tty
        case "$choice" in
            1) ssh_add_port ;;
            2) ssh_remove_port ;;
            3)
                clear
                echo -e "${YELLOW}=== /etc/ssh/sshd_config (активные настройки) ===${NC}\n"
                grep -vE "^#|^$" /etc/ssh/sshd_config 2>/dev/null
                ui_pause ;;
            0) return ;;
        esac
    done
}
