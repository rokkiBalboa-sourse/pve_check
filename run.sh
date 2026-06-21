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

# Сюда пользователь вставит свою ссылку на Яндекс.Диск
YANDEX_DISK_PUBLIC_LINK="https://disk.yandex.ru/d/Gf4LTZlkn58KXA"

# Функция отрисовки прогресс-бара
show_progress() {
    local current="$1"
    local total="$2"
    local percent=$(( current * 100 / total ))
    local bar_width=40
    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}#"; done
    for ((i=0; i<empty; i++)); do bar="${bar}-"; done
    
    printf "\r    [\033[0;32m%s\033[0m] %d%% (%d/%d)" "$bar" "$percent" "$current" "$total"
}

clear
echo -e "\033[0;36m╔══════════════════════════════════════════════════╗\033[0m"
echo -e "\033[0;36m║                                                  ║\033[0m"
echo -e "\033[0;36m║\033[1;33m             DEMOEXAM-CHECKER v1.2                \033[0;36m║\033[0m"
echo -e "\033[0;36m║\033[0;34m            Загрузка и обновление                 \033[0;36m║\033[0m"
echo -e "\033[0;36m║                                                  ║\033[0m"
echo -e "\033[0;36m╚══════════════════════════════════════════════════╝\033[0m"
echo ""

# Выбор источника загрузки
echo -e "\033[1;33mВыберите источник загрузки скриптов:\033[0m"
echo -e "  \033[0;32m1)\033[0m GitHub (основной)"
echo -e "  \033[0;32m2)\033[0m Yandex.Disk (зеркало)"
echo ""

choice=""
# Пытаемся прочитать с таймаутом 30 секунд.
if [ -t 0 ]; then
    read -t 30 -r -p "Ваш выбор [1-2] (по умолчанию 1, автовыбор через 30 сек): " choice
else
    if read -t 30 -r choice < /dev/tty 2>/dev/null; then
        :
    else
        choice="1"
        echo -e "\033[0;36m[+] Терминал не интерактивен. Источник: GitHub\033[0m"
    fi
fi

# Значение по умолчанию
choice=$(echo "$choice" | xargs)
if [[ "$choice" != "2" ]]; then
    choice="1"
fi

if [[ "$choice" == "1" ]]; then
    echo -e "\n\033[0;32m[+] Выбран источник: GitHub. Подготовка...\033[0m"
    
    # Проверяем наличие git
    if command -v git &> /dev/null; then
        if [ -d "$TARGET_DIR/.git" ]; then
            echo -e "\033[0;32m[+] Обновление существующего репозитория в $TARGET_DIR...\033[0m"
            cd "$TARGET_DIR" || exit 1
            git reset --hard &>/dev/null
            git pull || {
                echo -e "\033[1;33m[!] Ошибка обновления через git pull. Пересоздаем репозиторий...\033[0m"
                rm -rf "$TARGET_DIR"
                git clone "$REPO_URL" "$TARGET_DIR"
            }
        else
            echo -e "\033[0;32m[+] Клонирование репозитория в $TARGET_DIR...\033[0m"
            rm -rf "$TARGET_DIR"
            git clone "$REPO_URL" "$TARGET_DIR"
        fi
    else
        echo -e "\033[1;33m[!] Git не установлен. Скачивание файлов через curl\033[0m"
        
        files=(
            "menu.sh"
            "v1/module1_check.sh"
            "v1/module2_check.sh"
            "v1/module3_check.sh"
            "v2/module1_check.sh"
            "v2/module2_check.sh"
            "v2/module3_check.sh"
            "v3/module1_check.sh"
            "v3/module2_check.sh"
            "v3/module3_check.sh"
            "v4/module1_check.sh"
            "v4/module2_check.sh"
            "v4/module3_check.sh"
        )
        
        total=${#files[@]}
        current=0
        echo -e "\033[0;36m[+] Загрузка файлов...\033[0m"
        show_progress 0 $total
        
        for file in "${files[@]}"; do
            mkdir -p "$(dirname "$TARGET_DIR/$file")"
            curl -sSL "$RAW_URL/$file" -o "$TARGET_DIR/$file" || {
                echo -e "\n\033[0;31m✖ Ошибка скачивания файла $file\033[0m"
                exit 1
            }
            current=$((current + 1))
            show_progress $current $total
        done
        echo ""
    fi
else
    echo -e "\n\033[0;32m[+] Выбран источник: Yandex.Disk. Подготовка...\033[0m"
    
    if [[ "$YANDEX_DISK_PUBLIC_LINK" == "<YOUR_YANDEX_DISK_PUBLIC_LINK>" || -z "$YANDEX_DISK_PUBLIC_LINK" ]]; then
        echo -e "\033[0;31m✖ Ошибка: Публичная ссылка на Яндекс.Диск не настроена в скрипте run.sh!\033[0m"
        echo -e "Пожалуйста, пропишите рабочую ссылку в переменную YANDEX_DISK_PUBLIC_LINK."
        exit 1
    fi
    
    echo -e "\033[0;36m[+] Получение ссылки на скачивание с Yandex.Disk...\033[0m"
    api_response=$(curl -s "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=$YANDEX_DISK_PUBLIC_LINK")
    download_url=$(echo "$api_response" | sed -n 's/.*"href":"\([^"]*\)".*/\1/p')
    
    if [[ -z "$download_url" ]]; then
        echo -e "\033[0;31m✖ Ошибка: Не удалось получить ссылку от API Яндекс.Диска.\033[0m"
        echo -e "Ответ сервера: $api_response"
        exit 1
    fi
    
    echo -e "\033[0;32m[+] Ссылка получена. Скачивание архива...\033[0m"
    mkdir -p "$TARGET_DIR"
    curl -L --progress-bar "$download_url" -o "/tmp/pve_check.zip" || {
        echo -e "\033[0;31m✖ Ошибка скачивания архива с Yandex.Disk\033[0m"
        exit 1
    }
    
    echo -e "\033[0;36m[+] Распаковка архива через Python 3...\033[0m"
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/pve_check.zip').extractall('$TARGET_DIR')" || {
        echo -e "\033[0;31m✖ Ошибка распаковки архива\033[0m"
        exit 1
    }
    
    rm -f "/tmp/pve_check.zip"
fi

# Делаем скрипты исполняемыми
chmod +x "$TARGET_DIR/menu.sh"
chmod +x "$TARGET_DIR"/v*/*.sh 2>/dev/null || true

echo -e "\033[0;32m[+] Успешно настроено. Запуск главного меню...\033[0m"
echo ""
sleep 1

# Запуск меню
bash "$TARGET_DIR/menu.sh"
