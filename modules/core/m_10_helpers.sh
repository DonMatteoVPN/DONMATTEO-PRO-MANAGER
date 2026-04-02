#!/bin/bash
# =============================================================================
# МОДУЛЬ ХЕЛПЕРОВ: m_10_helpers.sh
# =============================================================================
# Загружается вторым. Содержит все вспомогательные функции:
# - Красивый вывод (UI): заголовки, разделители, цветные сообщения
# - Валидаторы ввода: IP, порты, URL
# - Аудит-лог: запись всех действий администратора
# - Функции статуса всех модулей (единое место — нет дублирования!)
#
# ДЛЯ ЧАЙНИКОВ: Этот файл отвечает за красивый вид интерфейса и за то,
# чтобы ты не мог случайно ввести неправильное значение. Все меню
# в менеджере используют функции отсюда.
# =============================================================================

# =============================================================================
# UI: ЕДИНЫЙ СТИЛЬ ИНТЕРФЕЙСА (БАГ #16 FIX — нет больше дублирования!)
# =============================================================================

# Рисует заголовок меню с иконкой и названием
ui_header() {
    local icon="${1:-🛠️}"
    local title="${2:-МЕНЮ}"
    local subtitle="${3:-}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${MAGENTA}  ${icon} ${title}${NC}"
    [[ -n "$subtitle" ]] && echo -e "${GRAY} ${subtitle}${NC}"
    echo -e "${BLUE}======================================================${NC}"
}

# Тонкий разделитель
ui_sep() {
    echo -e "${BLUE}------------------------------------------------------${NC}"
}

# Пауза "Нажмите Enter"
ui_pause() {
    echo -e "\n${CYAN}Нажмите [Enter] для возврата...${NC}"
    read -r < /dev/tty
}
# Экспортируем как pause для обратной совместимости
pause() { ui_pause; }
export -f pause

# Подтверждение действия (возвращает 0=да, 1=нет)
ui_confirm() {
    local prompt="${1:-Вы уверены?}"
    local default="${2:-Y}"
    local answer
    if [[ "$default" == "Y" ]]; then
        read -rp "${prompt} [Y/n]: " answer < /dev/tty
        answer="${answer:-Y}"
    else
        read -rp "${prompt} [y/N]: " answer < /dev/tty
        answer="${answer:-N}"
    fi
    [[ "${answer,,}" =~ ^[yдyes] ]] && return 0 || return 1
}

# Запрос значения с подсказкой и дефолтом
ui_input() {
    local prompt="$1"
    local default="${2:-}"
    local result
    if [[ -n "$default" ]]; then
        read -rp "${prompt} [${default}]: " result < /dev/tty
        echo "${result:-$default}"
    else
        read -rp "${prompt}: " result < /dev/tty
        echo "$result"
    fi
}

# Запрос порта с валидацией (1-65535)
ui_input_port() {
    local prompt="${1:-Введите порт}"
    local default="${2:-}"
    local port
    while true; do
        port=$(ui_input "$prompt" "$default")
        if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
            echo "$port"
            return 0
        fi
        echo -e "${RED}[!] Ошибка: порт должен быть числом от 1 до 65535.${NC}" >&2
    done
}

# Запрос IPv4 с валидацией
ui_input_ip() {
    local prompt="${1:-Введите IP-адрес}"
    local ip
    while true; do
        read -rp "${prompt}: " ip < /dev/tty
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            # Проверяем каждый октет
            local valid=true
            IFS='.' read -ra octets <<< "$ip"
            for oct in "${octets[@]}"; do
                (( oct > 255 )) && valid=false && break
            done
            [[ "$valid" == "true" ]] && { echo "$ip"; return 0; }
        fi
        echo -e "${RED}[!] Ошибка: введите корректный IPv4-адрес (например: 192.168.1.1).${NC}" >&2
    done
}

