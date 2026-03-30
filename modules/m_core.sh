#!/bin/bash
# Модуль Глобальных Функций (Умное ядро защиты от блокировок и сбоев)

# Список надежных зеркал-прокси для GitHub (на случай блокировок)
GH_PROXIES=(
    "https://mirror.ghproxy.com/"
    "https://gh-proxy.com/"
    "https://ghproxy.net/"
    "https://ghproxy.org/"
    "https://gh.api.99988866.xyz/"
    "https://github.moeyy.xyz/"
    "https://ghproxy.com.cn/"
    "https://mirror.ghproxy.cc/"
)

# ======================================================================
# 1. СТРУКТУРА ПАПОК И КОНФИГОВ
# ======================================================================
export BASE_DIR="/opt/remnawave/DONMATTEO-PRO-MANAGER"
# Глобальные переменные для скорости
export FAST_MIRROR=""
export GH_CDN="https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"

# ======================================================================
# 0. СИСТЕМА ЗОНДИРОВАНИЯ (Speed Probe)
# ======================================================================
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
        if curl -fsSL --connect-timeout 1 --max-time 3 "$url" -o /dev/null >/dev/null 2>&1; then
            export FAST_MIRROR="$base"
            echo -e "${GREEN}[+] Выбран канал: ${FAST_MIRROR}${NC}"
            return 0
        fi
    done
    
    # Режим "Зеркало" по умолчанию (надежный fallback)
    export FAST_MIRROR="https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"
    echo -e "${YELLOW}[!] Используется стандартный канал (CDN): ${FAST_MIRROR}${NC}"
}

export CONF_DIR="${BASE_DIR}/etc"
export MOD_DIR="${BASE_DIR}/modules"
export MOD_LIST_FILE="${BASE_DIR}/modules.list"

# Создать директорию модуля и вернуть путь
ensure_module_config() {
    local mod_name="$1"
    local target_dir="${CONF_DIR}/${mod_name}"
    mkdir -p "$target_dir"
    echo "$target_dir"
}

# Миграция старых файлов (ОДИН РАЗ ПРИ ЗАПУСКЕ)
migrate_old_files() {
    local OLD_BASE="/opt/remnawave"
    local NEW_BASE="/opt/remnawave/DONMATTEO-PRO-MANAGER"

    # 1. Если папка проекта еще не создана - создаем
    mkdir -p "${NEW_BASE}/etc"
    mkdir -p "${NEW_BASE}/modules"

    # 2. МИГРАЦИЯ v2 -> v3 (Перемещение файлов во вложенную папку проекта)
    if [[ -d "$OLD_BASE" && "$OLD_BASE" != "$NEW_BASE" ]]; then
        # Переносим don и modules.list
        [[ -f "${OLD_BASE}/don" ]] && mv "${OLD_BASE}/don" "${NEW_BASE}/don"
        [[ -f "${OLD_BASE}/modules.list" ]] && mv "${OLD_BASE}/modules.list" "${NEW_BASE}/modules.list"
        
        # Переносим модули
        if [[ -d "${OLD_BASE}/modules" && "${OLD_BASE}/modules" != "${NEW_BASE}/modules" ]]; then
            cp -r "${OLD_BASE}/modules/"* "${NEW_BASE}/modules/" 2>/dev/null
            rm -rf "${OLD_BASE}/modules" 2>/dev/null
        fi
        
        # Переносим конфиги etc
        if [[ -d "${OLD_BASE}/etc" && "${OLD_BASE}/etc" != "${NEW_BASE}/etc" ]]; then
            mkdir -p "${NEW_BASE}/etc"
            cp -r "${OLD_BASE}/etc/"* "${NEW_BASE}/etc/" 2>/dev/null
            rm -rf "${OLD_BASE}/etc" 2>/dev/null
        fi
    fi

    # 3. МИГРАЦИЯ v1 (Корневые файлы) -> v3 (etc/module/)
    local legacy_files=(
        "tg_url.txt:tg:url.txt"
        "tg_lists.txt:tg:lists.txt"
        "trafficguard-manual.list:tg:manual_ban.list"
        "whitelist.txt:f2b:whitelist.txt"
        "f2b_maxretry.txt:f2b:maxretry.txt"
        "f2b_findtime.txt:f2b:findtime.txt"
        "f2b_bantime.txt:f2b:bantime.txt"
        "limit_conn.txt:ufw:limit_conn_ports.txt"
        "limit_rate.txt:ufw:limit_rate_ports.txt"
        "limit_conn_val.txt:ufw:limit_conn_val.txt"
        "limit_rate_val.txt:ufw:limit_rate_val.txt"
    )

    for item in "${legacy_files[@]}"; do
        local old_name="${item%%:*}"
        local rest="${item#*:}"
        local mod_name="${rest%%:*}"
        local new_name="${rest#*:}"
        
        # Проверяем старые места: /opt/remnawave/, /opt/ (v1) и /opt/remnawave/DONMATTEO-PRO-MANAGER (если уже перенесли, но внутри еще v1 имена)
        for loc in "$OLD_BASE" "/opt" "$NEW_BASE"; do
            if [[ -f "${loc}/${old_name}" ]]; then
                local target_dir=$(ensure_module_config "$mod_name")
                mv "${loc}/${old_name}" "${target_dir}/${new_name}"
            fi
        done
    done
}

