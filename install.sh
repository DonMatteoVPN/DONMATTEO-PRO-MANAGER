#!/bin/bash
# ======================================================================
# Установщик TRAFFICGUARD PRO MANAGER (Standardized v2)
# ======================================================================

# Основные настройки
BASE_DIR="/opt/remnawave/DONMATTEO-PRO-MANAGER"
BIN_PATH="/usr/local/bin/don"
REPO_RAW="https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
MIRRORS=(
    "https://mirror.ghproxy.com/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
    "https://gh-proxy.com/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
    "https://ghproxy.net/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
    "https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Глобальные переменные для скорости
export FAST_MIRROR=""

# 0. ОЧИСТКА И МИГРАЦИЯ (Защита от конфликтов)
cleanup_legacy() {
    echo -e "${CYAN}[*] Глубокая очистка системы от старых версий...${NC}"
    
    # 1. Удаляем призрачные бинарники
    if [[ -f "/usr/local/bin/don" ]]; then
        rm -f "/usr/local/bin/don"
    fi

    # 2. Обработка основной папки проекта
    if [[ -d "$BASE_DIR" ]]; then
        # Если есть конфиги - спасаем их!
        if [[ -d "${BASE_DIR}/etc" ]]; then
            echo -e "${YELLOW} [!] Найдены существующие конфиги. Создаем временный бекап...${NC}"
            cp -r "${BASE_DIR}/etc" "/tmp/don_conf_bak"
        fi
        
        # Полная зачистка (чтобы не было старых битых модулей)
        echo -e "${GRAY}  --> Удаление старых файлов проекта...${NC}"
        rm -rf "$BASE_DIR"
    fi
    
    # 3. Восстановление структуры
    mkdir -p "${BASE_DIR}/modules"
    mkdir -p "${BASE_DIR}/etc"
    
    if [[ -d "/tmp/don_conf_bak" ]]; then
        cp -r "/tmp/don_conf_bak/"* "${BASE_DIR}/etc/" 2>/dev/null
        rm -rf "/tmp/don_conf_bak"
        echo -e "${GREEN} [+] Конфигурации успешно восстановлены.${NC}"
    fi
}

# 0.1 СИСТЕМА ЗОНДИРОВАНИЯ (Speed Probe)
find_fastest_mirror() {
    echo -e "${CYAN}[*] Зондирование сети: Поиск лучшего канала...${NC}"
    local test_file="don"
    local TS=$(date +%s)
    
    # Список кандидатов (приоритет: CDN -> Прокси -> Напрямую)
    local candidates=(
        "https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"
        "https://mirror.ghproxy.com/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
        "https://ghproxy.net/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
        "https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
    )

    for base in "${candidates[@]}"; do
        local url="${base}/${test_file}?t=${TS}"
        if curl -fsSL --connect-timeout 1 --max-time 2 "$url" -o /dev/null >/dev/null 2>&1; then
            export FAST_MIRROR="$base"
            echo -e "${GREEN}[+] Выбран канал: ${FAST_MIRROR}${NC}"
            return 0
        fi
    done
}

# Авто-исправление DNS
smart_dns_fix() {
    if ! host raw.githubusercontent.com >/dev/null 2>&1 && ! host github.com >/dev/null 2>&1; then
        echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
    fi
}

# Простейшая функция скачивания для инсталлера
smart_download() {
    local path=$1
    local output=$2
    
    # 0. Если у нас есть FAST_MIRROR
    if [[ -n "$FAST_MIRROR" ]]; then
        local url="${FAST_MIRROR}/${path}"
        [[ "$FAST_MIRROR" == *"jsdelivr"* ]] && url="${FAST_MIRROR}/${path}?t=$(date +%s)"
        if curl -fsSL --connect-timeout 2 --max-time 15 "$url" -o "$output" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 1. Сначала пытаемся напрямую (быстро)
    if curl -fsSL --connect-timeout 2 --max-time 15 "${REPO_RAW}/${path}" -o "$output" >/dev/null 2>&1; then
        return 0
    fi

    # 2. Фикс DNS и повтор
    smart_dns_fix
    if curl -fsSL --connect-timeout 2 --max-time 15 "${REPO_RAW}/${path}" -o "$output" >/dev/null 2>&1; then
        return 0
    fi

    # 3. Затем по зеркалам (быстрый перебор)
    for mirror in "${MIRRORS[@]}"; do
        if curl -fsSL --connect-timeout 2 --max-time 15 "${mirror}/${path}" -o "$output" >/dev/null 2>&1; then
            return 0
        fi
    done

    # 4. Режим "Отчаяние": без проверки SSL
    if curl -fsSLk --connect-timeout 5 --max-time 20 "${REPO_RAW}/${path}" -o "$output" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Запустите установку от имени root (sudo).${NC}"
    exit 1
fi

clear
echo -e "${CYAN}================================================================${NC}"
echo -e "${BOLD}${MAGENTA} 🚀 УСТАНОВКА / ОБНОВЛЕНИЕ TRAFFICGUARD PRO${NC}"
echo -e "${CYAN}================================================================${NC}"

echo -e "${CYAN}[*] Подготовка структуры директорий...${NC}"
cleanup_legacy

# Активация Speed Probe для быстрой установки
find_fastest_mirror

echo -e "${CYAN}[*] Синхронизация манифеста модулей...${NC}"
if ! smart_download "modules.list" "${BASE_DIR}/modules.list"; then
    echo -e "${RED} [!] Критическая ошибка: Не удалось скачать modules.list${NC}"
    exit 1
fi

echo -e "${CYAN}[*] Скачивание главного ядра (don)...${NC}"
if ! smart_download "don" "$BIN_PATH"; then
    echo -e "${RED} [!] Ошибка скачивания don${NC}"
    exit 1
fi
tr -d '\r' < "$BIN_PATH" > "${BIN_PATH}.tmp" && mv "${BIN_PATH}.tmp" "$BIN_PATH"
chmod +x "$BIN_PATH"

echo -e "${CYAN}[*] Скачивание системных модулей...${NC}"
# Читаем список модулей из скачанного манифеста
while read -r mod; do
    [[ -z "$mod" ]] && continue
    echo -ne "  --> Загрузка ${mod}... "
    if smart_download "modules/${mod}" "${BASE_DIR}/modules/${mod}"; then
        tr -d '\r' < "${BASE_DIR}/modules/${mod}" > "${BASE_DIR}/modules/${mod}.tmp" && mv "${BASE_DIR}/modules/${mod}.tmp" "${BASE_DIR}/modules/${mod}"
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[FAIL]${NC}"
    fi
done < "${BASE_DIR}/modules.list"

# Отдельно скачиваем m_core.sh, так как это основа
echo -ne "  --> Загрузка m_core.sh... "
if smart_download "modules/m_core.sh" "${BASE_DIR}/modules/m_core.sh"; then
    tr -d '\r' < "${BASE_DIR}/modules/m_core.sh" > "${BASE_DIR}/modules/m_core.sh.tmp" && mv "${BASE_DIR}/modules/m_core.sh.tmp" "${BASE_DIR}/modules/m_core.sh"
    echo -e "${GREEN}[OK]${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
fi

clear
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}${BOLD} 🚀 TRAFFICGUARD PRO УСПЕШНО УСТАНОВЛЕН!${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW} Система адаптирована под любые регионы и блокировки.${NC}"
echo -e "${YELLOW} Все конфигурации перенесены в ${BASE_DIR}/etc/${NC}\n"
echo -e " 👉 Просто введите в консоль команду: ${GREEN}${BOLD}don${NC}"
echo -e "${CYAN}================================================================${NC}"
