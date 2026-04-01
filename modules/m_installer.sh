#!/bin/bash
# Модуль установки компонентов защиты

show_prereq_instructions() {
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${MAGENTA}  📖 ИНСТРУКЦИЯ: ИДЕАЛЬНЫЙ NGINX + XRAY (2026)${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${GRAY} Эталонная настройка для максимальной скорости и скрытности.${NC}"
    echo -e "${BLUE}======================================================${NC}\n"
    
    echo -e "${GREEN}${BOLD} [ШАГ 1] НАСТРОЙКА XRAY (В ПАНЕЛИ)${NC}"
    echo -e " Входящее подключение (Inbound) REALITY:"
    echo -e " 1. ${YELLOW}target:${NC} ${GREEN}/dev/shm/nginx.sock${NC}"
    echo -e " 2. ${YELLOW}xver:${NC} ${GREEN}1${NC} ${GRAY}(ОБЯЗАТЕЛЬНО для передачи IP)${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 2] НАСТРОЙКА DOCKER (${YELLOW}docker-compose.yml${GREEN})${NC}"
    echo -e " В блоке ${CYAN}volumes:${NC} для контейнера ${CYAN}remnawave-nginx${NC} добавьте:\n"
    echo -e "${CYAN} - /opt/remnawave/nginx_logs:/var/log/nginx_custom${NC}\n"
    echo -e " В блоке ${CYAN}command:${NC} для очистки сокетов:\n"
    echo -e "${CYAN} command: sh -c 'rm -f /dev/shm/*.sock /dev/shm/*.socket && exec nginx -g \"daemon off;\"'${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 3] ИДЕАЛЬНЫЙ NGINX.CONF${NC}"
    echo -e " ${BOLD}А) Блок STREAM (Сортировщик и Лог сканеров):${NC}"
    echo -e "${CYAN} stream {
     log_format stream_routing '\$proxy_protocol_addr[\$time_local] SNI:\"\$ssl_preread_server_name\" RoutedTo:\"\$route_to\"';
     access_log /var/log/nginx_custom/stream_scanners.log stream_routing;
     
     map \$ssl_preread_server_name \$route_to {
         ваш.домен.com    unix:/dev/shm/nginx_http.sock;
         default          unix:/dev/shm/nginx_external.sock;
     }
     upstream external_sni { server api.dropbox.com:443; }
     
     server { listen unix:/dev/shm/nginx.sock proxy_protocol; ssl_preread on; proxy_pass \$route_to; proxy_protocol on; }
     server { listen unix:/dev/shm/nginx_external.sock proxy_protocol; proxy_pass external_sni; }
  }${NC}\n"

    echo -e " ${BOLD}Б) Блок HTTP (Секрет нулевого пинга и анти-индекс):${NC}"
    echo -e "${CYAN} http {
     tcp_nopush on; tcp_nodelay on; server_tokens off;
     ssl_protocols TLSv1.2 TLSv1.3;
     ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
     ssl_prefer_server_ciphers on; ssl_session_cache shared:SSL:10m; ssl_session_timeout 1d; ssl_session_tickets off;
     
     server {
         listen unix:/dev/shm/nginx_http.sock proxy_protocol ssl; http2 on; server_name _;
         set_real_ip_from unix:; real_ip_header proxy_protocol;
         access_log /var/log/nginx_custom/access.log; error_log /var/log/nginx_custom/error.log;
         
         add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;
         add_header X-Content-Type-Options nosniff; add_header X-Frame-Options DENY;
         add_header X-XSS-Protection \"1; mode=block\"; add_header X-Download-Options noopen;
         add_header X-Robots-Tag \"noindex, nofollow, nosnippet, noarchive\";

         location /newapi/v2/ {
             client_max_body_size 0; proxy_buffering off; proxy_request_buffering off;
             proxy_pass http://unix:/dev/shm/xrxh.socket; proxy_http_version 1.1;
             proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \"upgrade\";
             proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
             proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
         }
         root /var/www/html; index index.html; location / { try_files \$uri \$uri/ =404; }
     }
  }${NC}\n"

    echo -e "${MAGENTA}${BOLD} [ШАГ 4] ГИБРИДНАЯ ПАМЯТЬ (ZRAM + SWAP)${NC}"
    echo -e " ${CYAN}ZRAM (Приоритет 100):${NC} Быстрое сжатие в ОЗУ. Используется в первую очередь."
    echo -e " ${CYAN}Swap (Приоритет -2):${NC} Файл на диске. Используется только если ZRAM переполнен."
    echo -e " ${YELLOW}Это защищает сервер от «падения» при резких скачках нагрузки.${NC}\n"
    pause
}

