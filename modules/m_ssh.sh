#!/bin/bash

ssh_add_port() {
    clear; echo -e "${MAGENTA}=== ДОБАВИТЬ SSH ПОРТ ===${NC}"
    echo -e "Текущие порты:"; grep -i "^Port" /etc/ssh/sshd_config || echo "Port 22 (по умолчанию)"
    read -p $'\nНовый порт (например 2727): ' newport; [[ -z "$newport" ]] && return
    
    if [[ "$newport" =~ ^[0-9]+$ ]]; then
        ! grep -qi "^Port" /etc/ssh/sshd_config && echo "Port 22" >> /etc/ssh/sshd_config
        if grep -qi "^Port $newport$" /etc/ssh/sshd_config; then echo -e "${YELLOW}Уже прописан!${NC}"; else
            echo "Port $newport" >> /etc/ssh/sshd_config
            ufw allow $newport/tcp comment 'Secure SSH' > /dev/null 2>&1
            systemctl restart sshd; install_fail2ban >/dev/null 2>&1; ufw_global_setup >/dev/null 2>&1
            echo -e "${GREEN}Порт успешно добавлен, открыт в UFW и защищен!${NC}"
        fi
    fi
    pause
}

ssh_del_port() {
    while true; do
        clear; echo -e "${MAGENTA}=== УДАЛИТЬ SSH ПОРТ ===${NC}"
        mapfile -t SSH_PORTS < <(grep -i "^Port" /etc/ssh/sshd_config)
        [[ ${#SSH_PORTS[@]} -eq 0 ]] && { echo -e "${YELLOW}Нестандартных портов нет.${NC}"; pause; return; }
        
        local i=1; for p in "${SSH_PORTS[@]}"; do echo -e "  ${YELLOW}[$i]${NC} $p"; ((i++)); done
        read -p $'\nНОМЕР для удаления (0 - Назад): ' num; [[ "$num" == "0" || -z "$num" ]] && return
        
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -le "$i" ] && [ "$num" -gt 0 ]; then
            sed -i "/^${SSH_PORTS[$((num-1))]}$/d" /etc/ssh/sshd_config
            systemctl restart sshd; install_fail2ban >/dev/null 2>&1; ufw_global_setup >/dev/null 2>&1
            echo -e "${GREEN}Порт успешно удален.${NC}"; sleep 1
        fi
    done
}

menu_ssh() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🔑 УПРАВЛЕНИЕ SSH СЕРВЕРОМ${NC}"
        echo -e "${GRAY} Настройка портов для безопасного входа по SSH.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} ➕ Добавить новый порт SSH"
        echo -e "    ${GRAY}└─ Смена порта защитит от ботов-брутфорсеров.${NC}"
        echo -e " ${YELLOW}2.${NC} ➖ Удалить старый порт SSH"
        echo -e "    ${GRAY}└─ Убирает порт из конфигурации, если он не нужен.${NC}"
        echo -e " ${YELLOW}3.${NC} 🔄 Принудительный рестарт службы sshd"
        echo -e "    ${GRAY}└─ Применяет зависшие настройки SSH.${NC}"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) ssh_add_port ;; 2) ssh_del_port ;; 3) systemctl restart sshd; echo -e "${GREEN}Успешно перезапущено.${NC}"; sleep 1 ;; 0) return ;;
        esac
    done
}
