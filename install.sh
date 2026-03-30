#!/bin/bash
# ======================================================================
# Установщик TRAFFICGUARD PRO MANAGER (Standardized v3 - NO CACHE)
# ======================================================================

# Основные настройки
BASE_DIR="/opt/remnawave/DONMATTEO-PRO-MANAGER"
BIN_PATH="/usr/local/bin/don"
REPO_RAW="https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m'

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

# Авто-исправление DNS
smart_dns_fix() {
    if ! host raw.githubusercontent.com >/dev/null 2>&1 && ! host github.com >/dev/null 2>&1; then
        echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
    fi
}

# АГРЕССИВНАЯ функция скачивания с ПОЛНЫМ обходом кэша
smart_download() {
    local path=$1
    local output=$2
    local TS=$(date +%s)
    local NANO=$(date +%N 2>/dev/null || echo $RANDOM)
    local RAND=$(( RANDOM % 99999 ))
    
    echo -e "${CYAN}[*] Скачивание ${path} (обход всех кэшей)...${NC}"
    
    # 1. ПРИОРИТЕТ: GitHub API для получения SHA последнего коммита
    local COMMIT_SHA=$(curl -fsSL --connect-timeout 3 --max-time 5 \
        -H "Cache-Control: no-cache, no-store, must-revalidate" \
        -H "Pragma: no-cache" \
        "https://api.github.com/repos/DonMatteoVPN/DONMATTEO-PRO-MANAGER/commits/main" 2>/dev/null | \
        grep -oP '"sha":\s*"\K[^"]+' | head -n1)
    
    # 2. Если получили SHA - качаем напрямую по коммиту (100% свежий файл)
    if [[ -n "$COMMIT_SHA" && ${#COMMIT_SHA} -eq 40 ]]; then
        echo -e "${GREEN}  └─ Используем коммит: ${COMMIT_SHA:0:7}${NC}"
        local COMMIT_URL="https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/${COMMIT_SHA}/${path}"
        if curl -fsSL --connect-timeout 5 --max-time 20 \
            -H "Cache-Control: no-cache, no-store, must-revalidate" \
            -H "Pragma: no-cache" \
            "$COMMIT_URL" -o "$output" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # 3. Fallback: GitHub Raw с агрессивными заголовками
    if curl -fsSL --connect-timeout 5 --max-time 20 \
        -H "Cache-Control: no-cache, no-store, must-revalidate" \
        -H "Pragma: no-cache" \
        -H "Expires: 0" \
        "${REPO_RAW}/${path}?nocache=${TS}&r=${RAND}&n=${NANO}" -o "$output" >/dev/null 2>&1; then
        return 0
    fi

    # 4. Фикс DNS и повтор
    smart_dns_fix
    if curl -fsSL --connect-timeout 5 --max-time 20 \
        -H "Cache-Control: no-cache" \
        "${REPO_RAW}/${path}?t=${TS}" -o "$output" >/dev/null 2>&1; then
        return 0
    fi

    # 5. Режим "Отчаяние": без проверки SSL
    if curl -fsSLk --connect-timeout 5 --max-time 20 \
        "${REPO_RAW}/${path}?t=${TS}" -o "$output" >/dev/null 2>&1; then
        return 0
    fi
    
    echo -e "${RED}[!] Ошибка скачивания ${path}${NC}"
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
