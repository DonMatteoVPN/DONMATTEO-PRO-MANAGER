#!/bin/bash

install_kernel_protection() {
    echo -e "${CYAN}[*] Настройка защиты ядра (Sysctl)...${NC}"
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
    sysctl --system > /dev/null 2>&1
    echo -e "${GREEN}[+] Защита ядра активирована.${NC}"
}

install_menu() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🛠️  УСТАНОВКА И ИНИЦИАЛИЗАЦИЯ${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${GREEN}1.${NC} 🚀 Установить ВСЁ сразу (Sysctl + UFW + Fail2Ban)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e " ${YELLOW}2.${NC} Только защита ядра (Sysctl) ${NC}$(get_sysctl_status)"
        echo -e " ${YELLOW}3.${NC} Только инициализация UFW    ${NC}$(get_ufw_status)"
        echo -e " ${YELLOW}4.${NC} Только установка Fail2Ban   ${NC}$(get_f2b_status)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " inst_choice

        case $inst_choice in
            1) install_kernel_protection; ufw_global_setup; install_fail2ban; pause ;;
            2) install_kernel_protection; pause ;;
            3) ufw_global_setup; pause ;;
            4) install_fail2ban; pause ;;
            0) return ;;
        esac
    done
}