# ======================================================================
# 2. УМНОЕ СКАЧИВАНИЕ И СЕТЕВАЯ УСТОЙЧИВОСТЬ
# ======================================================================

# Авто-исправление DNS если GitHub не резолвится
smart_dns_fix() {
    if ! host raw.githubusercontent.com >/dev/null 2>&1 && ! host github.com >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] Проблема с DNS. Добавляем Google DNS временно...${NC}"
        # Делаем бекап если еще нет
        [[ ! -f /etc/resolv.conf.bak ]] && cp /etc/resolv.conf /etc/resolv.conf.bak
        echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
        return 0
    fi
    return 1
}

# Восстановление DNS
restore_dns() {
    [[ -f /etc/resolv.conf.bak ]] && mv /etc/resolv.conf.bak /etc/resolv.conf
}

smart_curl() {
    local url="$1"
    local output="$2"
    local timeout=${3:-20}
    local max_time=$timeout
    
    # 0. Если у нас есть FAST_MIRROR и это файл из нашего репо
    if [[ -n "${FAST_MIRROR:-}" && "$url" == *"/DONMATTEO-PRO-MANAGER/"* ]]; then
        local relative_path=$(echo "$url" | sed 's|.*/DONMATTEO-PRO-MANAGER/||' | sed 's|main/||')
        if curl -fsSL --connect-timeout 3 --max-time "$max_time" "${FAST_MIRROR}/${relative_path}" -o "$output" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 1. Прямая попытка
    if curl -fsSL --connect-timeout 3 --max-time "$max_time" "$url" -o "$output" >/dev/null 2>&1; then
        return 0
    fi

    # 2. Фикс DNS и повторная попытка
    smart_dns_fix && curl -fsSL --connect-timeout 5 --max-time "$max_time" "$url" -o "$output" >/dev/null 2>&1 && { restore_dns; return 0; }

    # 3. Если GitHub — пробуем jsDelivr (самое стабильное для сырых файлов)
    if [[ "$url" == *"raw.githubusercontent.com"* ]]; then
        local jsd_url=$(echo "$url" | sed -E 's|https://raw.githubusercontent.com/([^/]+)/([^/]+)/([^/]+)/(.*)|https://cdn.jsdelivr.net/gh/\1/\2@\3/\4|')
        if curl -fsSL --connect-timeout 5 --max-time "$max_time" "$jsd_url" -o "$output" >/dev/null 2>&1; then
            restore_dns; return 0
        fi
    fi

    # 4. Пробуем список прокси
    if [[ "$url" == *"github"* ]]; then
        echo -e "${YELLOW}[!] Прямой доступ ограничен. Пробуем зеркала...${NC}"
        local clean_url=$(echo "$url" | sed -E 's|https?://[^/]+/https://|https://|g')
        for proxy in "${GH_PROXIES[@]}"; do
            if curl -fsSL --connect-timeout 2 --max-time "$max_time" "${proxy}${clean_url}" -o "$output" >/dev/null 2>&1; then
                echo -e "${GREEN}[+] Скачано через: ${proxy}${NC}"
                restore_dns; return 0
            fi
        done
    fi

    # 5. Режим "Insecure"
    if curl -fsSLk --connect-timeout 5 --max-time "$max_time" "$url" -o "$output" >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] Скачано через Insecure-режим.${NC}"
        restore_dns; return 0
    fi

    echo -e "${RED}[!] ОШИБКА: Не удалось скачать файл: ${url}${NC}"
    restore_dns; return 1
}

# Умный CURL для JSON API (без зеркал, но с таймаутом и дефолтом)
smart_curl_json() {
    local url="$1"
    local field="$2"
    local default="${3:-}"
    local val=$(curl -s --max-time 3 "$url" | grep -oP "\"$field\":\s*\"\K[^\"]+" || echo "$default")
    [[ -z "$val" || "$val" == "null" ]] && echo "$default" || echo "$val"
}

