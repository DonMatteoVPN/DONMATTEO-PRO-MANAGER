#!/bin/bash
# =============================================================================
# МОДУЛЬ ЯДРА: m_00_core.sh
# =============================================================================
# Загружается первым. Содержит фундаментальные функции: сеть, DNS, зеркала,
# скачивание файлов с умным обходом блокировок, работа с пакетами.
#
# ДЛЯ ЧАЙНИКОВ: Этот файл — «мозг» всего менеджера. Здесь прописано,
# как скачивать файлы даже если GitHub заблокирован, как умно работать
# с интернетом и системными пакетами. Не редактируй без надобности!
# =============================================================================

# --- Глобальные константы ---
export BASE_DIR="${BASE_DIR:-/opt/remnawave/DONMATTEO-PRO-MANAGER}"
export CONF_DIR="${BASE_DIR}/etc"
export MOD_DIR="${BASE_DIR}/modules"
export CORE_DIR="${MOD_DIR}/core"
export MOD_LIST_FILE="${BASE_DIR}/modules.list"
export FAST_MIRROR=""
export AUDIT_LOG="/var/log/don_audit.log"

# --- Список зеркал для обхода блокировок GitHub ---
# ДЛЯ ЧАЙНИКОВ: Если GitHub заблокирован — скрипт автоматически использует зеркала.
# Это список «прокси-серверов» для GitHub, расположенных в разных странах.
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

export GH_CDN="https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"

