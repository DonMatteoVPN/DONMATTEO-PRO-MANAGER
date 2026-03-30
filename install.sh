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
    local TS=$(date +%s%N 2>/dev/null || date +%s)
    local RAND=$(( RANDOM % 9999 ))
    local BUSTER="t=${TS}&s=${RAND}"
    
    # 0. ПРИОРИТЕТ GITHUB (Для пробития кэша CDN)
    if [[ "$path" == "don" || "$path" == "modules/m_core.sh" || "$path" == "modules.list" ]]; then
        if curl -fsSL -H "Cache-Control: no-cache" --connect-timeout 2 --max-time 15 "${REPO_RAW}/${path}?${BUSTER}" -o "$output" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 1. Если у нас есть FAST_MIRROR
    if [[ -n "$FAST_MIRROR" ]]; then
        local url="${FAST_MIRROR}/${path}"
        [[ "$FAST_MIRROR" == *"jsdelivr"* || "$FAST_MIRROR" == *"raw.githubusercontent"* ]] && url="${FAST_MIRROR}/${path}?${BUSTER}"
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
        local m_url="${mirror}/${path}"
        [[ "$mirror" == *"jsdelivr"* || "$mirror" == *"raw.githubusercontent"* ]] && m_url="${mirror}/${path}?${BUSTER}"
        if curl -fsSL --connect-timeout 2 --max-time 15 "$m_url" -o "$output" >/dev/null 2>&1; then
            return 0
        fi
    done

    # 4. Режим "Отчаяние": без проверки SSL
    if curl -fsSLk --connect-timeout 5 --max-time 20 "${REPO_RAW}/${path}?${BUSTER}" -o "$output" >/dev/null 2>&1; then
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

# 0.2 РЕЖИМ ЛОКАЛЬНОЙ РАЗРАБОТКИ
export IS_LOCAL="false"
if [[ -f "./don" && -d "./modules" ]]; then
    export IS_LOCAL="true"
    echo -e "${YELLOW}[!] Найдена локальная копия проекта. Используем локальные файлы для установки...${NC}"
fi

# Активация Speed Probe для быстрой установки
find_fastest_mirror

echo -e "${CYAN}[*] Синхронизация манифеста модулей...${NC}"
if [[ "$IS_LOCAL" == "true" ]]; then
    cp "./modules.list" "${BASE_DIR}/modules.list" 2>/dev/null || ls modules/ > "${BASE_DIR}/modules.list"
else
    smart_download "modules.list" "${BASE_DIR}/modules.list"
fi

echo -e "${CYAN}[*] Установка главного ядра (don)...${NC}"
if [[ "$IS_LOCAL" == "true" ]]; then
    cp "./don" "$BIN_PATH"
else
    smart_download "don" "$BIN_PATH"
fi

if [[ ! -f "$BIN_PATH" ]]; then
    echo -e "${RED} [!] Ошибка установки don${NC}"
    exit 1
fi
tr -d '\r' < "$BIN_PATH" > "${BIN_PATH}.tmp" && mv "${BIN_PATH}.tmp" "$BIN_PATH"
chmod +x "$BIN_PATH"

echo -e "${CYAN}[*] Скачивание системных модулей...${NC}"
# Читаем список модулей из скачанного манифеста
while read -r mod; do
    [[ -z "$mod" ]] && continue
    echo -ne "  --> Загрузка/Копирование ${mod}... "
    if [[ "$IS_LOCAL" == "true" && -f "./modules/${mod}" ]]; then
        cp "./modules/${mod}" "${BASE_DIR}/modules/${mod}"
        echo -e "${GREEN}[OK] (local)${NC}"
    elif smart_download "modules/${mod}" "${BASE_DIR}/modules/${mod}"; then
        tr -d '\r' < "${BASE_DIR}/modules/${mod}" > "${BASE_DIR}/modules/${mod}.tmp" && mv "${BASE_DIR}/modules/${mod}.tmp" "${BASE_DIR}/modules/${mod}"
        echo -e "${GREEN}[OK] (remote)${NC}"
    else
        echo -e "${RED}[FAIL]${NC}"
    fi
done < "${BASE_DIR}/modules.list"

# Отдельно m_core.sh
echo -ne "  --> Загрузка/Копирование m_core.sh... "
if [[ "$IS_LOCAL" == "true" && -f "./modules/m_core.sh" ]]; then
    cp "./modules/m_core.sh" "${BASE_DIR}/modules/m_core.sh"
    echo -e "${GREEN}[OK] (local)${NC}"
elif smart_download "modules/m_core.sh" "${BASE_DIR}/modules/m_core.sh"; then
    tr -d '\r' < "${BASE_DIR}/modules/m_core.sh" > "${BASE_DIR}/modules/m_core.sh.tmp" && mv "${BASE_DIR}/modules/m_core.sh.tmp" "${BASE_DIR}/modules/m_core.sh"
    echo -e "${GREEN}[OK] (remote)${NC}"
else
    echo -e "${RED}[FAIL]${NC}"
fi

# 5. ИТОГОВАЯ ПРОВЕРКА
installed_ver=$(grep "APP_VERSION=" "$BIN_PATH" | cut -d'"' -f2 || echo "unknown")
chmod +x "$BIN_PATH"

clear
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}${BOLD} 🚀 TRAFFICGUARD PRO УСПЕШНО УСТАНОВЛЕН (v${installed_ver})!${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW} Система адаптирована под любые регионы и блокировки.${NC}"
echo -e "${YELLOW} Все конфигурации перенесены в ${BASE_DIR}/etc/${NC}\n"
echo -e " 👉 Просто введите в консоль команду: ${GREEN}${BOLD}don${NC}"
echo -e "${CYAN}================================================================${NC}"
