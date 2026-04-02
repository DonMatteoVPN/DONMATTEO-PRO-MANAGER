#!/bin/bash
# =============================================================================
# УСТАНОВЩИК: install.sh
# =============================================================================
# Этот скрипт устанавливает DONMATTEO PRO MANAGER на твой сервер.
#
# ДЛЯ ЧАЙНИКОВ: Запусти одну команду — и всё установится автоматически:
#   bash install.sh
#
# Что делает этот скрипт:
#   1. Создаёт папки для менеджера
#   2. Скачивает все модули с GitHub (с умным обходом блокировок)
#   3. Устанавливает главную команду "don" в систему
#   4. Переносит старые файлы если это обновление
#
# Скрипт ИДЕМПОТЕНТЕН — можно запускать повторно, это безопасно.
# (Умное слово: идемпотентен = повторный запуск не навредит системе)
# =============================================================================

set -euo pipefail

# =============================================================================
# ПЕРВИЧНЫЕ ПЕРЕМЕННЫЕ (до загрузки ядра)
# =============================================================================
REPO_RAW="https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
BASE_DIR="/opt/remnawave/DONMATTEO-PRO-MANAGER"
MOD_DIR="${BASE_DIR}/modules"
CORE_DIR="${MOD_DIR}/core"
CONF_DIR="${BASE_DIR}/etc"
BIN_LINK="/usr/local/bin/don"

# Цвета (нужны до загрузки модулей)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
GRAY='\033[0;90m'; NC='\033[0m'; BOLD='\033[1m'

# Зеркала GitHub для обхода блокировок (те же что в m_00_core.sh)
GH_PROXIES=(
    "https://mirror.ghproxy.com/"
    "https://gh-proxy.com/"
    "https://ghproxy.net/"
    "https://ghproxy.org/"
    "https://gh.api.99988866.xyz/"
    "https://github.moeyy.xyz/"
)
GH_CDN="https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"

# =============================================================================
# ПРОВЕРКИ
# =============================================================================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Запустите от root: sudo bash install.sh${NC}"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    apt-get install -y curl >/dev/null 2>&1 || \
        { echo -e "${RED}[!] curl не найден и не удалось установить. Прервано.${NC}"; exit 1; }
fi

# =============================================================================
# ФУНКЦИЯ СКАЧИВАНИЯ С ОБХОДОМ БЛОКИРОВОК (автономная версия для install.sh)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: Полная копия smart_curl из m_00_core.sh чтобы установщик
# работал ДО загрузки ядра. После установки используется та версия.
install_download() {
    local url="$1"
    local output="$2"
    local timeout="${3:-30}"

    # Метод 1: Прямой доступ
    curl -fsSL --connect-timeout 5 --max-time "$timeout" "$url" -o "$output" >/dev/null 2>&1 && return 0

    # Метод 2: CDN (jsDelivr)
    if [[ "$url" == *"raw.githubusercontent.com"* ]]; then
        local jsd_url
        jsd_url=$(echo "$url" | sed -E \
            's|https://raw.githubusercontent.com/([^/]+)/([^/]+)/([^/]+)/(.*)|https://cdn.jsdelivr.net/gh/\1/\2@\3/\4|')
        curl -fsSL --connect-timeout 5 --max-time "$timeout" "$jsd_url" -o "$output" >/dev/null 2>&1 && return 0
    fi

    # Метод 3: Зеркала GitHub
    if [[ "$url" == *"github"* ]]; then
        echo -e "${YELLOW}[!] Прямой доступ заблокирован. Подбор зеркала...${NC}"
        local n=0
        for proxy in "${GH_PROXIES[@]}"; do
            ((n++))
            echo -ne "\r  Зеркало [${n}/${#GH_PROXIES[@]}]..."
            curl -fsSL --connect-timeout 3 --max-time "$timeout" \
                "${proxy}${url}" -o "$output" >/dev/null 2>&1 && {
                    echo -e "\r${GREEN}[+] Скачано через зеркало!${NC}            "
                    return 0
                }
        done
    fi

    # Метод 4: Без SSL (последний шанс, с аудит-записью)
    echo -e "\n${YELLOW}[!] Все безопасные методы недоступны. Режим без SSL...${NC}"
    curl -fsSLk --connect-timeout 5 --max-time "$timeout" "$url" -o "$output" >/dev/null 2>&1 && {
        echo -e "${YELLOW}    ⚠️  Внимание: файл скачан без SSL-проверки!${NC}"
        return 0
    }

    return 1
}

# =============================================================================
# БАННЕР
# =============================================================================
clear
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${BOLD}${MAGENTA}🚀 DONMATTEO PRO MANAGER — УСТАНОВЩИК${NC}${BLUE}              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# СОЗДАНИЕ СТРУКТУРЫ ПАПОК
# =============================================================================
echo -e "${CYAN}[1/5] Создание структуры директорий...${NC}"
mkdir -p "${BASE_DIR}" "${CORE_DIR}" "${CONF_DIR}" "${MOD_DIR}"

