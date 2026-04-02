#!/bin/bash
# =============================================================================
# МОДУЛЬ НАСТРОЕК: m_20_config.sh
# =============================================================================
# Система глобальных настроек проекта через меню.
# Все пути, порты и URL можно менять прямо из интерфейса без редактирования кода.
#
# ДЛЯ ЧАЙНИКОВ: Здесь хранятся все важные настройки менеджера.
# Если тебе нужно изменить путь к папке или порт панели — зайди в
# Главное Меню → ⚙️ Настройки. Файл настроек: /opt/.../etc/settings.conf
# =============================================================================

# --- Файл настроек ---
SETTINGS_FILE="${CONF_DIR}/settings.conf"

# =============================================================================
# ЗАГРУЗКА НАСТРОЕК В ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ (вызывается при старте)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: При запуске менеджер читает все сохранённые настройки
# и устанавливает их как переменные для использования во всех модулях.
load_settings() {
    [[ ! -f "$SETTINGS_FILE" ]] && return 0
    # Читаем KEY=VALUE пары безопасно (без eval)
    while IFS='=' read -r key value; do
        # Пропускаем комментарии и пустые строки
        [[ "$key" =~ ^#|^[[:space:]]*$ ]] && continue
        # Убираем пробелы вокруг значения
        key="${key// /}"
        value="${value## }"; value="${value%% }"
        # Экспортируем только известные переменные
        case "$key" in
            NGINX_LOGS_DIR|XRAY_ASSETS_DIR|SCANNER_DIR|F2B_FILTER_DIR|\
            PANEL_PORT|AUDIT_LOG|AUDIT_LOG_ENABLED|\
            REPO_URL|TG_INSTALL_URL)
                export "$key"="$value"
                ;;
        esac
    done < "$SETTINGS_FILE"
}

# --- Чтение одного параметра ---
conf_get() {
    local key="$1"
    local default="${2:-}"
    if [[ -f "$SETTINGS_FILE" ]]; then
        local val; val=$(grep -m1 "^${key}=" "$SETTINGS_FILE" 2>/dev/null | cut -d= -f2-)
        [[ -n "$val" ]] && echo "$val" && return
    fi
    echo "$default"
}

# --- Запись/обновление параметра ---
conf_set() {
    local key="$1"
    local value="$2"
    mkdir -p "${CONF_DIR}"
    if [[ -f "$SETTINGS_FILE" ]] && grep -q "^${key}=" "$SETTINGS_FILE" 2>/dev/null; then
        # Безопасное обновление — через temp файл (БАГ #14 FIX)
        local tmpfile; tmpfile=$(safe_tmp "conf")
        sed "s|^${key}=.*|${key}=${value}|" "$SETTINGS_FILE" > "$tmpfile"
        mv "$tmpfile" "$SETTINGS_FILE"
    else
        echo "${key}=${value}" >> "$SETTINGS_FILE"
    fi
    export "$key"="$value"
    log_audit "SETTINGS" "Изменено: ${key}=${value}"
}

# =============================================================================
# ДЕФОЛТНЫЕ ЗНАЧЕНИЯ (если settings.conf не существует)
# =============================================================================
NGINX_LOGS_DIR="${NGINX_LOGS_DIR:-/opt/remnawave/nginx_logs}"
XRAY_ASSETS_DIR="${XRAY_ASSETS_DIR:-/opt/remnawave/xray/share}"
SCANNER_DIR="${SCANNER_DIR:-/opt/RealiTLScanner}"
F2B_FILTER_DIR="${F2B_FILTER_DIR:-/etc/fail2ban/filter.d}"
PANEL_PORT="${PANEL_PORT:-2222}"
AUDIT_LOG="${AUDIT_LOG:-/var/log/don_audit.log}"
AUDIT_LOG_ENABLED="${AUDIT_LOG_ENABLED:-true}"
REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main}"
TG_INSTALL_URL="${TG_INSTALL_URL:-https://github.com/DonMatteoVPN/TrafficGuard/releases/latest/download/install.sh}"

