#!/bin/bash
# Модуль Глобальных Функций (Умное ядро защиты от блокировок и сбоев)

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

export BASE_DIR="/opt/remnawave/DONMATTEO-PRO-MANAGER"
export FAST_MIRROR=""
export GH_CDN="https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"

# ======================================================================
# УМНЫЙ DNS: При запуске всегда обеспечиваем рабочий Google DNS.
# Логика: добавляем Google DNS В НАЧАЛО resolv.conf (не заменяем!).
# Это гарантирует быстрый старт без зависаний при плохом системном DNS.
# ======================================================================
ensure_google_dns() {
    # Если Google DNS уже первый в списке — ничего не делаем
    local first_ns
    first_ns=$(grep -m1 "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    if [[ "$first_ns" == "8.8.8.8" ]]; then
        return 0
    fi

    # Сохраняем оригинал (только один раз)
    if [[ ! -f /etc/resolv.conf.don_bak ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.don_bak 2>/dev/null || true
    fi

    # Вставляем Google DNS в начало, сохраняя остальное
    local current_content
    current_content=$(grep -v "^nameserver 8.8.8.8\|^nameserver 1.1.1.1" /etc/resolv.conf 2>/dev/null || true)
    {
        echo "# DON Manager: Приоритетный DNS"
        echo "nameserver 8.8.8.8"
        echo "nameserver 1.1.1.1"
        echo "$current_content"
    } > /etc/resolv.conf
}

restore_dns() {
    if [[ -f /etc/resolv.conf.don_bak ]]; then
        mv /etc/resolv.conf.don_bak /etc/resolv.conf 2>/dev/null || true
    fi
}

# Оставляем smart_dns_fix для обратной совместимости (теперь просто алиас)
smart_dns_fix() {
    ensure_google_dns
    return 1  # Возвращаем 1 чтобы не менять логику вызывающего кода
}

pause() {
    echo -e "\n${CYAN}Нажмите [Enter] для продолжения...${NC}"
    read -r < /dev/tty
}

# ======================================================================
# УМНЫЙ ВЫБОР ЗЕРКАЛА: Проверяем при первом запуске, кэшируем навсегда.
# Кэш сбрасывается только если сохранённое зеркало перестало отвечать.
# ======================================================================
find_fastest_mirror() {
    local CACHE_FILE="/tmp/don_mirror.cache"

    # Проверяем кэш: если файл есть — проверяем что зеркало всё ещё живое
    if [[ -f "$CACHE_FILE" ]]; then
        local cached_mirror
        cached_mirror=$(cat "$CACHE_FILE" 2>/dev/null)
        if [[ -n "$cached_mirror" ]]; then
            local TS
            TS=$(date +%s)
            if curl -fsSL --connect-timeout 2 --max-time 4 \
                "${cached_mirror}/don?t=${TS}" -o /dev/null >/dev/null 2>&1; then
                export FAST_MIRROR="$cached_mirror"
                return 0
            else
                # Кэшированное зеркало не отвечает — ищем заново
                rm -f "$CACHE_FILE"
            fi
        fi
    fi

    echo -e "${CYAN}[*] Зондирование сети: Поиск лучшего канала...${NC}"
    local test_file="don"
    local TS
    TS=$(date +%s)
    local candidates=(
        "https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
        "https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"
        "https://mirror.ghproxy.com/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
        "https://ghproxy.net/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
    )

    for base in "${candidates[@]}"; do
        local url="${base}/${test_file}?t=${TS}"
        if curl -fsSL --connect-timeout 2 --max-time 5 "$url" -o /dev/null >/dev/null 2>&1; then
            export FAST_MIRROR="$base"
            echo "$FAST_MIRROR" > "$CACHE_FILE"
            echo -e "${GREEN}[+] Выбран канал: ${FAST_MIRROR}${NC}"
            return 0
        fi
    done

    # Запасной вариант
    export FAST_MIRROR="https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"
    echo "$FAST_MIRROR" > "$CACHE_FILE"
    echo -e "${YELLOW}[!] Используется резервный канал (CDN): ${FAST_MIRROR}${NC}"
}

export CONF_DIR="${BASE_DIR}/etc"
export MOD_DIR="${BASE_DIR}/modules"
export MOD_LIST_FILE="${BASE_DIR}/modules.list"

ensure_module_config() {
    local mod_name="$1"
    local target_dir="${CONF_DIR}/${mod_name}"
    mkdir -p "$target_dir"
    echo "$target_dir"
}

migrate_old_files() {
    local OLD_BASE="/opt/remnawave"
    local NEW_BASE="/opt/remnawave/DONMATTEO-PRO-MANAGER"

    mkdir -p "${NEW_BASE}/etc"
    mkdir -p "${NEW_BASE}/modules"

    if [[ -d "$OLD_BASE" && "$OLD_BASE" != "$NEW_BASE" ]]; then
        [[ -f "${OLD_BASE}/don" ]] && mv "${OLD_BASE}/don" "${NEW_BASE}/don"
        [[ -f "${OLD_BASE}/modules.list" ]] && mv "${OLD_BASE}/modules.list" "${NEW_BASE}/modules.list"
        if [[ -d "${OLD_BASE}/modules" && "${OLD_BASE}/modules" != "${NEW_BASE}/modules" ]]; then
            cp -r "${OLD_BASE}/modules/"* "${NEW_BASE}/modules/" 2>/dev/null
            rm -rf "${OLD_BASE}/modules" 2>/dev/null
        fi
        if [[ -d "${OLD_BASE}/etc" && "${OLD_BASE}/etc" != "${NEW_BASE}/etc" ]]; then
            mkdir -p "${NEW_BASE}/etc"
            cp -r "${OLD_BASE}/etc/"* "${NEW_BASE}/etc/" 2>/dev/null
            rm -rf "${OLD_BASE}/etc" 2>/dev/null
        fi
    fi

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
        for loc in "$OLD_BASE" "/opt" "$NEW_BASE"; do
            if [[ -f "${loc}/${old_name}" ]]; then
                local target_dir
                target_dir=$(ensure_module_config "$mod_name")
                mv "${loc}/${old_name}" "${target_dir}/${new_name}"
            fi
        done
    done
}

smart_curl() {
    local url="$1"
    local output="$2"
    local timeout=${3:-20}
    local max_time=$timeout

    # Используем кэшированное быстрое зеркало
    if [[ -n "${FAST_MIRROR:-}" && "$url" == *"/DONMATTEO-PRO-MANAGER/"* ]]; then
        local relative_path
        relative_path=$(echo "$url" | sed 's|.*/DONMATTEO-PRO-MANAGER/||' | sed 's|main/||')
        if curl -fsSL --connect-timeout 3 --max-time "$max_time" \
            "${FAST_MIRROR}/${relative_path}" -o "$output" >/dev/null 2>&1; then
            return 0
        fi
        # Зеркало не сработало — сбрасываем кэш чтобы при следующем запуске переопределить
        rm -f "/tmp/don_mirror.cache" 2>/dev/null
    fi

    local std_out="/dev/null"
    [[ "${DEBUG:-false}" == "true" ]] && std_out="/dev/stdout"

    if curl -fsSL --connect-timeout 3 --max-time "$max_time" "$url" -o "$output" >"$std_out" 2>&1; then return 0; fi

    # GitHub CDN fallback
    if [[ "$url" == *"raw.githubusercontent.com"* ]]; then
        local jsd_url
        jsd_url=$(echo "$url" | sed -E 's|https://raw.githubusercontent.com/([^/]+)/([^/]+)/([^/]+)/(.*)|https://cdn.jsdelivr.net/gh/\1/\2@\3/\4|')
        if curl -fsSL --connect-timeout 5 --max-time "$max_time" "$jsd_url" -o "$output" >/dev/null 2>&1; then return 0; fi
    fi

    # GH Proxies fallback
    if [[ "$url" == *"github"* ]]; then
        echo -e "${YELLOW}[!] Прямой доступ ограничен. Пробуем зеркала...${NC}"
        local clean_url
        clean_url=$(echo "$url" | sed -E 's|https?://[^/]+/https://|https://|g')
        for proxy in "${GH_PROXIES[@]}"; do
            if curl -fsSL --connect-timeout 2 --max-time "$max_time" \
                "${proxy}${clean_url}" -o "$output" >/dev/null 2>&1; then
                echo -e "${GREEN}[+] Скачано через: ${proxy}${NC}"
                return 0
            fi
        done
    fi

    # Последний шанс — без проверки SSL
    if curl -fsSLk --connect-timeout 5 --max-time "$max_time" "$url" -o "$output" >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] Скачано через Insecure-режим.${NC}"
        return 0
    fi

    echo -e "${RED}[!] ОШИБКА: Не удалось скачать файл: ${url}${NC}"
    return 1
}

smart_curl_json() {
    local url="$1"
    local field="$2"
    local default="${3:-}"
    local val
    val=$(curl -s --max-time 3 "$url" | grep -oP "\"$field\":\s*\"\K[^\"]+") || val="$default"
    [[ -z "$val" || "$val" == "null" ]] && echo "$default" || echo "$val"
}

smart_git_clone() {
    local repo_url="$1"
    local target_dir="$2"
    if git clone --depth 1 "$repo_url" "$target_dir" >/dev/null 2>&1; then return 0; fi
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

safe_curl() { smart_curl "$@"; }

smart_apt_install() {
    local pkg="$1"
    if dpkg -s "$pkg" >/dev/null 2>&1; then echo -e "${GREEN}[УЖЕ УСТАНОВЛЕН]${NC}"; return 0; fi

    echo -ne "${CYAN}--> Установка ${pkg}... ${NC}"
    local lock_files=("/var/lib/dpkg/lock-frontend" "/var/lib/apt/lists/lock" "/var/cache/apt/archives/lock" "/var/lib/dpkg/lock")
    local max_wait=90

    if ! command -v fuser >/dev/null 2>&1; then apt-get install -y psmisc >/dev/null 2>&1 || true; fi

    for lock in "${lock_files[@]}"; do
        if [[ -e "$lock" ]]; then
            local count=0
            while fuser "$lock" >/dev/null 2>&1 && [ $count -lt $max_wait ]; do
                echo -ne "\r${YELLOW}[!] Ждем освобождения APT ($(basename "$lock"))... $count/$max_wait сек${NC}     "
                sleep 3; ((count+=3))
            done
            if [ $count -ge $max_wait ]; then
                fuser -k "$lock" >/dev/null 2>&1 || true; rm -f "$lock" 2>/dev/null || true; sleep 2
            fi
        fi
    done

    pkill -9 apt-get 2>/dev/null || true; pkill -9 apt 2>/dev/null || true; pkill -9 dpkg 2>/dev/null || true; sleep 2
    dpkg --configure -a >/dev/null 2>&1 || true; sleep 1

    export DEBIAN_FRONTEND=noninteractive
    local opts="-y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
    local std_out="/dev/null"; local std_err="2>&1"
    [[ "${DEBUG:-false}" == "true" ]] && { std_out="/dev/stdout"; std_err=""; }

    echo -ne "\r${CYAN}--> Установка ${pkg}... (попытка 1/3)${NC}     "
    if eval "apt-get install $opts \"$pkg\" >$std_out $std_err"; then echo -e "\r${GREEN}[УСПЕШНО]${NC}                              "; return 0; fi

    echo -ne "\r${YELLOW}[*] Обновление списков пакетов... (попытка 2/3)${NC}     "
    apt-get update -qq >/dev/null 2>&1 || apt-get update >/dev/null 2>&1
    if eval "apt-get install $opts \"$pkg\" >$std_out $std_err"; then echo -e "\r${GREEN}[УСПЕШНО] (после update)${NC}                              "; return 0; fi

    echo -ne "\r${YELLOW}[*] Исправление зависимостей... (попытка 3/3)${NC}     "
    apt-get install -f -y >/dev/null 2>&1 || true
    if eval "apt-get install $opts \"$pkg\" >$std_out $std_err"; then echo -e "\r${GREEN}[УСПЕШНО] (после fix)${NC}                              "; return 0; fi

    echo -e "\r${RED}[!] ОШИБКА: Пакет ${pkg} не установлен.${NC}                              "
    return 1
}

install_grafana_mirror() { smart_apt_install "grafana"; }

version_gt() {
    local v1
    local v2
    v1=$(echo "$1" | tr -d '.' | sed 's/^0*//')
    v2=$(echo "$2" | tr -d '.' | sed 's/^0*//')
    [[ ${v1:-0} -gt ${v2:-0} ]]
}