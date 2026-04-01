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

install_sysctl() {
    echo -e "\n${CYAN}[*] Включение РЕЖИМА БОГА (BBR + TCP Тюнинг + Anti-DDoS)...${NC}"
    
    cat << 'EOF' > /etc/sysctl.conf
# ==========================================
# 🚀 РЕЖИМ БОГА: СКОРОСТЬ И ОТКЛЮЧЕНИЕ IPV6
# ==========================================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.ens3.disable_ipv6 = 1

# ==========================================
# ⚡ ТЮНИНГ ДЛЯ XRAY И NGINX (ВЫСОКАЯ НАГРУЗКА)
# ==========================================
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# ==========================================
# 🛡️ БАЗОВАЯ ЗАЩИТА ОТ DDOS И СКАНЕРОВ
# ==========================================
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 65535
net.ipv4.tcp_synack_retries = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF

    sysctl -p >/dev/null 2>&1
    local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local tfo_status=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
    
    echo -e "${GREEN}[+] Ядро Linux успешно переведено в максимальный режим!${NC}"
    echo -e "${GRAY} └─ Алгоритм: ${YELLOW}${bbr_status^^}${GRAY} | FastOpen: ${YELLOW}${tfo_status}${NC}"
}

install_all() {
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
        echo -e "${BOLD}${MAGENTA}  🛠️  УСТАНОВКА И ИНИЦИАЛИЗАЦИЯ${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${CYAN}Перед установкой защиты убедитесь, что ваш Nginx и Xray${NC}"
        echo -e " ${CYAN}настроены на передачу IP-адресов. Иначе защита не сработает!${NC}"
        echo -e " ${YELLOW}👉 Нажмите [5], чтобы прочитать инструкцию.${NC}\n"
        echo -e " ${GREEN}1.${NC} 🚀 Установить ВСЁ сразу (Sysctl + UFW + Fail2Ban + Logrotate)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${YELLOW}2.${NC} Только защита ядра (Sysctl) $(get_sysctl_status)"
        echo -e " ${YELLOW}3.${NC} Только инициализация UFW    $(get_ufw_status)"
        echo -e " ${YELLOW}4.${NC} Только установка Fail2Ban   $(get_f2b_status)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${MAGENTA}${BOLD}5. 📖 ЧИТАТЬ ИНСТРУКЦИЮ (ИДЕАЛЬНЫЙ NGINX + XRAY)${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) install_all ;; 
            2) install_sysctl; pause ;; 
            3) ufw_auto_protect_open_ports; ufw_global_setup; pause ;; 
            4) install_fail2ban; pause ;; 
            5) show_prereq_instructions ;; 
            0) return ;;
            *) echo -e "${RED}Ошибка: Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}