# =============================================================================
# МЕНЮ: ПУТИ И ДИРЕКТОРИИ
# =============================================================================
menu_config_paths() {
    while true; do
        clear
        ui_header "📁" "ПУТИ И ДИРЕКТОРИИ"
        echo -e " Здесь можно изменить, куда смотрят модули менеджера.\n"
        echo -e " ${YELLOW}1.${NC} Nginx логи нашей панели"
        echo -e "   ${CYAN}→ Текущий:${NC} ${NGINX_LOGS_DIR}"
        echo -e " ${YELLOW}2.${NC} Xray Assets (базы Zapret/GeoSite/GeoIP)"
        echo -e "   ${CYAN}→ Текущий:${NC} ${XRAY_ASSETS_DIR}"
        echo -e " ${YELLOW}3.${NC} Директория Reality Scanner"
        echo -e "   ${CYAN}→ Текущий:${NC} ${SCANNER_DIR}"
        echo -e " ${YELLOW}4.${NC} Директория фильтров Fail2Ban"
        echo -e "   ${CYAN}→ Текущий:${NC} ${F2B_FILTER_DIR}"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1)
                echo -e "${GRAY}Введите новый путь к папке Nginx логов (должна существовать):${NC}"
                local new_val; new_val=$(ui_input "Путь" "$NGINX_LOGS_DIR")
                if [[ -n "$new_val" ]]; then
                    mkdir -p "$new_val" 2>/dev/null
                    conf_set "NGINX_LOGS_DIR" "$new_val"
                    echo -e "${GREEN}[+] Сохранено! Рестарт Fail2Ban для применения...${NC}"
                    systemctl restart fail2ban 2>/dev/null || true
                    sleep 1
                fi ;;
            2)
                local new_val; new_val=$(ui_input "Путь к Xray Assets" "$XRAY_ASSETS_DIR")
                [[ -n "$new_val" ]] && mkdir -p "$new_val" && conf_set "XRAY_ASSETS_DIR" "$new_val"
                echo -e "${GREEN}[+] Готово!${NC}"; sleep 1 ;;
            3)
                local new_val; new_val=$(ui_input "Путь к Scanner" "$SCANNER_DIR")
                [[ -n "$new_val" ]] && mkdir -p "$new_val" && conf_set "SCANNER_DIR" "$new_val"
                echo -e "${GREEN}[+] Готово!${NC}"; sleep 1 ;;
            4)
                local new_val; new_val=$(ui_input "Путь к фильтрам Fail2Ban" "$F2B_FILTER_DIR")
                [[ -n "$new_val" ]] && conf_set "F2B_FILTER_DIR" "$new_val"
                echo -e "${GREEN}[+] Готово!${NC}"; sleep 1 ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# МЕНЮ: ПОРТЫ И СЕРВИСЫ
# =============================================================================
menu_config_ports() {
    while true; do
        clear
        ui_header "🔌" "ПОРТЫ И СЕРВИСЫ"
        echo -e " ${YELLOW}1.${NC} Порт панели Remna (для белого списка Fail2Ban/UFW)"
        echo -e "   ${CYAN}→ Текущий:${NC} ${PANEL_PORT}"
        echo -e "   ${GRAY}   Важно: укажи порт твоей панели Remnawave (обычно 2222 или 3000)${NC}"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1)
                echo -e "${GRAY}Введи порт, на котором работает панель Remnawave:${NC}"
                local new_port; new_port=$(ui_input_port "Порт панели" "$PANEL_PORT")
                conf_set "PANEL_PORT" "$new_port"
                echo -e "${GREEN}[+] Порт панели обновлён: ${new_port}${NC}"; sleep 1 ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# МЕНЮ: URL ИСТОЧНИКОВ
# =============================================================================
menu_config_urls() {
    while true; do
        clear
        ui_header "🌐" "URL ИСТОЧНИКОВ"
        echo -e " Измени ссылки для скачивания модулей и установщиков.\n"
        echo -e " ${YELLOW}1.${NC} URL репозитория менеджера (для обновлений)"
        echo -e "   ${CYAN}→${NC} $(conf_get REPO_URL "$REPO_URL")"
        echo -e " ${YELLOW}2.${NC} URL установщика TrafficGuard"
        echo -e "   ${CYAN}→${NC} $(conf_get TG_INSTALL_URL "$TG_INSTALL_URL")"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1)
                local new_url; new_url=$(ui_input_url "URL репозитория")
                [[ -n "$new_url" ]] && conf_set "REPO_URL" "$new_url"
                echo -e "${GREEN}[+] Сохранено!${NC}"; sleep 1 ;;
            2)
                local new_url; new_url=$(ui_input_url "URL TrafficGuard")
                [[ -n "$new_url" ]] && conf_set "TG_INSTALL_URL" "$new_url"
                echo -e "${GREEN}[+] Сохранено!${NC}"; sleep 1 ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# МЕНЮ: АУДИТ-ЛОГ