# Умный Git Clone с поддержкой зеркал
smart_git_clone() {
    local repo_url="$1"
    local target_dir="$2"
    
    # 1. Пытаемся напрямую
    if git clone --depth 1 "$repo_url" "$target_dir" >/dev/null 2>&1; then
        return 0
    fi
    
    # 2. Пробуем через зеркала
    echo -e "${YELLOW}[!] Прямой Git-клон не удался. Пробуем зеркала...${NC}"
    for proxy in "${GH_PROXIES[@]}"; do
        local proxy_url="${proxy}${repo_url}"
        if git clone --depth 1 "$proxy_url" "$target_dir" >/dev/null 2>&1; then
            echo -e "${GREEN}[+] Репозиторий склонирован через: ${proxy}${NC}"
            return 0
        fi
    done
    
    return 1
}

# Псевдоним для обратной совместимости
safe_curl() { smart_curl "$@"; }

# ======================================================================
# 3. УМНАЯ УСТАНОВКА (С обходом блокировок и LOCK-ов)
# ======================================================================
smart_apt_install() {
    local pkg="$1"
    # Если пакет уже есть — выходим
    if dpkg -s "$pkg" >/dev/null 2>&1; then return 0; fi

    echo -ne "${CYAN}--> Установка ${pkg}... ${NC}"
    
    # 1. Ждем снятия локов
    local lock_files=("/var/lib/dpkg/lock-frontend" "/var/lib/apt/lists/lock" "/var/cache/apt/archives/lock")
    for lock in "${lock_files[@]}"; do
        if [[ -e "$lock" ]]; then
            local count=0
            while fuser "$lock" >/dev/null 2>&1 && [ $count -lt 30 ]; do
                echo -ne "\r${YELLOW}[!] Ждем APT ($lock)... $count/30${NC}"
                sleep 2
                ((count++))
            done
            [[ $count -eq 30 ]] && { fuser -k "$lock" >/dev/null 2>&1; rm -f "$lock"; }
        fi
    done

    # 2. Параметры установки
    export DEBIAN_FRONTEND=noninteractive
    local opts="-y -qq -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
    
    # Попытка 1: Обычная
    if apt-get install $opts "$pkg" >/dev/null 2>&1; then
        echo -e "${GREEN}[УСПЕШНО]${NC}"; return 0
    fi

    # Попытка 2: После update
    echo -ne "\r${YELLOW}[*] Обновление списков пакетов...${NC}"
    apt-get update -qq >/dev/null 2>&1
    if apt-get install $opts "$pkg" >/dev/null 2>&1; then
        echo -e "\r${GREEN}[УСПЕШНО] (после update)${NC}"; return 0
    fi

    # Попытка 3: Зеркала
    local mirrors=("https://mirror.yandex.ru" "http://mirror.umd.edu" "http://debian.mirror.constant.com")
    for mir in "${mirrors[@]}"; do
        echo -ne "\r${YELLOW}[!] Пробуем через зеркало: $mir...${NC}"
        [[ ! -f /etc/apt/sources.list.bak ]] && cp /etc/apt/sources.list /etc/apt/sources.list.bak
        sed -i "s|http://.*.debian.org|$mir|g" /etc/apt/sources.list
        sed -i "s|http://.*.ubuntu.com|$mir|g" /etc/apt/sources.list
        apt-get update -qq >/dev/null 2>&1
        if apt-get install $opts "$pkg" >/dev/null 2>&1; then
            echo -e "\r${GREEN}[УСПЕШНО] (через $mir)${NC}"
            mv /etc/apt/sources.list.bak /etc/apt/sources.list; return 0
        fi
        mv /etc/apt/sources.list.bak /etc/apt/sources.list
    done

    # Специальный случай для Grafana
    if [[ "$pkg" == "grafana" ]]; then
        echo -ne "\r${YELLOW}[!] Прямая установка Grafana .deb...${NC}"
        local DEB="/tmp/grafana_latest.deb"
        if smart_curl "https://dl.grafana.com/oss/release/grafana_11.5.0_amd64.deb" "$DEB" 60; then
            dpkg -i "$DEB" >/dev/null 2>&1 || apt-get install -f -y -qq >/dev/null 2>&1
            if command -v grafana-server >/dev/null; then
                echo -e "\r${GREEN}[УСПЕШНО] Grafana установлена напрямую.${NC}"
                rm -f "$DEB"; return 0
            fi
        fi
    fi

    echo -e "\r${RED}[!] СИСТЕМНАЯ ОШИБКА: Пакет ${pkg} не установлен.${NC}"
    return 1
}

# Совместимость со старыми модулями
install_grafana_mirror() {
    smart_apt_install "grafana"
}

# Сравнение версий (02.006 > 02.003)
version_gt() {
    local v1=$(echo "$1" | tr -d '.' | sed 's/^0*//')
    local v2=$(echo "$2" | tr -d '.' | sed 's/^0*//')
    [[ ${v1:-0} -gt ${v2:-0} ]]
}
