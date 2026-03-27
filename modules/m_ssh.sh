#!/bin/bash

# Функция для получения списка всех активных портов SSH
get_active_ssh_ports() {
    local ports=$(grep -i "^Port " /etc/ssh/sshd_config | awk '{print $2}' | xargs)
    [[ -z "$ports" ]] && echo "22" || echo "$ports"
}

ssh_add_port() {
    clear; echo -e "${MAGENTA}=== ДОБАВИТЬ SSH ПОРТ ===${NC}"
    local current_ports=$(get_active_ssh_ports)
    echo -e "Текущие активные порты: ${CYAN}${current_ports}${NC}"
    
    read -p $'\nВведите новый порт (1-65535): ' newport
    [[ -z "$newport" ]] && return

    # 1. Проверка: является ли ввод числом и входит ли в диапазон
    if ! [[ "$newport" =~ ^[0-9]+$ ]] || [ "$newport" -lt 1 ] || [ "$newport" -gt 65535 ]; then
        echo -e "${RED}Ошибка: Недопустимый порт!${NC}"; pause; return
    fi

    # 2. Проверка на дубликат
    if grep -qi "^Port $newport$" /etc/ssh/sshd_config; then
        echo -e "${YELLOW}Порт $newport уже прописан в конфигурации!${NC}"; pause; return
    fi

    # 3. Безопасность: Если файл пустой (без слова Port), SSH работает на 22.
    # Чтобы не потерять доступ, принудительно прописываем текущий 22 порт перед добавлением нового.
    if ! grep -qi "^Port " /etc/ssh/sshd_config; then
        echo "Port 22" >> /etc/ssh/sshd_config
    fi

    # 4. Добавление порта
    echo "Port $newport" >> /etc/ssh/sshd_config
    
    # 5. Применение настроек
    echo -e "${CYAN}[*] Перезапуск SSH и обновление защиты...${NC}"
    systemctl restart sshd
    
    # Автоматически открываем порт в UFW и обновляем Fail2Ban
    ufw allow "$newport"/tcp comment 'Secure SSH' > /dev/null 2>&1
    install_fail2ban >/dev/null 2>&1
    ufw_global_setup >/dev/null 2>&1
    
    echo -e "${GREEN}Порт $newport успешно добавлен и защищен!${NC}"
    pause
}

ssh_del_port() {
    while true; do
        clear; echo -e "${MAGENTA}=== УДАЛИТЬ SSH ПОРТ ===${NC}"
        # Получаем массив портов
        mapfile -t SSH_PORTS < <(grep -i "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        
        if [[ ${#SSH_PORTS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}В конфиге нет явно прописанных портов (используется стандартный 22).${NC}"
            echo -e "${RED}Удаление невозможно, иначе вы потеряете доступ!${NC}"
            pause; return
        fi

        # Защита: нельзя удалить единственный порт
        if [[ ${#SSH_PORTS[@]} -eq 1 ]]; then
            echo -e "${RED}ВНИМАНИЕ: Это ваш единственный порт (${SSH_PORTS[0]}).${NC}"
            echo -e "${RED}Удаление последнего порта приведет к потере доступа к серверу!${NC}"
            pause; return
        fi
        
        local i=1; for p in "${SSH_PORTS[@]}"; do echo -e "  ${YELLOW}[$i]${NC} Port $p"; ((i++)); done
        read -p $'\nНОМЕР для удаления (0 - Назад): ' num; [[ "$num" == "0" || -z "$num" ]] && return
        
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -lt "$i" ] && [ "$num" -gt 0 ]; then
            local port_to_del="${SSH_PORTS[$((num-1))]}"
            
            # Удаляем строку из конфига
            sed -i "/^Port $port_to_del$/d" /etc/ssh/sshd_config
            
            # Закрываем порт в UFW
            ufw delete allow "$port_to_del"/tcp > /dev/null 2>&1
            
            systemctl restart sshd
            install_fail2ban >/dev/null 2>&1
            ufw_global_setup >/dev/null 2>&1
            
            echo -e "${GREEN}Порт $port_to_del успешно удален.${NC}"; sleep 1
        else
            echo -e "${RED}Неверный номер!${NC}"; sleep 1
        fi
    done
}

menu_ssh() {
    while true; do
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${BOLD}${MAGENTA}  🔑 УПРАВЛЕНИЕ SSH СЕРВЕРОМ${NC}"
        echo -e " Статус: $(systemctl is-active sshd || echo "error")"
        echo -e " Активные порты: $(get_active_ssh_ports)"
        echo -e "${BLUE}======================================================${NC}"
        echo -e " ${YELLOW}1.${NC} ➕ Добавить новый порт SSH"
        echo -e " ${YELLOW}2.${NC} ➖ Удалить старый порт SSH"
        echo -e " ${YELLOW}3.${NC} 🔄 Принудительный рестарт службы"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        read -p ">> " choice
        case $choice in
            1) ssh_add_port ;; 2) ssh_del_port ;; 3) systemctl restart sshd; echo -e "${GREEN}Перезапущено.${NC}"; sleep 1 ;; 0) return ;;
        esac
    done
}
