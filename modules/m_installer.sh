#!/bin/bash
# Модуль установки компонентов защиты

show_prereq_instructions() {
    clear
    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${BOLD}${YELLOW} ⚠️ ИНСТРУКЦИЯ ДЛЯ ЧАЙНИКОВ: НАСТРОЙКА NGINX И ЗАЩИТЫ ⚠️${NC}"
    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${CYAN} ${BOLD}КАК РАБОТАЕТ ИДЕАЛЬНАЯ ЗАЩИТА (ПРИМЕР):${NC}"
    echo -e "${GRAY} Представьте, что ваш сервер — это ночной клуб. Xray — это вышибала.${NC}"
    echo -e "${GREEN} 1. Приходит ВАШ клиент (REALITY)${NC}${GRAY} -> Вышибала узнает пароль и пускает сразу.${NC}"
    echo -e "${CYAN} 2. Приходит ВАШ клиент (XHTTP)${NC}${GRAY}   -> Вышибала передает его администратору (Nginx),${NC}"
    echo -e "${GRAY}                                    Nginx проверяет ваш секретный домен и пускает.${NC}"
    echo -e "${RED} 3. Приходит ХАКЕР или бот РКН${NC}${GRAY}    -> Вышибала передает его Nginx, Nginx отправляет${NC}"
    echo -e "${GRAY}                                    его на сайт Яндекса (маскировка), но при этом${NC}"
    echo -e "${GRAY}                                    ${RED}ЗАПИСЫВАЕТ ЕГО IP В ЛОГ${GRAY}. Fail2Ban дает БАН!${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 1] Настройка в панели (Xray Inbounds)${NC}"
    echo -e " Независимо от того, используете вы ТОЛЬКО REALITY или REALITY + XHTTP,"
    echo -e " найдите в настройках REALITY параметры и измените их так:"
    echo -e " ${RED}\"target\": \"www.yandex.com:443\"${NC} ===> ${GREEN}\"target\": \"/dev/shm/nginx.sock\"${NC} ${GRAY}(или dest)${NC}"
    echo -e " ${RED}\"xver\": 0${NC} ===> ${GREEN}\"xver\": 1${NC} ${GRAY}(ОБЯЗАТЕЛЬНО! Это передаст IP хакера в лог)${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 2] Сохранение логов (Файл: ${YELLOW}/opt/remnawave/docker-compose.yml${GREEN})${NC}"
    echo -e " Чтобы логи не удалялись при перезагрузке, найдите контейнер ${CYAN}remnawave-nginx${NC}"
    echo -e " и добавьте в блок ${CYAN}volumes:${NC} эту строчку:"
    echo -e " ${GREEN}- /opt/remnawave/nginx_logs:/var/log/nginx_custom${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 3] Настройка самого Nginx (Файл: ${YELLOW}/opt/remnawave/nginx.conf${GREEN})${NC}"
    
    echo -e " ${YELLOW}ВАРИАНТ А: У вас ТОЛЬКО REALITY (Старый/Простой конфиг)${NC}"
    echo -e " Внутри блока ${CYAN}server { ... }${NC} добавьте:"
    echo -e " ${GREEN}listen unix:/dev/shm/nginx.sock proxy_protocol ssl;${NC}"
    echo -e " ${GREEN}set_real_ip_from unix:;${NC}"
    echo -e " ${GREEN}real_ip_header proxy_protocol;${NC}"
    echo -e " ${GREEN}access_log /var/log/nginx_custom/access.log;${NC}\n"
    echo -e " ${GREEN}error_log /var/log/nginx_custom/error.log;${NC}\n"

    echo -e " ${YELLOW}ВАРИАНТ Б: У вас REALITY + XHTTP (Продвинутая 'Матрешка')${NC}"
    echo -e " У вас должно быть ДВА блока. В наружном блоке ${CYAN}stream { ... }${NC} укажите:"
    echo -e " ${GREEN}access_log /var/log/nginx_custom/stream_scanners.log stream_routing;${NC}"
    echo -e " А во внутреннем блоке ${CYAN}http { server { ... } }${NC} укажите:"
    echo -e " ${GREEN}access_log /var/log/nginx_custom/access.log;${NC}\n"
    echo -e " ${GREEN}error_log /var/log/nginx_custom/error.log;${NC}\n"

    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${YELLOW} После внесения изменений ПЕРЕСОБЕРИТЕ КОНТЕЙНЕРЫ командой:${NC}"
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