# =============================================================================
menu_config_audit() {
    while true; do
        clear
        ui_header "🔔" "АУДИТ-ЛОГ ДЕЙСТВИЙ"
        echo -e " ${GRAY}Журнал фиксирует все важные действия: бан/разбан, смена портов, правила...${NC}\n"
        local status_str
        [[ "$AUDIT_LOG_ENABLED" == "true" ]] && \
            status_str="${GREEN}[ВКЛЮЧЁН]${NC}" || status_str="${RED}[ВЫКЛЮЧЕН]${NC}"
        echo -e " Статус: ${status_str}"
        echo -e " Файл:   ${CYAN}${AUDIT_LOG}${NC}"
        echo -e " Размер: ${GRAY}$(du -sh "${AUDIT_LOG}" 2>/dev/null | awk '{print $1}' || echo '0')${NC}\n"
        echo -e " ${YELLOW}1.${NC} Включить/Выключить аудит-лог"
        echo -e " ${YELLOW}2.${NC} Посмотреть последние 50 записей"
        echo -e " ${YELLOW}3.${NC} Изменить путь к файлу лога"
        echo -e " ${RED}4.${NC} Очистить аудит-лог"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1)
                if [[ "$AUDIT_LOG_ENABLED" == "true" ]]; then
                    conf_set "AUDIT_LOG_ENABLED" "false"; AUDIT_LOG_ENABLED="false"
                    echo -e "${YELLOW}[i] Аудит-лог выключен.${NC}"
                else
                    conf_set "AUDIT_LOG_ENABLED" "true"; AUDIT_LOG_ENABLED="true"
                    echo -e "${GREEN}[+] Аудит-лог включён.${NC}"
                fi
                sleep 1 ;;
            2)
                clear; echo -e "${YELLOW}=== Последние 50 записей аудит-лога ===${NC}\n"
                tail -n 50 "${AUDIT_LOG}" 2>/dev/null || echo -e "${GRAY}(Лог пуст или не найден)${NC}"
                ui_pause ;;
            3)
                local new_log; new_log=$(ui_input "Путь к файлу" "$AUDIT_LOG")
                [[ -n "$new_log" ]] && conf_set "AUDIT_LOG" "$new_log" && AUDIT_LOG="$new_log"
                echo -e "${GREEN}[+] Путь обновлён.${NC}"; sleep 1 ;;
            4)
                if ui_confirm "Очистить аудит-лог?" "N"; then
                    > "${AUDIT_LOG}" 2>/dev/null
                    echo -e "${GREEN}[+] Лог очищен.${NC}"
                else
                    echo -e "${YELLOW}[i] Отменено.${NC}"
                fi
                sleep 1 ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# МЕНЮ: ЭКСПОРТ / ИМПОРТ
# =============================================================================
menu_config_export() {
    while true; do
        clear
        ui_header "🗂️" "ЭКСПОРТ / ИМПОРТ НАСТРОЕК"
        echo -e " ${YELLOW}1.${NC} 📤 Экспортировать текущие настройки в файл"
        echo -e " ${YELLOW}2.${NC} 📥 Импортировать настройки из файла"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1)
                local export_path; export_path=$(ui_input "Путь для сохранения" "/root/don_settings_$(date +%Y%m%d).conf")
                if [[ -n "$export_path" ]]; then
                    cp "$SETTINGS_FILE" "$export_path" 2>/dev/null && \
                        echo -e "${GREEN}[+] Экспортировано: ${export_path}${NC}" || \
                        echo -e "${RED}[!] Ошибка экспорта.${NC}"
                fi
                sleep 2 ;;
            2)
                local import_path; import_path=$(ui_input "Путь к файлу настроек" "/root/don_settings.conf")
                if [[ -f "$import_path" ]]; then
                    cp "$import_path" "$SETTINGS_FILE" 2>/dev/null
                    load_settings
                    echo -e "${GREEN}[+] Импортировано! Настройки применены.${NC}"
                else
                    echo -e "${RED}[!] Файл не найден: ${import_path}${NC}"
                fi
                sleep 2 ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# ГЛАВНОЕ МЕНЮ НАСТРОЕК
# =============================================================================
menu_config() {
    while true; do
        clear
        ui_header "⚙️" "ГЛОБАЛЬНЫЕ НАСТРОЙКИ" "Управляй всеми параметрами менеджера из одного места."
        echo -e " ${GREEN}1.${NC} 📁 Пути и Директории"
        echo -e " ${GREEN}2.${NC} 🔌 Порты и Сервисы"
        echo -e " ${GREEN}3.${NC} 🌐 URL источников"
        echo -e " ${GREEN}4.${NC} 🔔 Аудит-лог действий"
        echo -e " ${GREEN}5.${NC} 🗂️  Экспорт / Импорт настроек"
        ui_sep
        echo -e " ${YELLOW}6.${NC} 📋 Показать все текущие настройки"
        echo -e " ${YELLOW}7.${NC} 🔄 Сбросить к дефолтным настройкам"
        ui_sep
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " ch < /dev/tty
        case "$ch" in
            1) menu_config_paths ;;
            2) menu_config_ports ;;
            3) menu_config_urls ;;
            4) menu_config_audit ;;
            5) menu_config_export ;;
            6)
                clear
                ui_header "📋" "ТЕКУЩИЕ НАСТРОЙКИ"
                if [[ -f "$SETTINGS_FILE" ]]; then
                    echo -e "${CYAN}Файл: ${SETTINGS_FILE}${NC}\n"
                    while IFS='=' read -r k v; do
                        [[ "$k" =~ ^# ]] && continue
                        printf " ${YELLOW}%-25s${NC} ${GREEN}%s${NC}\n" "$k" "$v"
                    done < "$SETTINGS_FILE"
                else
                    echo -e " ${GRAY}(Файл настроек не создан — используются дефолтные значения)${NC}"
                fi
                ui_pause ;;
            7)
                if ui_confirm "Сбросить ВСЕ настройки к дефолтным?" "N"; then
                    rm -f "$SETTINGS_FILE" 2>/dev/null
                    rm -f "${BASE_DIR}/etc/.mirror.cache" 2>/dev/null
                    log_audit "SETTINGS" "Сброс к дефолтным настройкам"
                    echo -e "${GREEN}[+] Настройки сброшены! Перезапусти менеджер.${NC}"
                fi
                sleep 2 ;;
            0) return ;;
        esac
    done
}
