#!/bin/bash

# ============================================================
# DEMOEXAM-CHECKER v1.2 - Выбор варианта и главное меню
# ============================================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

# Переменные для выбранного варианта
CURRENT_VARIANT=""
SCRIPT_DIR=""
# Получаем директорию, в которой находится сам menu.sh
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Отслеживание запущенного в текущей сессии модуля
CURRENT_ACTIVE_MODULE=""

# Массивы ВМ для каждого модуля
declare -a MODULE1_VMS=("10101" "10102" "10103" "10104" "10105" "10106")
declare -a MODULE2_VMS=("10201" "10202" "10203" "10204" "10205" "10206")
declare -a MODULE3_VMS=("10301" "10302" "10303" "10304" "10305" "10306")

# Функция подготовки (запуска) ВМ для выбранного модуля
prepare_module_vms() {
    local module_num="$1"
    local -a vms
    case $module_num in
        1) vms=("${MODULE1_VMS[@]}") ;;
        2) vms=("${MODULE2_VMS[@]}") ;;
        3) vms=("${MODULE3_VMS[@]}") ;;
        *) return 1 ;;
    esac

    # Проверяем, существует ли утилита qm (чтобы скрипт не падал на обычной системе без PVE)
    if ! command -v qm &> /dev/null; then
        echo -e "${YELLOW}  [!] Утилита qm не найдена. Пропуск управления питанием ВМ.${NC}"
        return 0
    fi

    echo ""
    echo -e "${BLUE}  ▸ Проверка состояния виртуальных машин Модуля ${module_num}...${NC}"

    local started_any=false
    for vmid in "${vms[@]}"; do
        local status
        status=$(qm status "$vmid" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}  ✖ ВМ с ID ${vmid} не найдена в Proxmox!${NC}"
            continue
        fi

        if echo "$status" | grep -q "status: stopped"; then
            echo -e "${YELLOW}  ▸ ВМ ${vmid} выключена. Запуск...${NC}"
            qm start "$vmid" &>/dev/null
            started_any=true
        else
            echo -e "${GREEN}  ✔ ВМ ${vmid} уже запущена.${NC}"
        fi
    done

    # Если была запущена хотя бы одна ВМ, ждем 30 секунд
    if [[ "$started_any" == true ]]; then
        local timeout=30
        echo -e "${YELLOW}  ⌛ Ожидание ${timeout} сек. для загрузки систем и запуска QEMU Agent...${NC}"
        for ((i=timeout; i>0; i--)); do
            printf "\r    Осталось %2d сек... " "$i"
            sleep 1
        done
        echo -e "\n${GREEN}  ✔ Виртуальные машины запущены и готовы к проверке.${NC}"
    else
        echo -e "${GREEN}  ✔ Все ВМ модуля уже запущены. Ожидание не требуется.${NC}"
    fi
    echo ""
}

# Функция остановки всех ВМ для выбранного модуля
stop_module_vms() {
    local module_num="$1"
    local -a vms
    case $module_num in
        1) vms=("${MODULE1_VMS[@]}") ;;
        2) vms=("${MODULE2_VMS[@]}") ;;
        3) vms=("${MODULE3_VMS[@]}") ;;
        *) return 1 ;;
    esac

    if ! command -v qm &> /dev/null; then
        return 0
    fi

    echo ""
    echo -e "${BLUE}  ▸ Остановка виртуальных машин Модуля ${module_num}...${NC}"

    for vmid in "${vms[@]}"; do
        local status
        status=$(qm status "$vmid" 2>/dev/null)
        if [[ $? -eq 0 ]] && echo "$status" | grep -q "status: running"; then
            echo -e "${YELLOW}  ▸ Останавливаем ВМ ${vmid}...${NC}"
            qm stop "$vmid" &>/dev/null
        fi
    done
    echo -e "${GREEN}  ✔ Все ВМ Модуля ${module_num} остановлены.${NC}"
    echo ""
}


