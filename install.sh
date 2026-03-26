#!/bin/bash
# Скрипт установки DONMATTEO PRO MANAGER

# ⚠️ ЗАМЕНИ НА ССЫЛКУ НА СВОЙ RAW GITHUB:
REPO_URL="https://raw.githubusercontent.com/ТВОЙ_НИК/donmatteo-manager/main"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Запустите установку от имени root (sudo).${NC}"
    exit 1
fi

echo -e "${CYAN}[*] Подготовка директорий...${NC}"
mkdir -p /opt/remnawave/modules

echo -e "${CYAN}[*] Скачивание главного ядра (don)...${NC}"
curl -sL "${REPO_URL}/don" -o /usr/local/bin/don
chmod +x /usr/local/bin/don

echo -e "${CYAN}[*] Скачивание модулей...${NC}"
MODULES=("m_ufw.sh" "m_ssh.sh" "m_f2b.sh" "m_tg.sh" "m_swap.sh" "m_cleaner.sh" "m_installer.sh")

for mod in "${MODULES[@]}"; do
    curl -sL "${REPO_URL}/modules/${mod}" -o "/opt/remnawave/modules/${mod}"
done

clear
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}${BOLD} 🚀 УСТАНОВКА DONMATTEO MANAGER УСПЕШНО ЗАВЕРШЕНА!${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW} Теперь вы можете управлять защитой и сервером из любого места.${NC}"
echo -e "${YELLOW} Вам больше не нужно искать пути к скриптам или писать bash.${NC}\n"
echo -e "${W} 👉 Просто введите в консоль команду:${NC} ${GREEN}${BOLD}don${NC}"
echo -e "${CYAN}================================================================${NC}"