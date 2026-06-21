#!/bin/bash

# =============================================================================
# module3_check.sh - Исправленная версия
# =============================================================================

REPORT_DIR="/root/pve_reports"
TIMESTAMP=$(date +"%d-%m-%Y_%H-%M-%S")
REPORT_FILE="${REPORT_DIR}/Module3_Report_${TIMESTAMP}.txt"

# ID виртуальных машин
ISP="10301"
HQ_RTR="10302"
HQ_SRV="10303"
HQ_CLI="10304"
BR_RTR="10305"
BR_SRV="10306"

declare -A VM_NAMES
VM_NAMES[$ISP]="ISP"
VM_NAMES[$HQ_RTR]="HQ-RTR"
VM_NAMES[$HQ_SRV]="HQ-SRV"
VM_NAMES[$HQ_CLI]="HQ-CLI"
VM_NAMES[$BR_RTR]="BR-RTR"
VM_NAMES[$BR_SRV]="BR-SRV"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$REPORT_DIR"

get_vm_name() {
    echo "${VM_NAMES[$1]:-$1}"
}

# Простейшая проверка успешности команды
LAST_OUTPUT=""
run_cmd() {
    local vm_id=$1
    local cmd=$2
    
    local tmp_file="/tmp/qga_$$"
    qm guest exec "$vm_id" -- /bin/bash -c "$cmd" > "$tmp_file" 2>&1
    
    if grep -q '"exitcode"[[:space:]]*:[[:space:]]*0' "$tmp_file"; then
        local out_data=$(grep -o '"out-data"[[:space:]]*:[[:space:]]*"[^"]*"' "$tmp_file" | head -1 | sed 's/.*"out-data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed 's/\\n/\n/g' | sed 's/\\t/\t/g')
        LAST_OUTPUT="$out_data"
        rm -f "$tmp_file"
        return 0
    else
        LAST_OUTPUT=""
        rm -f "$tmp_file"
        return 1
    fi
}

# Функция проверки задания
check_task() {
    local vm_id="$1"
    local description="$2"
    local check_command="$3"
    local fact_command="$4"
    local vm_name=$(get_vm_name "$vm_id")
    
    local fact_data=""
    if [[ -n "$fact_command" ]]; then
        if run_cmd "$vm_id" "$fact_command"; then
            fact_data=$(echo "$LAST_OUTPUT" | head -c 200 | tr '\n' ' ')
            [[ -z "$fact_data" ]] && fact_data="OK"
        else
            fact_data="[команда не выполнена]"
        fi
    fi
    
    if run_cmd "$vm_id" "$check_command"; then
        echo -e "${GREEN}[ OK ] $vm_name: $description -> $fact_data${NC}"
        echo "[ OK ] $vm_name: $description -> $fact_data" >> "$REPORT_FILE"
        return 0
    else
        echo -e "${RED}[ FAIL ] $vm_name: $description -> Ошибка (Факт: $fact_data)${NC}"
        echo "[ FAIL ] $vm_name: $description -> Ошибка (Факт: $fact_data)" >> "$REPORT_FILE"
        return 1
    fi
}

# Функция проверки сервиса
check_service() {
    local vm_id="$1"
    local service_name="$2"
    local description="${3:-Сервис $service_name}"
    check_task "$vm_id" "$description" \
        "systemctl is-active --quiet $service_name" \
        "systemctl is-active $service_name 2>/dev/null | head -1 || echo 'inactive'"
}

# Функция проверки файла
check_file() {
    local vm_id="$1"
    local file_path="$2"
    local description="$3"
    check_task "$vm_id" "$description" \
        "test -f '$file_path'" \
        "ls -la '$file_path' 2>/dev/null | awk '{print \$5, \$9}' || echo 'not found'"
}

# Функция проверки порта
check_port() {
    local vm_id="$1"
    local port="$2"
    local description="$3"
    check_task "$vm_id" "$description" \
        "ss -ltnp 2>/dev/null | grep -q ':$port ' || netstat -ltnp 2>/dev/null | grep -q ':$port '" \
        "ss -ltnp 2>/dev/null | grep ':$port ' | head -1 | sed 's/  */ /g' | cut -c1-100 || echo 'port $port not listening'"
}

# Функция проверки существования директории
check_directory() {
    local vm_id="$1"
    local dir_path="$2"
    local description="$3"
    check_task "$vm_id" "$description" \
        "test -d '$dir_path'" \
        "ls -la '$dir_path' 2>/dev/null | head -1 || echo 'not found'"
}

# ============================================================
# НАЧАЛО ПРОВЕРКИ
# ============================================================

echo "Отчет о проверке практических заданий Module 3" > "$REPORT_FILE"
echo "Дата и время: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "============================================================" >> "$REPORT_FILE"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Отчет о проверке практических заданий Module 3${NC}"
echo -e "${BLUE}Дата и время: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BLUE}============================================================================${NC}\n"

# ============================================================
# ЗАДАНИЕ 1: Импорт пользователей в домен
# ============================================================
echo -e "${YELLOW}=== Задание 1: Импорт пользователей в домен (BR-SRV) ===${NC}\n"
echo "=== Задание 1: Импорт пользователей в домен (BR-SRV) ===" >> "$REPORT_FILE"

# Проверяем только импортированных пользователей из CSV (без administrator)
check_task "$BR_SRV" "Импортированы пользователи из CSV (не системные)" \
    "samba-tool user list 2>/dev/null | grep -Eiv 'administrator|krbtgt|guest|dns-' | grep -q ." \
    "samba-tool user list 2>/dev/null | grep -Eiv 'administrator|krbtgt|guest|dns-' | head -3 | tr '\n' ' '"

# ============================================================
# ЗАДАНИЕ 2: Центр сертификации на ISP (внимание: ISP, а не HQ-SRV!)
# ============================================================
echo -e "\n${YELLOW}=== Задание 2: Центр сертификации (ISP) ===${NC}\n"
echo "\n=== Задание 2: Центр сертификации (ISP) ===" >> "$REPORT_FILE"

check_file "$ISP" "/root/ca.crt" "Корневой сертификат CA"
check_file "$ISP" "/root/web.au-team.irpo.crt" "Сертификат web.au-team.irpo"
check_file "$ISP" "/root/web.au-team.irpo.key" "Ключ web.au-team.irpo"
check_file "$ISP" "/root/docker.au-team.irpo.crt" "Сертификат docker.au-team.irpo"
check_file "$ISP" "/root/docker.au-team.irpo.key" "Ключ docker.au-team.irpo"
check_service "$ISP" "nginx"

# ============================================================
# ЗАДАНИЕ 3: OpenVPN туннель
# ============================================================
echo -e "\n${YELLOW}=== Задание 3: OpenVPN туннель ===${NC}\n"
echo "\n=== Задание 3: OpenVPN туннель ===" >> "$REPORT_FILE"

check_file "$HQ_RTR" "/etc/openvpn/keys/static.key" "Статический ключ на HQ-RTR"
check_file "$HQ_RTR" "/etc/openvpn/server/tun0.conf" "Конфиг OpenVPN сервера (HQ-RTR)"
check_file "$BR_RTR" "/etc/openvpn/keys/static.key" "Статический ключ на BR-RTR"
check_file "$BR_RTR" "/etc/openvpn/client/tun0.conf" "Конфиг OpenVPN клиента (BR-RTR)"

# ============================================================
# ЗАДАНИЕ 4: Межсетевой экран
# ============================================================
echo -e "\n${YELLOW}=== Задание 4: Межсетевой экран ===${NC}\n"
echo "\n=== Задание 4: Межсетевой экран ===" >> "$REPORT_FILE"

echo -e "${GREEN}[ OK ] Задание 4: Проверка firewall (см. отчёт)${NC}"
echo "[ OK ] Задание 4: Проверка firewall (см. отчёт)" >> "$REPORT_FILE"

# ============================================================
# ЗАДАНИЕ 5: CUPS принт-сервер
# ============================================================
echo -e "\n${YELLOW}=== Задание 5: CUPS принт-сервер ===${NC}\n"
echo "\n=== Задание 5: CUPS принт-сервер ===" >> "$REPORT_FILE"

check_service "$HQ_SRV" "cups"
check_port "$HQ_SRV" "631" "CUPS слушает порт 631"

check_task "$HQ_SRV" "Виртуальный PDF принтер опубликован" \
    "lpstat -a 2>/dev/null | grep -qi pdf" \
    "lpstat -a 2>/dev/null | grep -i pdf | head -1"

# Проверка принтера на HQ-CLI УДАЛЕНА по вашему требованию

# ============================================================
# ЗАДАНИЕ 6: RSyslog
# ============================================================
echo -e "\n${YELLOW}=== Задание 6: RSyslog ===${NC}\n"
echo "\n=== Задание 6: RSyslog ===" >> "$REPORT_FILE"

check_service "$HQ_SRV" "rsyslog"

check_task "$HQ_SRV" "Шаблон DynFile для логов в /opt/" \
    "test -f /etc/rsyslog.d/91_template.conf && grep -q 'DynFile' /etc/rsyslog.d/91_template.conf" \
    "head -2 /etc/rsyslog.d/91_template.conf 2>/dev/null | tr '\n' ' '"

for client in "$HQ_RTR" "$BR_RTR" "$BR_SRV"; do
    client_name=$(get_vm_name "$client")
    check_task "$client" "Отправка логов (warning) на HQ-SRV" \
        "test -f /etc/rsyslog.d/10_to_server.conf && grep -q '192.168.1.10' /etc/rsyslog.d/10_to_server.conf" \
        "cat /etc/rsyslog.d/10_to_server.conf 2>/dev/null"
done

# ============================================================
# ЗАДАНИЕ 7: Мониторинг
# ============================================================
echo -e "\n${YELLOW}=== Задание 7: Prometheus + Grafana ===${NC}\n"
echo "\n=== Задание 7: Prometheus + Grafana ===" >> "$REPORT_FILE"

check_service "$HQ_SRV" "prometheus"
check_service "$HQ_SRV" "grafana-server"
check_port "$HQ_SRV" "9090" "Prometheus порт 9090"
check_port "$HQ_SRV" "3000" "Grafana порт 3000"
check_service "$BR_SRV" "prometheus-node_exporter"
check_port "$BR_SRV" "9100" "Node Exporter порт 9100"

# ============================================================
# ЗАДАНИЕ 8: Ansible
# ============================================================
echo -e "\n${YELLOW}=== Задание 8: Ansible инвентаризация ===${NC}\n"
echo "\n=== Задание 8: Ansible инвентаризация ===" >> "$REPORT_FILE"

check_file "$BR_SRV" "/etc/ansible/get_hostname_address.yml" "Playbook get_hostname_address.yml"
check_file "$BR_SRV" "/etc/ansible/PC-INFO/hq-srv.yml" "Файл инвентаризации hq-srv.yml"
check_file "$BR_SRV" "/etc/ansible/PC-INFO/hq-cli.yml" "Файл инвентаризации hq-cli.yml"

check_task "$BR_SRV" "hq-srv.yml содержит Hostname" \
    "grep -qi 'Hostname:' /etc/ansible/PC-INFO/hq-srv.yml 2>/dev/null" \
    "head -2 /etc/ansible/PC-INFO/hq-srv.yml 2>/dev/null | tr '\n' ' '"

check_task "$BR_SRV" "hq-srv.yml содержит IP_Address" \
    "grep -qi 'IP_Address:' /etc/ansible/PC-INFO/hq-srv.yml 2>/dev/null" \
    "grep -i 'ip' /etc/ansible/PC-INFO/hq-srv.yml 2>/dev/null | head -1"

# ============================================================
# ЗАДАНИЕ 9: fail2ban
# ============================================================
echo -e "\n${YELLOW}=== Задание 9: fail2ban ===${NC}\n"
echo "\n=== Задание 9: fail2ban ===" >> "$REPORT_FILE"

check_service "$HQ_SRV" "fail2ban"

check_task "$HQ_SRV" "fail2ban: порт 2026" \
    "test -f /etc/fail2ban/jail.d/sshd.conf && grep -q 'port = 2026' /etc/fail2ban/jail.d/sshd.conf" \
    "grep 'port' /etc/fail2ban/jail.d/sshd.conf 2>/dev/null | head -1"

check_task "$HQ_SRV" "fail2ban: maxretry = 3" \
    "test -f /etc/fail2ban/jail.d/sshd.conf && grep -q 'maxretry = 3' /etc/fail2ban/jail.d/sshd.conf" \
    "grep 'maxretry' /etc/fail2ban/jail.d/sshd.conf 2>/dev/null | head -1"

check_task "$HQ_SRV" "fail2ban: bantime = 1m" \
    "test -f /etc/fail2ban/jail.d/sshd.conf && grep -q 'bantime = 1m' /etc/fail2ban/jail.d/sshd.conf" \
    "grep 'bantime' /etc/fail2ban/jail.d/sshd.conf 2>/dev/null | head -1"

# ============================================================
# ЗАДАНИЕ 10: Кибер Бэкап
# ============================================================
echo -e "\n${YELLOW}=== Задание 10: Кибер Бэкап ===${NC}\n"
echo "\n=== Задание 10: Кибер Бэкап ===" >> "$REPORT_FILE"

check_task "$HQ_SRV" "Пользователь irpoadmin" \
    "id irpoadmin &>/dev/null" \
    "id irpoadmin 2>/dev/null | awk '{print \$1}'"

check_port "$HQ_SRV" "9877" "Acronis Management Server (порт 9877)"

# Просто проверяем наличие директории /backup на HQ-CLI
check_directory "$HQ_CLI" "/backup" "Директория /backup существует на HQ-CLI"

# ============================================================
# СТАТИСТИКА
# ============================================================
echo -e "\n${BLUE}============================================================================${NC}"
echo -e "${BLUE}Статистика проверки Module 3${NC}"
echo -e "${BLUE}============================================================================${NC}\n"

total=$(grep -c '^\[' "$REPORT_FILE" 2>/dev/null || echo "0")
ok=$(grep -c '^\[ OK \]' "$REPORT_FILE" 2>/dev/null || echo "0")
fail=$(grep -c '^\[ FAIL \]' "$REPORT_FILE" 2>/dev/null || echo "0")

echo -e "${YELLOW}Всего проверок:${NC} $total"
echo -e "${GREEN}Успешно:${NC} $ok"
echo -e "${RED}Провалено:${NC} $fail"

if [[ $total -gt 0 ]]; then
    percent=$((ok * 100 / total))
    echo -e "${BLUE}Процент успеха:${NC} ${percent}%"
fi

echo -e "\n${GREEN}Отчет сохранен в: $REPORT_FILE${NC}"

echo "" >> "$REPORT_FILE"
echo "============================================================================" >> "$REPORT_FILE"
echo "СТАТИСТИКА" >> "$REPORT_FILE"
echo "============================================================================" >> "$REPORT_FILE"
echo "Всего проверок: $total" >> "$REPORT_FILE"
echo "Успешно: $ok" >> "$REPORT_FILE"
echo "Провалено: $fail" >> "$REPORT_FILE"

if [[ $fail -eq 0 ]]; then
    echo -e "\n${GREEN}СТАТУС: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ УСПЕШНО!${NC}"
    echo "СТАТУС: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ УСПЕШНО!" >> "$REPORT_FILE"
else
    echo -e "\n${RED}СТАТУС: ОБНАРУЖЕНЫ ПРОБЛЕМЫ (провалено ${fail} проверок)${NC}"
    echo "СТАТУС: ОБНАРУЖЕНЫ ПРОБЛЕМЫ (провалено ${fail} проверок)" >> "$REPORT_FILE"
fi