# Функция выбора варианта
choose_variant() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                  ║${NC}"
    echo -e "${CYAN}║${YELLOW}             DEMOEXAM-CHECKER v1.2                ${CYAN}║${NC}"
    echo -e "${CYAN}║${BLUE}            Выбор варианта проверки               ${CYAN}║${NC}"
    echo -e "${CYAN}║                                                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}  Выберите вариант:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} ${YELLOW}Вариант 1${NC}"
    echo -e "  ${GREEN}2)${NC} ${YELLOW}Вариант 2${NC}"
    echo -e "  ${GREEN}3)${NC} ${YELLOW}Вариант 3${NC}"
    echo -e "  ${GREEN}4)${NC} ${YELLOW}Вариант 4${NC}"
    echo ""
    echo -e "  ${RED}0)${NC} ${YELLOW}Выход${NC}"
    echo ""
    
    while true; do
        echo -ne "${YELLOW}  Ваш выбор [0-4]: ${NC}"
        read -r choice
        case $choice in
            1|2|3|4)
                CURRENT_VARIANT=$choice
                # Устанавливаем SCRIPT_DIR в зависимости от варианта
                case $choice in
                    1) SCRIPT_DIR="$SCRIPT_PATH/v1" ;;
                    2) SCRIPT_DIR="$SCRIPT_PATH/v2" ;;
                    3) SCRIPT_DIR="$SCRIPT_PATH/v3" ;;
                    4) SCRIPT_DIR="$SCRIPT_PATH/v4" ;;
                esac
                return 0
                ;;
            0)
                echo ""
                echo -e "${CYAN}  До свидания!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}  Неверный выбор: ${choice}${NC}"
                echo -e "${YELLOW}  Пожалуйста, выберите число от 0 до 4${NC}"
                ;;
        esac
    done
}

# Функция отрисовки карточки модуля
show_module_card() {
    local num="$1"
    local title="$2"
    local desc="$3"
    local vms="$4"
    local report="$5"
    local status="$6"
    
    if [[ "$status" == "ready" ]]; then
        echo -e "  ${GREEN}${num})${NC} ${YELLOW}${title}${NC} — ${desc}"
    else
        echo -e "  ${RED}${num})${NC} ${YELLOW}${title}${NC} — ${RED}${desc}${NC}"
    fi
    
    printf "  ${MAGENTA}%-66s${NC}\n" "├─ Целевые ВМ: ${vms}"
    printf "  ${MAGENTA}%-66s${NC}\n" "└─ Отчет: ${report}"
    echo ""
}

# Функция запуска проверки модуля
run_module_check() {
    local module_num="$1"
    local module_script="$2"
    
    echo ""
    echo -e "${GREEN}  ▶ Запуск проверки Модуля ${module_num}...${NC}"
    echo ""
    
    if [[ -f "$module_script" ]]; then
        # Если ранее в этой сессии проверялся другой модуль, выключаем его машины
        if [[ -n "$CURRENT_ACTIVE_MODULE" && "$CURRENT_ACTIVE_MODULE" != "$module_num" ]]; then
            echo -e "${YELLOW}  [!] Обнаружена смена модуля. Выключаем машины предыдущего Модуля ${CURRENT_ACTIVE_MODULE}...${NC}"
            stop_module_vms "$CURRENT_ACTIVE_MODULE"
        fi
        
        prepare_module_vms "$module_num"
        CURRENT_ACTIVE_MODULE="$module_num"
        
        bash "$module_script"
        local exit_code=$?
        echo ""
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}  ✔ Проверка Модуля ${module_num} завершена!${NC}"
            return 0
        else
            echo -e "${RED}  ✖ Проверка Модуля ${module_num} завершилась с ошибкой (код: ${exit_code})${NC}"
            return 1
        fi
    else
        echo -e "${RED}  ✖ Ошибка: скрипт ${module_script} не найден!${NC}"
        echo -e "${YELLOW}    Убедитесь, что файл существует.${NC}"
        return 1
    fi
}