# Запрос URL с базовой валидацией
ui_input_url() {
    local prompt="${1:-Введите URL}"
    local url
    while true; do
        read -rp "${prompt}: " url < /dev/tty
        if [[ "$url" =~ ^https?:// ]]; then
            echo "$url"
            return 0
        fi
        echo -e "${RED}[!] URL должен начинаться с http:// или https://${NC}" >&2
    done
}

# =============================================================================
# АУДИТ-ЛОГ (БАГ #19 FIX — теперь все действия записываются)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: Каждое важное действие (бан IP, изменение порта, установка
# правила) записывается в лог-файл с временем и подробностями.
# Лог: /var/log/don_audit.log
log_audit() {
    local action="$1"
    local detail="${2:-}"
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user="${SUDO_USER:-root}"
    local msg="[${timestamp}] [${user}] ${action}"
    [[ -n "$detail" ]] && msg="${msg}: ${detail}"
    echo "$msg" >> "${AUDIT_LOG:-/var/log/don_audit.log}" 2>/dev/null || true
}

# =============================================================================
# ФУНКЦИИ СТАТУСА (БАГ #16 FIX — единое место, нет дублирования в файлах)
# =============================================================================

# Статус sysctl (BBR и защита ядра)
get_sysctl_status() {
    if [[ "$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)" == "1" ]]; then
        echo -e "${GREEN}[ВКЛЮЧЕНО]${NC}"
    else
        echo -e "${RED}[НЕ УСТАНОВЛЕНО]${NC}"
    fi
}

# Статус UFW (сетевой экран)
get_ufw_status() {
    if [[ "${OS_TYPE:-linux}" == "macos" ]]; then echo -e "${YELLOW}[N/A]${NC}"; return; fi
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "${RED}[НЕ УСТАНОВЛЕН]${NC}"; return
    fi
    if ufw status 2>/dev/null | grep -qw "active"; then
        echo -e "${GREEN}[РАБОТАЕТ]${NC}"
    else
        echo -e "${YELLOW}[ВЫКЛЮЧЕН]${NC}"
    fi
}

# Статус Fail2Ban
get_f2b_status() {
    if [[ "${OS_TYPE:-linux}" == "macos" ]]; then echo -e "${YELLOW}[N/A]${NC}"; return; fi
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "${RED}[НЕ УСТАНОВЛЕН]${NC}"; return
    fi
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        echo -e "${GREEN}[РАБОТАЕТ]${NC}"
    else
        echo -e "${YELLOW}[ОСТАНОВЛЕН]${NC}"
    fi
}

# Статус TrafficGuard
get_tg_status() {
    if [[ "${OS_TYPE:-linux}" == "macos" ]]; then echo -e "${YELLOW}[N/A]${NC}"; return; fi
    if systemctl is-active --quiet antiscan-aggregate.timer 2>/dev/null; then
        echo -e "${GREEN}[РАБОТАЕТ]${NC}"
    elif [[ -f /usr/local/bin/traffic-guard ]]; then
        echo -e "${YELLOW}[УСТАНОВЛЕН, НЕ АКТИВЕН]${NC}"
    else
        echo -e "${RED}[НЕ УСТАНОВЛЕНО]${NC}"
    fi
}

# Статус SWAP/ZRAM
get_swap_status() {
    local swp; swp=$(free -m 2>/dev/null | awk '/^Swap:/ {print $2}')
    local has_zram; has_zram=$(lsblk 2>/dev/null | grep -i zram)
    local has_file; has_file=$(swapon --show --noheadings 2>/dev/null | grep -i "/swapfile")

    if [[ -n "$has_zram" && -n "$has_file" ]]; then
        echo -e "${GREEN}[ГИБРИД: ZRAM + Swap]${NC}"
    elif [[ -n "$has_zram" ]]; then
        echo -e "${GREEN}[ZRAM: ${swp} MB]${NC}"
    elif [[ -n "$swp" && "$swp" != "0" ]]; then
        echo -e "${YELLOW}[DISK SWAP: ${swp} MB]${NC}"
    else
        echo -e "${RED}[ВЫКЛЮЧЕН]${NC}"
    fi
}

# Статус SSH
get_ssh_status() {
    if [[ "${OS_TYPE:-linux}" == "macos" ]]; then echo -e "${YELLOW}[N/A]${NC}"; return; fi
    local status_text
    if systemctl is-active --quiet ssh 2>/dev/null || \
       systemctl is-active --quiet sshd 2>/dev/null; then
        status_text="${GREEN}[РАБОТАЕТ]${NC}"
    else
        status_text="${RED}[ВЫКЛЮЧЕН]${NC}"
    fi
    local ports; ports=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | \
        awk '{print $2}' | paste -sd ',' -)
    [[ -z "$ports" ]] && ports="22"
    echo -e "${status_text} ${GRAY}(Порт(ы): ${ports})${NC}"
}

# Статус автообновления Xray ассетов
get_node_status() {
    if crontab -l 2>/dev/null | grep -q "update_assets.sh"; then
        echo -e "${GREEN}[Автообновление: ВКЛ]${NC}"
    else
        echo -e "${GRAY}[Автообновление: ВЫКЛ]${NC}"
    fi
}

# Статус логротации
get_logrotate_status() {
    local rules_count; rules_count=$(ls /etc/logrotate.d/don_* 2>/dev/null | wc -l)
    if [[ "$rules_count" -gt 0 ]]; then
        echo -e "${GREEN}[Активно: ${rules_count} правил]${NC}"
    else
        echo -e "${RED}[НЕ НАСТРОЕНО]${NC}"
    fi
}

# Статус модуля настроек
get_config_status() {
    local cfg="${CONF_DIR}/settings.conf"
    if [[ -f "$cfg" ]]; then
        local count; count=$(grep -c "=" "$cfg" 2>/dev/null || echo "0")
        echo -e "${GREEN}[${count} настроек]${NC}"
    else
        echo -e "${GRAY}[Дефолт]${NC}"
    fi
}

# =============================================================================
# ВЫВОД ИНФОРМАЦИИ О СИСТЕМЕ
# =============================================================================
show_system_info() {
    local ram_total; ram_total=$(free -m | awk '/^Mem:/{print $2}')
    local ram_used; ram_used=$(free -m | awk '/^Mem:/{print $3}')
    local disk_free; disk_free=$(df -BM / | awk 'NR==2{print $4}' | tr -d 'M')
    local uptime_str; uptime_str=$(uptime -p 2>/dev/null || uptime)
    local cpu_model; cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    echo -e " ${GRAY}RAM: ${ram_used}/${ram_total} MB | Диск: ${disk_free} MB свободно | Uptime: ${uptime_str}${NC}"
}

# =============================================================================
# ЧИСЛОВОЙ СОРТИРОВЩИК МОДУЛЕЙ
# =============================================================================
# Возвращает список модулей в порядке числового приоритета (m_00_, m_10_, ...)
list_core_modules_sorted() {
    local core_dir="${CORE_DIR:-${BASE_DIR}/modules/core}"
    [[ -d "$core_dir" ]] || return 0
    # Сортируем по числовому префиксу
    find "$core_dir" -maxdepth 1 -name 'm_[0-9][0-9]_*.sh' 2>/dev/null | sort
}

# Возвращает пользовательские модули (в modules/, не в core/)
list_user_modules() {
    local mod_dir="${MOD_DIR:-${BASE_DIR}/modules}"
    [[ -d "$mod_dir" ]] || return 0
    find "$mod_dir" -maxdepth 1 -name 'm_*.sh' 2>/dev/null | sort
}
