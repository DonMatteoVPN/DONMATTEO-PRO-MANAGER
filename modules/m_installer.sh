#!/bin/bash
# Модуль установки компонентов защиты

show_prereq_instructions() {
    clear
    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${BOLD}${YELLOW} ⚠️  МЕГА-РУКОВОДСТВО: REALITY + XHTTP + ИДЕАЛЬНАЯ ЗАЩИТА ⚠️${NC}"
    echo -e "${MAGENTA}======================================================================${NC}"
    
    echo -e "${CYAN}${BOLD}КАК ЭТО РАБОТАЕТ (ЛОГИКА ПОТОКОВ):${NC}"
    echo -e " 1. ${GREEN}REALITY:${NC} Клиент стучится на 443 -> Xray узнает его и пускает сразу."
    echo -e " 2. ${BLUE}XHTTP:${NC}   Клиент стучится на 443 -> Xray не узнает Reality, отдает запрос"
    echo -e "    в Nginx (${YELLOW}stream${NC}). Nginx видит ваш домен и шлет запрос обратно в Xray (${YELLOW}xhttp${NC})."
    echo -e " 3. ${RED}СКАНЕР:${NC}  Стучится на 443 -> Xray отдает его в Nginx. Nginx не видит домена"
    echo -e "    и шлет бота на ${YELLOW}yandex.ru${NC}, но ПЕРЕД ЭТИМ записывает его IP в лог для бана.\n"

    echo -e "${GREEN}${BOLD} [ШАГ 1] НАСТРОЙКА XRAY (В ПАНЕЛИ)${NC}"
    echo -e " Найдите настройки входящего подключения (Inbound) REALITY:"
    echo -e " 1. ${YELLOW}target (или dest):${NC} ${GREEN}/dev/shm/nginx.sock${NC}"
    echo -e " 2. ${YELLOW}xver:${NC} ${GREEN}1${NC} ${GRAY}(ОБЯЗАТЕЛЬНО! Без этого Nginx не увидит IP для бана)${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 2] НАСТРОЙКА DOCKER (${YELLOW}docker-compose.yml${GREEN})${NC}"
    echo -e " Нужно вынести логи из контейнера наружу для Fail2Ban."
    echo -e " В блоке ${CYAN}volumes:${NC} для контейнера ${CYAN}remnawave-nginx${NC} добавьте:"
    echo -e " ${GREEN}- /opt/remnawave/nginx_logs:/var/log/nginx_custom${NC}\n"

    echo -e "${GREEN}${BOLD} [ШАГ 3] НАСТРОЙКА NGINX (${YELLOW}nginx.conf${GREEN})${NC}"
    echo -e " Ваш конфиг должен состоять из двух главных частей:\n"
    
    echo -e " ${BOLD}А) СНАРУЖИ (Блок stream) — Сортировщик и Лог сканеров:${NC}"
    echo -e " ${GRAY}Этот блок должен быть ВНЕ блока http (обычно в самом начале файла)${NC}"
    echo -e "${CYAN} stream {
    log_format stream_routing '\$proxy_protocol_addr[\$time_local] SNI:\"\$ssl_preread_server_name\" RoutedTo:\"\$route_to\"';
    access_log /var/log/nginx_custom/stream_scanners.log stream_routing;
    
    map \$ssl_preread_server_name \$route_to {
        ваш.домен.com    unix:/dev/shm/nginx_http.sock;
        default          unix:/dev/shm/nginx_external.sock;
    }
    # ... далее блоки upstream и server ...
 }${NC}\n"

    echo -e " ${BOLD}Б) ВНУТРИ (Блок http -> server) — Ваш сайт и XHTTP:${NC}"
    echo -e " Внутри ${CYAN}server { ... }${NC} обязательно пропишите эти пути:"
    echo -e " ${GREEN}listen unix:/dev/shm/nginx_http.sock proxy_protocol ssl;${NC}"
    echo -e " ${GREEN}set_real_ip_from unix:; real_ip_header proxy_protocol;${NC}"
    echo -e " ${GREEN}access_log /var/log/nginx_custom/access.log;${NC}"
    echo -e " ${GREEN}error_log  /var/log/nginx_custom/error.log;${NC}\n"

    echo -e "${MAGENTA}======================================================================${NC}"
    echo -e "${YELLOW} ПРОВЕРКА: Если файлы /var/log/nginx_custom/access.log и stream_scanners.log${NC}"
    echo -e "${YELLOW} начали заполняться - значит всё настроено ВЕРНО!${NC}"
    echo -e "${CYAN} Команда для перезапуска: docker compose down && docker compose up -d${NC}"
    echo -e "${MAGENTA}======================================================================${NC}"
    pause
}