# Функция отображения главного меню (с информацией о варианте)
show_menu() {
    clear
    
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                  ║${NC}"
    echo -e "${CYAN}║${YELLOW}              DEMOEXAM-CHECKER v1.2               ${CYAN}║${NC}"
    echo -e "${CYAN}║${BLUE}     Авто-проверка демонстрационного экзамена     ${CYAN}║${NC}"
    echo -e "${CYAN}║${BLUE}                СиСА 09.02.06                     ${CYAN}║${NC}"
    echo -e "${CYAN}║                                                  ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${MAGENTA}  Текущий вариант: ${YELLOW}${CURRENT_VARIANT}${CYAN}                              ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║                                                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}  Выберите модуль для проверки:${NC}"
    echo ""
    
    # Определяем пути к скриптам (глобальные переменные)
    local MODULE1_SCRIPT="${SCRIPT_DIR}/module1_check.sh"
    local MODULE2_SCRIPT="${SCRIPT_DIR}/module2_check.sh"
    local MODULE3_SCRIPT="${SCRIPT_DIR}/module3_check.sh"
    
    # Проверяем готовность модулей
    local MODULE1_READY=false
    local MODULE2_READY=false
    local MODULE3_READY=false
    
    [[ -f "$MODULE1_SCRIPT" ]] && MODULE1_READY=true
    [[ -f "$MODULE2_SCRIPT" ]] && MODULE2_READY=true
    [[ -f "$MODULE3_SCRIPT" ]] && MODULE3_READY=true
    
    show_module_card \
        "1" \
        "Модуль 1" \
        "Базовая настройка сети и сервисов" \
        "ISP(10101), HQ-RTR(10102), HQ-SRV(10103), HQ-CLI(10104), BR-RTR(10105), BR-SRV(10106)" \
        "/root/pve_reports/Module1_Report_*.txt" \
        $( [[ "$MODULE1_READY" == true ]] && echo "ready" || echo "not_ready" )
    
    show_module_card \
        "2" \
        "Модуль 2" \
        "Samba DC, RAID, NFS, Docker, LAMP, Nginx" \
        "ISP(10201), HQ-RTR(10202), HQ-SRV(10203), HQ-CLI(10204), BR-RTR(10205), BR-SRV(10206)" \
        "/root/pve_reports/Module2_Report_*.txt" \
        $( [[ "$MODULE2_READY" == true ]] && echo "ready" || echo "not_ready" )
    
    show_module_card \
        "3" \
        "Модуль 3" \
        "ГОСТ шифрование, OpenVPN, мониторинг, бэкапы" \
        "ISP(10301), HQ-RTR(10302), HQ-SRV(10303), HQ-CLI(10304), BR-RTR(10305), BR-SRV(10306)" \
        "/root/pve_reports/Module3_Report_*.txt" \
        $( [[ "$MODULE3_READY" == true ]] && echo "ready" || echo "not_ready" )
    
    echo -e "  ${GREEN}4)${NC} ${YELLOW}Проверить ВСЕ модули последовательно${NC}"
    echo ""
    
    echo -e "  ${RED}0)${NC} ${YELLOW}Выход${NC}"
    echo ""
}

