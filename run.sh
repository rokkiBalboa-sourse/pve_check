#!/bin/bash

# ============================================================
# DEMOEXAM-CHECKER - Bootstrap & Updater
# ============================================================

# Проверка прав суперпользователя (root)
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[0;31mОшибка: Скрипт должен быть запущен от имени root (sudo)!\033[0m"
  exit 1
fi

REPO_URL="https://github.com/rokkiBalboa-sourse/pve_check.git"
RAW_URL="https://raw.githubusercontent.com/rokkiBalboa-sourse/pve_check/main"
TARGET_DIR="/root/pve_checks"
SCRIPT_DIR="$TARGET_DIR/pve_checks"

echo -e "\033[0;36m[+] Подготовка DEMOEXAM-CHECKER...\033[0m"

# Проверяем наличие git
if command -v git &> /dev/null; then
    if [ -d "$TARGET_DIR/.git" ]; then
        echo -e "\033[0;32m[+] Обновление существующего репозитория в $TARGET_DIR...\033[0m"
        cd "$TARGET_DIR" || exit 1
        # Сбросим локальные изменения, если они были, чтобы git pull прошел успешно
        git reset --hard &>/dev/null
        git pull || {
            echo -e "\033[1;33m[!] Ошибка обновления через git pull. Попробуем пересоздать репозиторий...\033[0m"
            rm -rf "$TARGET_DIR"
            git clone "$REPO_URL" "$TARGET_DIR"
        }
    else
        echo -e "\033[0;32m[+] Клонирование репозитория в $TARGET_DIR...\033[0m"
        rm -rf "$TARGET_DIR"
        git clone "$REPO_URL" "$TARGET_DIR"
    fi
else
    echo -e "\033[1;33m[!] Git не установлен. Скачивание файлов через curl...\033[0m"
    
    # Список файлов для скачивания (пути относительно корня репозитория)
    files=(
        "pve_checks/menu.sh"
        "pve_checks/v1/module1_check.sh"
        "pve_checks/v1/module2_check.sh"
        "pve_checks/v1/module3_check.sh"
        "pve_checks/v2/module1_check.sh"
        "pve_checks/v2/module2_check.sh"
        "pve_checks/v2/module3_check.sh"
        "pve_checks/v3/module1_check.sh"
        "pve_checks/v3/module2_check.sh"
        "pve_checks/v3/module3_check.sh"
        "pve_checks/v4/module1_check.sh"
        "pve_checks/v4/module2_check.sh"
        "pve_checks/v4/module3_check.sh"
    )
    
    for file in "${files[@]}"; do
        echo "Скачивание $file..."
        mkdir -p "$(dirname "$TARGET_DIR/$file")"
        curl -sSL "$RAW_URL/$file" -o "$TARGET_DIR/$file" || {
            echo -e "\033[0;31m✖ Ошибка скачивания файла $file\033[0m"
            exit 1
        }
    done
fi

# Делаем скрипты исполняемыми
chmod +x "$SCRIPT_DIR/menu.sh"
chmod +x "$SCRIPT_DIR"/v*/*.sh 2>/dev/null || true

echo -e "\033[0;32m[+] Успешно настроено. Запуск главного меню...\033[0m"
echo ""
sleep 1

# Запуск меню
bash "$SCRIPT_DIR/menu.sh"