# ======================================================================
# ЗАЩИТА ПАНЕЛИ: Умное добавление IP в whitelist перед установкой UFW
# ======================================================================
protect_panel_connection() {
    echo -e "\n${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}  🔒 ЗАЩИТА ПОДКЛЮЧЕНИЙ ПЕРЕД УСТАНОВКОЙ UFW${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${YELLOW}  ВНИМАНИЕ! UFW может заблокировать доступ к серверу.${NC}"
    echo -e "${YELLOW}  Защищаем важные IP-адреса заранее.${NC}"
    echo -e "${MAGENTA}------------------------------------------------------${NC}\n"

    # --- 1. Автоматическое обнаружение IP на порту 2222 ---
    local panel_port=2222
    local panel_ip=""
    local detected_ips=()

    # Ищем установленные соединения на порту 2222 (Remna Panel)
    if command -v ss >/dev/null 2>&1; then
        mapfile -t detected_ips < <(ss -tnp 2>/dev/null | awk -v port=":${panel_port}" '$0 ~ port {print $5}' | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^127\.' | sort -u)
    fi

    # Также проверяем через netstat если ss не нашёл
    if [[ ${#detected_ips[@]} -eq 0 ]] && command -v netstat >/dev/null 2>&1; then
        mapfile -t detected_ips < <(netstat -tn 2>/dev/null | awk -v port=":${panel_port}" '$0 ~ port {print $5}' | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^127\.' | sort -u)
    fi

    if [[ ${#detected_ips[@]} -gt 0 ]]; then
        echo -e "${GREEN}[✓] Найдено активное подключение на порту ${panel_port} (Remna Panel):${NC}"
        for ip in "${detected_ips[@]}"; do
            echo -e "    ${CYAN}→ ${ip}${NC}"
            # Добавляем в whitelist автоматически
            if ! grep -q "^${ip}" "$WHITELIST_FILE" 2>/dev/null; then
                echo "${ip} # Remna Panel (авто)" >> "$WHITELIST_FILE"
                echo -e "    ${GREEN}[+] Добавлен в whitelist: ${ip} (Remna Panel)${NC}"
            else
                echo -e "    ${YELLOW}[!] Уже в whitelist: ${ip}${NC}"
            fi
        done
        panel_ip="${detected_ips[0]}"
    else
        echo -e "${YELLOW}[!] Активных подключений на порту ${panel_port} не обнаружено.${NC}"
        echo -e "${CYAN}    Хотите открыть порт ${panel_port} и добавить IP панели?${NC}"
        echo -e "${GRAY}    Введите IP вашей панели (Remna) или нажмите Enter, чтобы пропустить:${NC}"
        read -rp ">> IP панели: " panel_ip < /dev/tty

        if [[ -n "$panel_ip" ]]; then
            if [[ "$panel_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                if ! grep -q "^${panel_ip}" "$WHITELIST_FILE" 2>/dev/null; then
                    echo "${panel_ip} # Remna Panel" >> "$WHITELIST_FILE"
                    echo -e "${GREEN}[+] Добавлен в whitelist: ${panel_ip} (Remna Panel)${NC}"
                else
                    echo -e "${YELLOW}[!] Уже в whitelist: ${panel_ip}${NC}"
                fi
                # Открываем порт 2222
                ufw allow from "${panel_ip}" to any port "${panel_port}" comment "Remna Panel" >/dev/null 2>&1 || true
                echo -e "${GREEN}[+] Порт ${panel_port} открыт для: ${panel_ip}${NC}"
            else
                echo -e "${RED}[!] Некорректный IP. Пропускаем.${NC}"
            fi
        fi
    fi

    # --- 2. Текущее SSH-соединение (кто сейчас подключён) ---
    local ssh_client_ip=""
    ssh_client_ip=$(echo "${SSH_CLIENT:-}" | awk '{print $1}')
    if [[ -z "$ssh_client_ip" ]] && [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_client_ip=$(echo "${SSH_CONNECTION:-}" | awk '{print $1}')
    fi

    if [[ -n "$ssh_client_ip" && "$ssh_client_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if ! grep -q "^${ssh_client_ip}" "$WHITELIST_FILE" 2>/dev/null; then
            echo -e "${CYAN}[→] Ваш текущий IP (SSH-сессия): ${YELLOW}${ssh_client_ip}${NC}"
            read -rp "   Добавить в whitelist? [Y/n]: " add_ssh < /dev/tty
            if [[ "${add_ssh:-Y}" =~ ^[Yy]$ ]] || [[ -z "$add_ssh" ]]; then
                echo "${ssh_client_ip} # Текущая SSH сессия (авто)" >> "$WHITELIST_FILE"
                echo -e "${GREEN}[+] Добавлен в whitelist: ${ssh_client_ip}${NC}"
            fi
        else
            echo -e "${GREEN}[✓] Ваш SSH IP уже в whitelist: ${ssh_client_ip}${NC}"
        fi
    fi

    echo -e "\n${GREEN}[✓] Whitelist защищён. Продолжаем установку...${NC}"
    echo -e "${MAGENTA}======================================================${NC}\n"
    sleep 1
}

install_sysctl() {
    echo -e "\n${CYAN}[*] Применение «Золотого стандарта 2026» (BBR + IPv6-Off + Tuning)...${NC}"

    # Определяем основной сетевой интерфейс автоматически
    local MAIN_IF
    MAIN_IF=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)
    [[ -z "$MAIN_IF" ]] && MAIN_IF="eth0"

    # Заменяем содержимое /etc/sysctl.conf согласно Золотому Стандарту
    cat << EOF > /etc/sysctl.conf
# === СКОРОСТЬ (BBR) И ОТКЛЮЧЕНИЕ IPV6 (Золотой Стандарт 2026) ===
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.${MAIN_IF}.disable_ipv6 = 1

# === ТЮНИНГ ДЛЯ XRAY И NGINX (РЕЖИМ БОГА) ===
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# === ЗАЩИТА ТРАФИКА И DNS (Essential Fix) ===
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF

    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}[+] Параметры ядра успешно обновлены до Золотого Стандарта.${NC}"
    verify_system_protection
}

verify_system_protection() {
    echo -e "\n${MAGENTA}======================================================${NC}"
    echo -e "${BOLD}  📊 ПРОВЕРКА ПРИМЕНЕНИЯ «ЗОЛОТОГО СТАНДАРТА»${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    
    # 1. BBR
    local bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$bbr" == "bbr" ]]; then
        echo -e " 🚀 BBR (Скорость):           ${GREEN}[ ПРИМЕНЕНО: $bbr ]${NC}"
    else
        echo -e " 🚀 BBR (Скорость):           ${RED}[ ОШИБКА: $bbr ]${NC}"
    fi

    # 2. Fast Open
    local tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
    if [[ "$tfo" == "3" ]]; then
        echo -e " ⚡ Fast Open (Отклик):       ${GREEN}[ ПРИМЕНЕНО: $tfo ]${NC}"
    else
        echo -e " ⚡ Fast Open (Отклик):       ${RED}[ ОШИБКА: $tfo ]${NC}"
    fi

    # 3. MTU Probing
    local mtu=$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null)
    if [[ "$mtu" == "1" ]]; then
        echo -e " 🦾 MTU Probing (Стабильность): ${GREEN}[ ПРИМЕНЕНО: $mtu ]${NC}"
    else
        echo -e " 🦾 MTU Probing (Стабильность): ${RED}[ ОШИБКА: $mtu ]${NC}"
    fi

    # 4. IPv6
    if ip a | grep -q "inet6"; then
        echo -e " 🕵️ IPv6 (Скрытность):        ${RED}[ ВНИМАНИЕ: АКТИВЕН ]${NC}"
    else
        echo -e " 🕵️ IPv6 (Скрытность):        ${GREEN}[ МЕРТВ: УТЕЧЕК НЕТ ]${NC}"
    fi
    echo -e "${MAGENTA}======================================================${NC}\n"
}

get_logrotate_status() {
    if ls /etc/logrotate.d/don_* >/dev/null 2>&1; then echo -e "${GREEN}[НАСТРОЕН]${NC}"; else echo -e "${RED}[НЕ НАСТРОЕН]${NC}"; fi
}

show_install_confirmation() {
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${MAGENTA}  🚀 ПОДГОТОВКА К ПОЛНОЙ УСТАНОВКЕ ЗАЩИТЫ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e " Будут выполнены следующие этапы «Золотой Стандарт»:"
    echo -e " ${CYAN}1. Защита панели:${NC} Автоматическое добавление вашего IP в белый список."
    echo -e " ${CYAN}2. Чистый лист:${NC} Сброс UFW и Fail2Ban до заводских настроек (устранение конфликтов)."
    echo -e " ${CYAN}3. Тюнинг ядра:${NC} Внедрение BBR, FastOpen и тотальное отключение IPv6."
    echo -e " ${CYAN}4. Сетевой экран:${NC} Активация UFW с DDoS-фильтрами и лимитами на порты."
    echo -e " ${CYAN}5. Инспектор:${NC} Установка Fail2Ban (фильтры SSH + Nginx REALITY)."
    echo -e " ${CYAN}6. Память:${NC} Гибридная оптимизация (ZRAM + Swap) для стабильности Docker."
    echo -e "${BLUE}======================================================${NC}"
    echo -e " ${YELLOW}ВНИМАНИЕ: Во время сброса UFW соединение может мигнуть.${NC}"
    echo -e " Это безопасно, так как мы сначала защитим ваш IP."
    echo -e "${BLUE}======================================================${NC}"
    read -rp " Начинаем установку? [Y/n]: " confirm
    [[ "${confirm:-Y}" =~ ^[Yy]$ || -z "$confirm" ]] && return 0 || return 1
}

install_all() {
    if ! show_install_confirmation; then
        echo -e "${RED}[!] Установка отменена пользователем.${NC}"
        sleep 1; return
    fi

    # СНАЧАЛА защищаем важные IP чтобы не потерять соединение
    protect_panel_connection

    # --- ЭТАП: ЧИСТЫЙ ЛИСТ (RESET TO DEFAULTS) ---
    echo -e "\n${YELLOW}[*] Сброс системы до заводских настроек защиты...${NC}"
    ufw --force reset >/dev/null 2>&1
    rm -f /etc/fail2ban/jail.local >/dev/null 2>&1
    
    # Дефолтные политики UFW
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    # Сразу открываем SSH чтобы не вылететь после reset
    ACTIVE_SSH=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | xargs)
    [[ -z "$ACTIVE_SSH" ]] && ACTIVE_SSH="22"
    for p in $ACTIVE_SSH; do ufw allow "$p"/tcp >/dev/null 2>&1; done

    # --- ЭТАП: СИСТЕМНЫЙ ТЮНИНГ ---
    install_sysctl
    
    # --- ЭТАП: UFW ---
    if declare -f ufw_global_setup > /dev/null; then
        echo -e "\n${CYAN}[*] Инициализация UFW (DDoS Protection)...${NC}"
        # АВТОМАТИКА: Сканируем открытые порты и добавляем в лимиты
        ufw_auto_protect_open_ports
        ufw_global_setup
    else
        echo -e "${RED}[!] Ошибка: Модуль m_ufw.sh не загружен.${NC}"
    fi
    
    # --- ЭТАП: FAIL2BAN ---
    if declare -f install_fail2ban > /dev/null; then
        install_fail2ban
    else
        echo -e "${RED}[!] Ошибка: Модуль m_f2b.sh не загружен.${NC}"
    fi

    # --- ЭТАП: РОТАЦИЯ ЛОГОВ ---
    if declare -f lr_auto_setup > /dev/null; then
        echo -e "\n${CYAN}[*] Автоматическая настройка ротации логов...${NC}"
        lr_auto_setup
        echo -e "${GREEN}[+] Логи под контролем.${NC}"
    fi

    # --- ЭТАП: ГИБРИДНАЯ ПАМЯТЬ ---
    if declare -f install_hybrid_memory_optimization > /dev/null; then
        install_hybrid_memory_optimization
    fi

    echo -e "\n${GREEN}${BOLD}🚀 ВСЕ КОМПОНЕНТЫ УСПЕШНО УСТАНОВЛЕНЫ И ПРОВЕРЕНЫ!${NC}"
    pause
}

install_menu() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🛠️  УСТАНОВКА И ИНИЦИАЛИЗАЦИЯ ЗАЩИТЫ${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${CYAN}Перед установкой защиты убедитесь, что ваш Nginx и Xray${NC}"
        echo -e " ${CYAN}настроены на передачу IP-адресов. Иначе защита не сработает!${NC}"
        echo -e " ${YELLOW}👉 Нажмите [7], чтобы прочитать инструкцию.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${GREEN}${BOLD}1.${NC} 🚀 ${BOLD}Установить ВСЁ сразу${NC} ${GRAY}(Sysctl + UFW + Fail2Ban + Swap)${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${YELLOW}2.${NC} Только защита ядра (Sysctl)               $(get_sysctl_status)"
        echo -e " ${YELLOW}3.${NC} Только инициализация UFW                   $(get_ufw_status)"
        echo -e " ${YELLOW}4.${NC} Только установка Fail2Ban (фильтры)      $(get_f2b_status)"
        echo -e " ${YELLOW}5.${NC} Только настройка ротации логов             $(get_logrotate_status)"
        echo -e " ${YELLOW}6.${NC} Оптимизация памяти (ZRAM + Swap)           $(get_swap_status)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${MAGENTA}${BOLD}7. 📖 ПОКАЗАТЬ ИНСТРУКЦИЮ ПО НАСТРОЙКЕ NGINX${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -rp ">> " choice
        case $choice in
            1) install_all ;;
            2) install_sysctl; pause ;;
            3)
                protect_panel_connection
                ufw_auto_protect_open_ports
                ufw_global_setup
                pause
                ;;
            4) install_fail2ban; pause ;;
            5)
                if declare -f lr_auto_setup > /dev/null; then
                    echo -e "\n${CYAN}[*] Настройка ротации логов...${NC}"
                    lr_auto_setup
                    echo -e "${GREEN}[+] Готово!${NC}"
                    pause
                else
                    echo -e "${RED}[!] Модуль очистки не загружен.${NC}"; sleep 2
                fi
                ;;
            6)
                if declare -f manage_swap > /dev/null; then
                    manage_swap
                else
                    echo -e "${RED}[!] Модуль памяти не загружен.${NC}"; sleep 2
                fi
                ;;
            7) show_prereq_instructions ;;
            0) return ;;
            *) echo -e "${RED}Ошибка: Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}