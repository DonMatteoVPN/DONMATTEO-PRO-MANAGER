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
    echo -e "\n${CYAN}[*] Включение РЕЖИМА БОГА (BBR + TCP Тюнинг + Anti-DDoS)...${NC}"

    # Определяем основной сетевой интерфейс автоматически
    local MAIN_IF
    MAIN_IF=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)
    [[ -z "$MAIN_IF" ]] && MAIN_IF="eth0"

    cat << EOF > /etc/sysctl.d/99-donmatteo.conf
# ==========================================
# 🚀 РЕЖИМ БОГА: СКОРОСТЬ (BBR + FastOpen)
# Файл: /etc/sysctl.d/99-donmatteo.conf
# ==========================================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# ==========================================
# 🛡️ ЗАЩИТА ОТ DDOS (Безопасные настройки)
# ВАЖНО: rp_filter=2 (мягкий режим)
# rp_filter=1 ломает DNS на VPS с асимметричной маршрутизацией!
# ==========================================
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 65535
net.ipv4.tcp_synack_retries = 2
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.icmp_echo_ignore_broadcasts = 1

# ==========================================
# 🚫 ОТКЛЮЧЕНИЕ IPV6 (Только если нет IPv6)
# ==========================================
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.${MAIN_IF}.disable_ipv6 = 1
EOF

    sysctl --system >/dev/null 2>&1
    local bbr_status
    bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local tfo_status
    tfo_status=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)

    echo -e "${GREEN}[+] Ядро Linux успешно переведено в максимальный режим!${NC}"
    echo -e "${GRAY} └─ Алгоритм: ${YELLOW}${bbr_status^^}${GRAY} | FastOpen: ${YELLOW}${tfo_status}${GRAY} | Интерфейс: ${YELLOW}${MAIN_IF}${NC}"
    echo -e "${GRAY} └─ rp_filter: ${YELLOW}2 (мягкий, не ломает DNS)${NC}"
}

get_logrotate_status() {
    if ls /etc/logrotate.d/don_* >/dev/null 2>&1; then echo -e "${GREEN}[НАСТРОЕН]${NC}"; else echo -e "${RED}[НЕ НАСТРОЕН]${NC}"; fi
}

install_all() {
    # СНАЧАЛА защищаем важные IP чтобы не потерять соединение
    protect_panel_connection

    install_sysctl
    
    if declare -f ufw_global_setup > /dev/null; then
        echo -e "\n${CYAN}[*] Инициализация UFW (Полный Автомат)...${NC}"
        # АВТОМАТИКА: Сканируем открытые порты и добавляем в лимиты
        ufw_auto_protect_open_ports
        ufw_global_setup
    else
        echo -e "${RED}[!] Ошибка: Модуль m_ufw.sh не загружен.${NC}"
    fi
    
    if declare -f install_fail2ban > /dev/null; then
        install_fail2ban
    else
        echo -e "${RED}[!] Ошибка: Модуль m_f2b.sh не загружен.${NC}"
    fi

    if declare -f lr_auto_setup > /dev/null; then
        echo -e "\n${CYAN}[*] Автоматическая настройка ротации логов...${NC}"
        lr_auto_setup
        echo -e "${GREEN}[+] Логи Nginx и Ноды взяты под контроль.${NC}"
    fi
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
        echo -e " ${YELLOW}👉 Нажмите [6], чтобы прочитать инструкцию.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${GREEN}${BOLD}1.${NC} 🚀 ${BOLD}Установить ВСЁ сразу${NC} ${GRAY}(Sysctl + UFW + Fail2Ban + Logrotate)${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${YELLOW}2.${NC} Только защита ядра (Sysctl)               $(get_sysctl_status)"
        echo -e " ${YELLOW}3.${NC} Только инициализация UFW                   $(get_ufw_status)"
        echo -e " ${YELLOW}4.${NC} Только установка Fail2Ban (фильтры)      $(get_f2b_status)"
        echo -e " ${YELLOW}5.${NC} Только настройка ротации логов             $(get_logrotate_status)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${MAGENTA}${BOLD}6. 📖 ПОКАЗАТЬ ИНСТРУКЦИЮ ПО НАСТРОЙКЕ NGINX${NC}"
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
            6) show_prereq_instructions ;;
            0) return ;;
            *) echo -e "${RED}Ошибка: Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}