install_ufw() {
    echo -e "\n${CYAN}[*] Первичная настройка UFW (Сброс до заводских настроек)...${NC}"
    apt-get install ufw -y >/dev/null 2>&1
    
    # --- ШАГ 1: ПОИСК ТЕКУЩЕГО SSH ПОРТА ---
    # Ищем все строки Port в конфиге, берем первую цифру. Если пусто - ставим 22.
    local CURRENT_SSH=$(grep -i "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    [[ -z "$CURRENT_SSH" ]] && CURRENT_SSH="22"
    echo -e "${GRAY}Обнаружен активный SSH порт: ${YELLOW}$CURRENT_SSH${NC}"

    # --- ШАГ 2: СБРОС ПРАВИЛ ---
    ufw --force reset >/dev/null 2>&1
    cp /etc/ufw/before.rules /etc/ufw/before.rules.bak
    
    # Очищаем старые записи нашего скрипта
    sed -i '/# --- НАЧАЛО: Правила защиты от DDoS/,/# --- КОНЕЦ: Направляем трафик/d' /etc/ufw/before.rules

    # --- ШАГ 3: ИНЪЕКЦИЯ ПРАВИЛ (С дефолтными лимитами 80/150) ---
    # Мы подставляем $CURRENT_SSH в правила лимитов скорости
    sed -i '/\*filter/a \
# --- НАЧАЛО: Правила защиты от DDoS (DonMatteo) ---\n\
:IN_LIMIT - [0:0]\n\
-A IN_LIMIT -m limit --limit 80/s --limit-burst 250 -j RETURN\n\
-A IN_LIMIT -j DROP\n\
# --- КОНЕЦ: Правила защиты от DDoS ---\n\
\n\
:ufw-before-input - [0:0]\n\
\n\
# --- НАЧАЛО: Защита от сканеров и кривых пакетов ---\n\
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP\n\
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP\n\
# --- КОНЕЦ: Защита от сканеров ---\n\
\n\
# --- НАЧАЛО: Лимит одновременных соединений (Дефолт 150) ---\n\
-A ufw-before-input -p tcp --dport 443 -m connlimit --connlimit-above 150 --connlimit-mask 32 -j DROP\n\
-A ufw-before-input -p tcp --dport 8443 -m connlimit --connlimit-above 150 --connlimit-mask 32 -j DROP\n\
# --- КОНЕЦ: Лимит одновременных соединений ---\n\
\n\
# --- НАЧАЛО: Направляем трафик на проверку скорости (Дефолт 80/s) ---\n\
-A ufw-before-input -p tcp --dport '"$CURRENT_SSH"' -m conntrack --ctstate NEW -j IN_LIMIT\n\
-A ufw-before-input -p tcp --dport 443 -m conntrack --ctstate NEW -j IN_LIMIT\n\
-A ufw-before-input -p tcp --dport 8443 -m conntrack --ctstate NEW -j IN_LIMIT\n\
-A ufw-before-input -p tcp --dport 2222 -m conntrack --ctstate NEW -j IN_LIMIT\n\
# --- КОНЕЦ: Направляем трафик на проверку скорости ---' /etc/ufw/before.rules

    # --- ШАГ 4: ЗАПУСК И ПОРТЫ ---
    ufw default deny incoming >/dev/null 2>&1
    ufw allow "$CURRENT_SSH"/tcp comment 'Secure SSH' >/dev/null 2>&1
    ufw allow 443/tcp comment 'VLESS Reality/XHTTP' >/dev/null 2>&1
    ufw allow 6443/tcp comment 'VLESS Reality/XHTTP' >/dev/null 2>&1
    
    # Если панель на другом порту, открываем и его
    ufw allow 2222/tcp comment 'Remna Panel' >/dev/null 2>&1
    
    ufw --force enable >/dev/null 2>&1
    echo -e "${GREEN}[+] UFW успешно инициализирован. Сброс к лимитам 150/80 выполнен.${NC}"
    pause
}

install_all() {
    install_sysctl
    install_ufw
    install_fail2ban 
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