# Главное меню (основной цикл)
main_menu() {
    while true; do
        show_menu
        
        echo -ne "${YELLOW}  Ваш выбор [0-4]: ${NC}"
        read -r choice
        
        local MODULE1_SCRIPT="${SCRIPT_DIR}/module1_check.sh"
        local MODULE2_SCRIPT="${SCRIPT_DIR}/module2_check.sh"
        local MODULE3_SCRIPT="${SCRIPT_DIR}/module3_check.sh"
        
        case $choice in
            1)
                if [[ -f "$MODULE1_SCRIPT" ]]; then
                    run_module_check "1" "$MODULE1_SCRIPT"
                else
                    echo ""
                    echo -e "${RED}  ✖ Скрипт Модуля 1 не найден!${NC}"
                    echo -e "${YELLOW}    Ожидаемый путь: ${MODULE1_SCRIPT}${NC}"
                fi
                ;;
            2)
                if [[ -f "$MODULE2_SCRIPT" ]]; then
                    run_module_check "2" "$MODULE2_SCRIPT"
                else
                    echo ""
                    echo -e "${RED}  ✖ Скрипт Модуля 2 не найден!${NC}"
                    echo -e "${YELLOW}    Ожидаемый путь: ${MODULE2_SCRIPT}${NC}"
                fi
                ;;
            3)
                if [[ -f "$MODULE3_SCRIPT" ]]; then
                    run_module_check "3" "$MODULE3_SCRIPT"
                else
                    echo ""
                    echo -e "${RED}  ✖ Скрипт Модуля 3 не найден!${NC}"
                    echo -e "${YELLOW}    Ожидаемый путь: ${MODULE3_SCRIPT}${NC}"
                fi
                ;;
            4)
                echo ""
                echo -e "${GREEN}  ▶ Запуск последовательной проверки ВСЕХ модулей...${NC}"
                echo ""
                
                # Если ранее в этой сессии проверялся одиночный модуль, тушим его
                if [[ -n "$CURRENT_ACTIVE_MODULE" ]]; then
                    echo -e "${YELLOW}  [!] Обнаружен запуск всех модулей. Выключаем машины предыдущего Модуля ${CURRENT_ACTIVE_MODULE}...${NC}"
                    stop_module_vms "$CURRENT_ACTIVE_MODULE"
                    CURRENT_ACTIVE_MODULE=""
                fi

                MODULES_OK=0
                MODULES_FAIL=0
                MODULES_TOTAL=0
                
                # Модуль 1
                echo -e "${BLUE}  ▸ [1/3] Проверка Модуля 1...${NC}"
                MODULES_TOTAL=$((MODULES_TOTAL + 1))
                if [[ -f "$MODULE1_SCRIPT" ]]; then
                    prepare_module_vms "1"
                    bash "$MODULE1_SCRIPT"
                    local exit_code=$?
                    stop_module_vms "1"
                    if [[ $exit_code -eq 0 ]]; then
                        echo -e "${GREEN}  ✔ Модуль 1 завершен${NC}"
                        MODULES_OK=$((MODULES_OK + 1))
                    else
                        echo -e "${RED}  ✖ Модуль 1 завершился с ошибкой${NC}"
                        MODULES_FAIL=$((MODULES_FAIL + 1))
                    fi
                else
                    echo -e "${RED}  ✖ Скрипт Модуля 1 не найден: ${MODULE1_SCRIPT}${NC}"
                    MODULES_FAIL=$((MODULES_FAIL + 1))
                fi
                echo ""
                
                # Модуль 2
                echo -e "${BLUE}  ▸ [2/3] Проверка Модуля 2...${NC}"
                MODULES_TOTAL=$((MODULES_TOTAL + 1))
                if [[ -f "$MODULE2_SCRIPT" ]]; then
                    prepare_module_vms "2"
                    bash "$MODULE2_SCRIPT"
                    local exit_code=$?
                    stop_module_vms "2"
                    if [[ $exit_code -eq 0 ]]; then
                        echo -e "${GREEN}  ✔ Модуль 2 завершен${NC}"
                        MODULES_OK=$((MODULES_OK + 1))
                    else
                        echo -e "${RED}  ✖ Модуль 2 завершился с ошибкой${NC}"
                        MODULES_FAIL=$((MODULES_FAIL + 1))
                    fi
                else
                    echo -e "${RED}  ✖ Скрипт Модуля 2 не найден: ${MODULE2_SCRIPT}${NC}"
                    MODULES_FAIL=$((MODULES_FAIL + 1))
                fi
                echo ""
                
                # Модуль 3
                echo -e "${BLUE}  ▸ [3/3] Проверка Модуля 3...${NC}"
                MODULES_TOTAL=$((MODULES_TOTAL + 1))
                if [[ -f "$MODULE3_SCRIPT" ]]; then
                    prepare_module_vms "3"
                    bash "$MODULE3_SCRIPT"
                    local exit_code=$?
                    stop_module_vms "3"
                    if [[ $exit_code -eq 0 ]]; then
                        echo -e "${GREEN}  ✔ Модуль 3 завершен${NC}"
                        MODULES_OK=$((MODULES_OK + 1))
                    else
                        echo -e "${RED}  ✖ Модуль 3 завершился с ошибкой${NC}"
                        MODULES_FAIL=$((MODULES_FAIL + 1))
                    fi
                else
                    echo -e "${RED}  ✖ Скрипт Модуля 3 не найден: ${MODULE3_SCRIPT}${NC}"
                    MODULES_FAIL=$((MODULES_FAIL + 1))
                fi
                echo ""
                
                # Итог
                echo -e "${CYAN}  ══════════════════════════════════════════${NC}"
                echo -e "${CYAN}  Результат проверки всех модулей:${NC}"
                echo -e "${GREEN}  ✔ Успешно проверено: ${MODULES_OK}/${MODULES_TOTAL}${NC}"
                if [[ $MODULES_FAIL -gt 0 ]]; then
                    echo -e "${RED}  ✖ С ошибками: ${MODULES_FAIL}/${MODULES_TOTAL}${NC}"
                    echo -e "${YELLOW}  Проверьте наличие скриптов:${NC}"
                    [[ ! -f "$MODULE1_SCRIPT" ]] && echo -e "${RED}     - ${MODULE1_SCRIPT}${NC}"
                    [[ ! -f "$MODULE2_SCRIPT" ]] && echo -e "${RED}     - ${MODULE2_SCRIPT}${NC}"
                    [[ ! -f "$MODULE3_SCRIPT" ]] && echo -e "${RED}     - ${MODULE3_SCRIPT}${NC}"
                fi
                
                if [[ $MODULES_FAIL -eq 0 ]]; then
                    echo ""
                    echo -e "${GREEN}  ✔ Все модули успешно проверены!${NC}"
                    echo -e "${CYAN}  Отчеты сохранены в /root/pve_reports/${NC}"
                fi
                echo -e "${CYAN}  ══════════════════════════════════════════${NC}"
                ;;
            0)
                echo ""
                echo -e "${CYAN}  До свидания!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo ""
                echo -e "${RED}  Неверный выбор: ${choice}${NC}"
                echo -e "${YELLOW}  Пожалуйста, выберите число от 0 до 4${NC}"
                ;;
        esac
        
        # Пауза перед возвратом в меню (кроме выхода)
        if [[ "$choice" != "0" ]]; then
            echo ""
            echo -ne "${CYAN}  Нажмите ENTER чтобы продолжить...${NC}"
            read -r
        fi
    done
}

# ============================================================
# Запуск
# ============================================================

# Сначала выбираем вариант
choose_variant

# Затем запускаем основное меню с выбранным SCRIPT_DIR
main_menu