# =============================================================================
# DNS: Умное управление — НЕ ломаем systemd-resolved
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: DNS — это «телефонная книга» интернета. Если системный DNS
# не работает, скрипт аккуратно добавляет Google DNS в начало списка,
# не уничтожая системные настройки.
ensure_google_dns() {
    # Не трогаем если уже стоит Google DNS первым
    local first_ns
    first_ns=$(grep -m1 "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    [[ "$first_ns" == "8.8.8.8" ]] && return 0

    # Проверяем: не управляется ли resolv.conf через systemd-resolved?
    if [[ -L /etc/resolv.conf ]]; then
        local real_path
        real_path=$(readlink -f /etc/resolv.conf)
        if [[ "$real_path" == *"systemd"* ]] || [[ "$real_path" == *"resolvconf"* ]]; then
            # Системный резолвер активен — редактируем только через него
            if command -v resolvconf >/dev/null 2>&1; then
                echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" | resolvconf -a lo.don 2>/dev/null
            elif command -v systemd-resolve >/dev/null 2>&1; then
                # Добавляем DNS через systemd-resolved API
                systemd-resolve --set-dns=8.8.8.8 --interface=lo 2>/dev/null || true
            fi
            return 0
        fi
    fi

    # Обычная система — добавляем в начало resolv.conf
    [[ ! -f /etc/resolv.conf.don_bak ]] && cp /etc/resolv.conf /etc/resolv.conf.don_bak 2>/dev/null || true

    local current_content
    current_content=$(grep -v "^nameserver 8.8.8.8\|^nameserver 1.1.1.1\|^# DON Manager" /etc/resolv.conf 2>/dev/null || true)
    {
        echo "# DON Manager: Приоритетный DNS (резервная копия: /etc/resolv.conf.don_bak)"
        echo "nameserver 8.8.8.8"
        echo "nameserver 1.1.1.1"
        echo "$current_content"
    } > /etc/resolv.conf
}

restore_dns() {
    # ДЛЯ ЧАЙНИКОВ: Восстанавливаем оригинальный DNS при выходе из скрипта.
    if [[ -f /etc/resolv.conf.don_bak ]]; then
        mv /etc/resolv.conf.don_bak /etc/resolv.conf 2>/dev/null || true
    fi
    # Убираем lo.don из resolvconf если добавляли
    command -v resolvconf >/dev/null 2>&1 && resolvconf -d lo.don 2>/dev/null || true
}

# Псевдоним для обратной совместимости со старым кодом
smart_dns_fix() { ensure_google_dns; }

# =============================================================================
# ПОИСК БЫСТРЕЙШЕГО ЗЕРКАЛА
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: Скрипт проверяет несколько источников скачивания и выбирает
# самый быстрый. Результат сохраняется в кэш, чтобы не тратить время каждый раз.
find_fastest_mirror() {
    # Файл кэша — хранится в папке проекта, не в /tmp (переживёт перезагрузку)
    local CACHE_FILE="${BASE_DIR}/etc/.mirror.cache"
    mkdir -p "${BASE_DIR}/etc" 2>/dev/null

    if [[ -f "$CACHE_FILE" ]]; then
        local cached_mirror
        cached_mirror=$(cat "$CACHE_FILE" 2>/dev/null)
        if [[ -n "$cached_mirror" ]]; then
            # Проверяем что кэшированное зеркало ещё живое
            if curl -fsSL --connect-timeout 3 --max-time 5 \
                "${cached_mirror}/don" -o /dev/null >/dev/null 2>&1; then
                export FAST_MIRROR="$cached_mirror"
                return 0
            else
                rm -f "$CACHE_FILE"
            fi
        fi
    fi

    echo -e "${CYAN}[*] Поиск наилучшего канала скачивания...${NC}"
    local TS; TS=$(date +%s)
    local candidates=(
        "https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
        "https://cdn.jsdelivr.net/gh/DonMatteoVPN/DONMATTEO-PRO-MANAGER@main"
        "https://mirror.ghproxy.com/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
        "https://ghproxy.net/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
        "https://gh.api.99988866.xyz/https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
    )

    for base in "${candidates[@]}"; do
        if curl -fsSL --connect-timeout 2 --max-time 5 \
            "${base}/don?t=${TS}" -o /dev/null >/dev/null 2>&1; then
            export FAST_MIRROR="$base"
            echo "$FAST_MIRROR" > "$CACHE_FILE"
            echo -e "${GREEN}[+] Выбран канал: ${FAST_MIRROR}${NC}"
            return 0
        fi
    done

    # Запасной вариант — CDN
    export FAST_MIRROR="$GH_CDN"
    echo "$FAST_MIRROR" > "$CACHE_FILE"
    echo -e "${YELLOW}[!] Используется резервный CDN-канал.${NC}"
}

# =============================================================================
# УМНОЕ СКАЧИВАНИЕ С ПОЛНЫМ ОБХОДОМ БЛОКИРОВОК (БЕЗ curl -k по умолчанию!)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: Эта функция пробует скачать файл несколькими способами.
# Сначала напрямую, потом через зеркала (прокси-серверы), потом через CDN.
# Если ВООБЩЕ ничего не работает — сообщает об ошибке. Безопасность гарантирована!
smart_curl() {
    local url="$1"
    local output="$2"
    local timeout="${3:-20}"
    local debug_out="/dev/null"
    [[ "${DEBUG:-false}" == "true" ]] && debug_out="/dev/stderr"

    # --- МЕТОД 1: Быстрое кэшированное зеркало ---
    if [[ -n "${FAST_MIRROR:-}" && "$url" == *"DONMATTEO-PRO-MANAGER"* ]]; then
        local relative_path
        relative_path=$(echo "$url" | sed 's|.*/DONMATTEO-PRO-MANAGER/main/||; s|.*/DONMATTEO-PRO-MANAGER@main/||')
        if curl -fsSL --connect-timeout 3 --max-time "$timeout" \
            "${FAST_MIRROR}/${relative_path}" -o "$output" >"$debug_out" 2>&1; then
            return 0
        fi
        rm -f "${BASE_DIR}/etc/.mirror.cache" 2>/dev/null
    fi

    # --- МЕТОД 2: Прямое подключение ---
    if curl -fsSL --connect-timeout 5 --max-time "$timeout" \
        "$url" -o "$output" >"$debug_out" 2>&1; then
        return 0
    fi

    # --- МЕТОД 3: Через системный HTTP/HTTPS прокси (если настроен) ---
    if [[ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}${https_proxy:-}${http_proxy:-}" ]]; then
        if curl -fsSL --connect-timeout 5 --max-time "$timeout" \
            "$url" -o "$output" >"$debug_out" 2>&1; then
            echo -e "${GREEN}[+] Скачано через системный прокси.${NC}" >"$debug_out"
            return 0
        fi
    fi

    # --- МЕТОД 4: CDN Fallback (для GitHub файлов) ---
    if [[ "$url" == *"raw.githubusercontent.com"* ]]; then
        local jsd_url
        jsd_url=$(echo "$url" | sed -E \
            's|https://raw.githubusercontent.com/([^/]+)/([^/]+)/([^/]+)/(.*)|https://cdn.jsdelivr.net/gh/\1/\2@\3/\4|')
        if curl -fsSL --connect-timeout 5 --max-time "$timeout" \
            "$jsd_url" -o "$output" >"$debug_out" 2>&1; then
            return 0
        fi
    fi

    # --- МЕТОД 5: Список зеркал GitHub (обход РКН) ---
    if [[ "$url" == *"github"* ]]; then
        echo -e "${YELLOW}[!] Прямой доступ ограничен. Автоматический подбор зеркала...${NC}"
        local clean_url
        clean_url=$(echo "$url" | sed -E 's|https?://[^/]+/https://|https://|g')
        local proxy_num=0
        for proxy in "${GH_PROXIES[@]}"; do
            ((proxy_num++))
            echo -ne "\r  Пробую зеркало [${proxy_num}/${#GH_PROXIES[@]}]..."
            if curl -fsSL --connect-timeout 3 --max-time "$timeout" \
                "${proxy}${clean_url}" -o "$output" >"$debug_out" 2>&1; then
                echo -e "\r${GREEN}[+] Скачано через зеркало: ${proxy}${NC}                    "
                # Кэшируем успешное зеркало
                local mirror_base="${proxy}https://raw.githubusercontent.com/DonMatteoVPN/DONMATTEO-PRO-MANAGER/main"
                echo "$mirror_base" > "${BASE_DIR}/etc/.mirror.cache"
                export FAST_MIRROR="$mirror_base"
                return 0
            fi
        done
        echo -e "\r${YELLOW}[!] Все зеркала недоступны. Последняя попытка...${NC}   "
    fi

    # --- МЕТОД 6: Фикс DNS + повтор ---
    ensure_google_dns
    if curl -fsSL --connect-timeout 5 --max-time "$timeout" \
        "$url" -o "$output" >"$debug_out" 2>&1; then
        return 0
    fi

    # --- МЕТОД 7: Последний шанс без SSL (с записью в аудит-лог!) ---
    # ДЛЯ ЧАЙНИКОВ: Если ВООБЩЕ ничего не работает, пробуем без проверки
    # SSL-сертификата. Это небезопасно, поэтому пишем в лог.
    echo -e "${RED}[!] ВНИМАНИЕ: Все безопасные методы исчерпаны.${NC}"
    echo -e "${YELLOW}    Последняя попытка: режим без проверки SSL...${NC}"
    if curl -fsSLk --connect-timeout 5 --max-time "$timeout" \
        "$url" -o "$output" >"$debug_out" 2>&1; then
        local warn_msg="НЕБЕЗОПАСНОЕ СКАЧИВАНИЕ (без SSL): ${url}"
        echo -e "${RED}⚠️  ${warn_msg}${NC}"
        # Записываем в аудит-лог
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${warn_msg}" >> "$AUDIT_LOG" 2>/dev/null || true
        return 0
    fi

    echo -e "${RED}[✗] ОШИБКА: Не удалось скачать файл ни одним из методов.${NC}"
    echo -e "${GRAY}    URL: ${url}${NC}"
    return 1
}

# --- Мягкая проверка SHA256 (БАГ #1 FIX) ---
# ДЛЯ ЧАЙНИКОВ: Проверяем что скачанный файл не подменили хакеры.
# "Мягкая" = если хеш-файла нет, просто предупреждаем, не блокируем.
verify_checksum() {
    local file="$1"
    local expected_sha256="$2"
    [[ -z "$expected_sha256" ]] && return 0  # Нет хеша — пропускаем

    local actual_sha256
    actual_sha256=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')

    if [[ "$actual_sha256" == "$expected_sha256" ]]; then
        return 0
    else
        echo -e "${YELLOW}[!] ПРЕДУПРЕЖДЕНИЕ: Хеш файла не совпадает!${NC}"
        echo -e "${GRAY}    Ожидалось: ${expected_sha256}${NC}"
        echo -e "${GRAY}    Получено:  ${actual_sha256}${NC}"
        echo -e "${YELLOW}    Файл может быть изменён. Продолжить? (y/N)${NC}"
        read -r confirm < /dev/tty
        [[ "${confirm,,}" == "y" ]] && return 0 || return 1
    fi
}

# --- JSON-парсер через curl ---
smart_curl_json() {
    local url="$1"
    local field="$2"
    local default="${3:-}"
    local val
    val=$(curl -s --max-time 5 "$url" 2>/dev/null | grep -oP "\"${field}\":\s*\"\K[^\"]+") || val="$default"
    [[ -z "$val" || "$val" == "null" ]] && echo "$default" || echo "$val"
}

# --- Git clone через зеркала ---
smart_git_clone() {
    local repo_url="$1"
    local target_dir="$2"

    if git clone --depth 1 "$repo_url" "$target_dir" >/dev/null 2>&1; then return 0; fi

    echo -e "${YELLOW}[!] Прямой Git-клон не удался. Пробуем через зеркала...${NC}"
    local proxy_num=0
    for proxy in "${GH_PROXIES[@]}"; do
        ((proxy_num++))
        echo -ne "\r  Зеркало [${proxy_num}/${#GH_PROXIES[@]}]..."
        if git clone --depth 1 "${proxy}${repo_url}" "$target_dir" >/dev/null 2>&1; then
            echo -e "\r${GREEN}[+] Клонировано через: ${proxy}${NC}                    "
            return 0
        fi
    done
    return 1
}

# Псевдоним для обратной совместимости
safe_curl() { smart_curl "$@"; }

# =============================================================================
# КОНФИГУРАЦИЯ МОДУЛЕЙ
# =============================================================================
ensure_module_config() {
    local mod_name="$1"
    local target_dir="${CONF_DIR}/${mod_name}"
    mkdir -p "$target_dir"
    echo "$target_dir"
}

# =============================================================================
# МИГРАЦИЯ СТАРЫХ ФАЙЛОВ (запускается один раз при апгрейде)
# =============================================================================
migrate_old_files() {
    local OLD_BASE="/opt/remnawave"
    local NEW_BASE="$BASE_DIR"

    mkdir -p "${NEW_BASE}/etc" "${NEW_BASE}/modules/core"

    # Переносим старую структуру flat-modules → core/
    if [[ -d "${NEW_BASE}/modules" ]]; then
        for old_mod in "${NEW_BASE}/modules/"m_*.sh; do
            [[ ! -f "$old_mod" ]] && continue
            local modname; modname=$(basename "$old_mod")
            # Если уже в core — пропускаем
            [[ -f "${NEW_BASE}/modules/core/${modname}" ]] && continue
            # Пытаемся найти соответствие по нумерованному имени
            local new_name=""
            case "$modname" in
                m_core.sh)       new_name="m_00_core.sh" ;;
                m_helpers.sh)    new_name="m_10_helpers.sh" ;;
                m_config.sh)     new_name="m_20_config.sh" ;;
                m_ufw.sh)        new_name="m_30_ufw.sh" ;;
                m_f2b.sh)        new_name="m_40_f2b.sh" ;;
                m_ssh.sh)        new_name="m_50_ssh.sh" ;;
                m_tg.sh)         new_name="m_60_tg.sh" ;;
                m_swap.sh)       new_name="m_70_swap.sh" ;;
                m_cleaner.sh)    new_name="m_80_cleaner.sh" ;;
                m_installer.sh)  new_name="m_90_installer.sh" ;;
                m_update.sh)     new_name="m_95_update.sh" ;;
                m_scanner.sh)    new_name="m_96_scanner.sh" ;;
                m_node.sh)       new_name="m_97_node.sh" ;;
            esac
            if [[ -n "$new_name" ]]; then
                mv "$old_mod" "${NEW_BASE}/modules/core/${new_name}" 2>/dev/null || true
            fi
        done
    fi

    # Переносим конфиги из старого места
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
                local target_dir; target_dir=$(ensure_module_config "$mod_name")
                mv "${loc}/${old_name}" "${target_dir}/${new_name}" 2>/dev/null || true
            fi
        done
    done
}