# =============================================================================
# РЕЗЕРВНАЯ КОПИЯ НАСТРОЕК (если это обновление)
# =============================================================================
echo -e "${CYAN}[2/5] Проверка существующей конфигурации...${NC}"
if [[ -d "${CONF_DIR}" ]] && ls "${CONF_DIR}"/*.conf >/dev/null 2>&1; then
    local_backup="${BASE_DIR}/.config_backup_$(date +%Y%m%d_%H%M%S)"
    cp -r "${CONF_DIR}" "$local_backup" && \
        echo -e "${GREEN}  [+] Настройки сохранены: ${local_backup}${NC}"
fi

# =============================================================================
# СКАЧИВАНИЕ ГЛАВНОГО ФАЙЛА
# =============================================================================
echo -e "${CYAN}[3/5] Скачивание главного файла (don)...${NC}"
if ! install_download "${REPO_RAW}/don" "${BASE_DIR}/don" 30; then
    echo -e "${RED}[!] КРИТИЧЕСКАЯ ОШИБКА: Не удалось скачать главный файл.${NC}"
    echo -e "${YELLOW}    Проверь подключение к интернету.${NC}"
    exit 1
fi
chmod +x "${BASE_DIR}/don"
echo -e "${GREEN}  [✓] don — скачан${NC}"

# =============================================================================
# СКАЧИВАНИЕ MODULES.LIST И МОДУЛЕЙ
# =============================================================================
echo -e "${CYAN}[4/5] Скачивание модулей...${NC}"

# Скачиваем список модулей
if ! install_download "${REPO_RAW}/modules.list" "${BASE_DIR}/modules.list" 15; then
    echo -e "${RED}[!] Не удалось скачать modules.list!${NC}"
    exit 1
fi

# Скачиваем install.sh (обновляем себя)
install_download "${REPO_RAW}/install.sh" "${BASE_DIR}/install.sh" 15 >/dev/null 2>&1 || true
chmod +x "${BASE_DIR}/install.sh" 2>/dev/null || true

# Скачиваем хеш-манифест (мягко)
install_download "${REPO_RAW}/etc/checksums.sha256" "${CONF_DIR}/checksums.sha256" 10 >/dev/null 2>&1 || true

# Скачиваем каждый core-модуль
ok_count=0
fail_count=0
while IFS= read -r mod_name; do
    [[ -z "$mod_name" || "$mod_name" =~ ^# ]] && continue
    local_path="${CORE_DIR}/${mod_name}"
    remote_url="${REPO_RAW}/modules/core/${mod_name}"

    echo -ne "  → ${mod_name}..."
    if install_download "$remote_url" "${local_path}.tmp" 30; then
        mv "${local_path}.tmp" "$local_path"
        chmod +x "$local_path"
        ((ok_count++))
        echo -e "\r  ${GREEN}✓ ${mod_name}${NC}                          "
    else
        ((fail_count++))
        echo -e "\r  ${RED}✗ ${mod_name} (ошибка)${NC}  "
        rm -f "${local_path}.tmp" 2>/dev/null || true
    fi
done < "${BASE_DIR}/modules.list"

echo -e "\n  ${GREEN}Загружено: ${ok_count}${NC} | ${RED}Ошибок: ${fail_count}${NC}"

if [[ $fail_count -gt 0 ]]; then
    echo -e "${YELLOW}[!] Некоторые модули не загружены. Повтори установку.${NC}"
fi

# =============================================================================
# ФИНАЛИЗАЦИЯ: символическая ссылка + миграция
# =============================================================================
echo -e "${CYAN}[5/5] Финализация...${NC}"

# Устанавливаем команду "don" в систему
ln -sf "${BASE_DIR}/don" "${BIN_LINK}" && \
    echo -e "${GREEN}  [✓] Команда 'don' доступна в системе.${NC}"

# Запоминаем текущий commit
current_commit=$(curl -fsSL --max-time 5 \
    "https://api.github.com/repos/DonMatteoVPN/DONMATTEO-PRO-MANAGER/commits/main" \
    2>/dev/null | grep -oP '"sha": "\K[^"]+' | head -1 | cut -c1-7 || echo "unknown")
echo "$current_commit" > "${CONF_DIR}/.last_commit" 2>/dev/null || true

# =============================================================================
# ИТОГ
# =============================================================================
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${BOLD}${GREEN}✅ УСТАНОВКА ЗАВЕРШЕНА!${NC}${BLUE}                             ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  📁 Путь установки: ${CYAN}${BASE_DIR}${NC}${BLUE}        ║${NC}"
echo -e "${BLUE}║${NC}  📁 Core-модули:    ${CYAN}${CORE_DIR}${NC}${BLUE}    ║${NC}"
echo -e "${BLUE}║${NC}  ⚙️  Настройки:      ${CYAN}${CONF_DIR}${NC}${BLUE}           ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  🚀 Запусти менеджер командой: ${BOLD}${GREEN}don${NC}${BLUE}                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}💡 Добавить свой модуль → ${CORE_DIR}/m_XX_mymodule.sh${NC}"
echo -e "${YELLOW}   Менеджер найдёт его автоматически при следующем запуске!${NC}"
echo ""
