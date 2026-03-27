#!/bin/bash
# Модуль установки компонентов защиты

show_prereq_instructions() {
    clear
    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${BOLD}${YELLOW} ⚠️ ИНСТРУКЦИЯ: ИДЕАЛЬНАЯ МАСКИРОВКА XRAY (REALITY + XHTTP) ⚠️${NC}"
    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${CYAN} Для того чтобы оба протокола (Reality и XHTTP) работали на 443 порту${NC}"
    echo -e "${CYAN} и защита Fail2Ban видела реальные IP хакеров, выполните 3 шага:${NC}\n"

    echo -e "${GREEN}${BOLD}[ШАГ 1] Настройка в панели (Xray Inbounds)${NC}"
    echo -e " В настройках подключения REALITY найдите блок ${YELLOW}realitySettings${NC} и укажите:"
    echo -e " ${RED}\"dest\": \"www.yandex.com:443\"${NC}  ====>  ${GREEN}\"dest\": \"/dev/shm/nginx.sock\"${NC} ${GRAY}(или target)${NC}"
    echo -e " ${RED}\"xver\": 0${NC}  ====>  ${GREEN}\"xver\": 1${NC} ${GRAY}(ОБЯЗАТЕЛЬНО для передачи IP в Nginx!)${NC}\n"

    echo -e "${GREEN}${BOLD}[ШАГ 2] Проброс логов в Docker (${YELLOW}docker-compose.yml${GREEN})${NC}"
    echo -e " Добавьте в ${CYAN}volumes${NC} контейнера Nginx (чтобы логи не удалялись при рестарте):"
    echo -e " ${GREEN}- /opt/remnawave/nginx_logs:/var/log/nginx_custom${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 3] Двухуровневый Nginx (${YELLOW}nginx.conf${GREEN})${NC}"
    echo -e " Ваша архитектура должна состоять из ДВУХ блоков (Матрёшка):\n"
    
    echo -e " ${YELLOW}1. Наружный блок stream { ... } (ДО блока http!)${NC}"
    echo -e "    Он слушает ${CYAN}nginx.sock proxy_protocol;${NC} и работает как умный сортировщик."
    echo -e "    Пишет лог сканеров: ${GREEN}access_log /var/log/nginx_custom/stream_scanners.log stream_routing;${NC}"
    echo -e "    Свой домен отправляет внутрь, а чужие (РКН) - наружу (на wp.pl или Яндекc).\n"

    echo -e " ${YELLOW}2. Внутренний блок http { server { ... } } (Для вашего XHTTP)${NC}"
    echo -e "    Слушает ВНУТРЕННИЙ сокет: ${CYAN}listen unix:/dev/shm/nginx_http.sock proxy_protocol ssl;${NC}"
    echo -e "    Читает IP: ${CYAN}set_real_ip_from unix:; real_ip_header proxy_protocol;${NC}"
    echo -e "    Пишет HTTP лог: ${GREEN}access_log /var/log/nginx_custom/access.log;${NC}\n"

    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${YELLOW} После настройки конфигов ПЕРЕСОБЕРИТЕ контейнеры:${NC}"
    echo -e "${CYAN} cd /opt/remnawave && docker compose down && docker compose build --no-cache && docker compose up -d${NC}"
    echo -e "${MAGENTA}======================================================================${NC}"
    pause
}

install_sysctl() {
    echo -e "\n${CYAN}[*] Настройка параметров ядра (Sysctl)...${NC}"
    cat << 'EOF' > /etc/sysctl.d/99-anti-ddos.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_synack_retries = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF
    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}[+] Защита ядра активирована.${NC}"
    pause
}

install_ufw() {
    echo -e "\n${CYAN}[*] Настройка UFW (Сетевой экран)...${NC}"
    apt-get install ufw -y >/dev/null 2>&1
    cp /etc/ufw/before.rules /etc/ufw/before.rules.bak
    sed -i '/# --- НАЧАЛО: Правила защиты от DDoS/,/# --- КОНЕЦ: Направляем трафик/d' /etc/ufw/before.rules
    sed -i '/\*filter/a \
# --- НАЧАЛО: Правила защиты от DDoS (DonMatteo) ---\n\
:IN_LIMIT - [0:0]\n\
-A IN_LIMIT -m limit --limit 80/s --limit-burst 250 -j RETURN\n\
-A IN_LIMIT -j DROP\n\
# --- КОНЕЦ: Правила защиты от DDoS ---\n\
\n\
:ufw-before-input -[0:0]\n\
\n\
# --- НАЧАЛО: Защита от сканеров и кривых пакетов ---\n\
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP\n\
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP\n\
# --- КОНЕЦ: Защита от сканеров ---\n\
\n\
# --- НАЧАЛО: Лимит одновременных соединений (Анти-ДДОС L4 на 1 IP) ---\n\
-A ufw-before-input -p tcp --dport 443 -m connlimit --connlimit-above 150 --connlimit-mask 32 -j DROP\n\
-A ufw-before-input -p tcp --dport 6443 -m connlimit --connlimit-above 150 --connlimit-mask 32 -j DROP\n\
# --- КОНЕЦ: Лимит одновременных соединений ---\n\
\n\
# --- НАЧАЛО: Направляем трафик на проверку скорости (Глобальный лимит) ---\n\
-A ufw-before-input -p tcp --dport 22 -m conntrack --ctstate NEW -j IN_LIMIT\n\
-A ufw-before-input -p tcp --dport 443 -m conntrack --ctstate NEW -j IN_LIMIT\n\
-A ufw-before-input -p tcp --dport 6443 -m conntrack --ctstate NEW -j IN_LIMIT\n\
-A ufw-before-input -p tcp --dport 2222 -m conntrack --ctstate NEW -j IN_LIMIT\n\
# --- КОНЕЦ: Направляем трафик на проверку скорости ---' /etc/ufw/before.rules

    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw allow 22/tcp comment 'Secure SSH' >/dev/null 2>&1
    ufw allow 443/tcp comment 'VLESS Reality/XHTTP' >/dev/null 2>&1
    ufw allow 6443/tcp comment 'VLESS Reality/XHTTP' >/dev/null 2>&1
    ufw allow from 11.22.33.4 to any port 2222 comment 'Remna Panel' >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1
    echo -e "${GREEN}[+] UFW успешно инициализирован.${NC}"
    pause
}

install_all() {
    install_sysctl
    install_ufw
    install_fail2ban # <-- Исправлено здесь
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
        echo -e " ${GREEN}1.${NC} 🚀 Установить ВСЁ сразу (Sysctl + UFW + Fail2Ban)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${YELLOW}2.${NC} Только защита ядра (Sysctl) $(get_sysctl_status)"
        echo -e " ${YELLOW}3.${NC} Только инициализация UFW    $(get_ufw_status)"
        echo -e " ${YELLOW}4.${NC} Только установка Fail2Ban   $(get_f2b_status)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${MAGENTA}${BOLD}5. 📖 ЧИТАТЬ ИНСТРУКЦИЮ (НАСТРОЙКА NGINX + XRAY)${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) install_all ;; 
            2) install_sysctl ;; 
            3) install_ufw ;; 
            4) install_fail2ban ;; # <-- Исправлено здесь
            5) show_prereq_instructions ;; 
            0) return ;;
            *) echo -e "${RED}Ошибка: Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}