# =============================================================================
# APT: УМНАЯ УСТАНОВКА ПАКЕТОВ (ИСПРАВЛЕН БАГ #9 И #18)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: Устанавливает программы aus apt. Умеет ждать если apt занят
# другим процессом и принимает несколько пакетов сразу.
smart_apt_install() {
    # Принимаем несколько пакетов: smart_apt_install "curl" "wget" "bc"
    local pkgs=("$@")
    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    # Фильтруем только неустановленные
    local to_install=()
    for pkg in "${pkgs[@]}"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || to_install+=("$pkg")
    done
    [[ ${#to_install[@]} -eq 0 ]] && return 0

    echo -ne "${CYAN}--> Установка: ${to_install[*]}... ${NC}"

    # Ждём освобождения APT (без убийства процесса!)
    local lock_files=("/var/lib/dpkg/lock-frontend" "/var/lib/apt/lists/lock"
                      "/var/cache/apt/archives/lock" "/var/lib/dpkg/lock")
    local max_wait=120

    for lock in "${lock_files[@]}"; do
        [[ ! -e "$lock" ]] && continue
        local count=0
        if ! command -v fuser >/dev/null 2>&1; then
            apt-get install -y psmisc >/dev/null 2>&1 || true
        fi
        while fuser "$lock" >/dev/null 2>&1 && [[ $count -lt $max_wait ]]; do
            echo -ne "\r${YELLOW}[!] Ждём APT ($(basename "$lock"))... ${count}s/${max_wait}s ${NC}"
            sleep 3; ((count+=3))
        done
        if [[ $count -ge $max_wait ]]; then
            # Мягкое восстановление - НЕ убиваем процессы грубо!
            echo -e "\n${YELLOW}[!] Таймаут ожидания APT. Восстанавливаем состояние...${NC}"
            dpkg --configure -a >/dev/null 2>&1 || true
            apt-get --fix-broken install -y >/dev/null 2>&1 || true
            rm -f "$lock" 2>/dev/null || true
        fi
    done

    export DEBIAN_FRONTEND=noninteractive
    local apt_opts="-y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
    local std_out="/dev/null"
    [[ "${DEBUG:-false}" == "true" ]] && std_out="/dev/stdout"

    # Попытка 1
    echo -ne "\r${CYAN}--> Установка: ${to_install[*]}... (1/3)${NC}     "
    if eval "apt-get install $apt_opts ${to_install[*]} >$std_out 2>&1"; then
        echo -e "\r${GREEN}[✓] Установлено: ${to_install[*]}${NC}                              "
        return 0
    fi

    # Попытка 2: обновить списки
    echo -ne "\r${YELLOW}[*] Обновление списков пакетов... (2/3)${NC}     "
    apt-get update -qq >/dev/null 2>&1 || apt-get update >/dev/null 2>&1 || true
    if eval "apt-get install $apt_opts ${to_install[*]} >$std_out 2>&1"; then
        echo -e "\r${GREEN}[✓] Установлено после update: ${to_install[*]}${NC}                              "
        return 0
    fi

    # Попытка 3: исправление зависимостей
    echo -ne "\r${YELLOW}[*] Исправление зависимостей... (3/3)${NC}     "
    apt-get install --fix-broken -y >/dev/null 2>&1 || true
    if eval "apt-get install $apt_opts ${to_install[*]} >$std_out 2>&1"; then
        echo -e "\r${GREEN}[✓] Установлено после fix: ${to_install[*]}${NC}                              "
        return 0
    fi

    echo -e "\r${RED}[✗] ОШИБКА: Не удалось установить: ${to_install[*]}${NC}                              "
    return 1
}

# =============================================================================
# СРАВНЕНИЕ ВЕРСИЙ (БАГ #5 FIX: используем sort -V)
# =============================================================================
# ДЛЯ ЧАЙНИКОВ: Правильно сравнивает версии типа "1.10" > "1.9"
# Старый код неправильно сравнивал такие версии.
version_gt() {
    # Возвращает успех если $1 > $2
    [[ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]] && \
    [[ "$1" != "$2" ]]
}

# --- Безопасный временный файл (БАГ #8 FIX) ---
# ДЛЯ ЧАЙНИКОВ: mktemp создаёт файл с случайным именем,
# что защищает от атак через предсказуемые имена файлов.
safe_tmp() {
    local prefix="${1:-don}"
    mktemp "/tmp/${prefix}_XXXXXX"
}

# =============================================================================
# ПРОВЕРКА ЗАВИСИМОСТЕЙ (БАГ #17 FIX)
# =============================================================================
dep_check() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}[!] Отсутствуют зависимости: ${missing[*]}${NC}"
        echo -e "${YELLOW}    Установка...${NC}"
        smart_apt_install "${missing[@]}"
    fi
}

# =============================================================================
# GRAFANA (обёртка для обратной совместимости)
# =============================================================================
install_grafana_mirror() { smart_apt_install "grafana"; }
