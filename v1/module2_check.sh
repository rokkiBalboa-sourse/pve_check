#!/bin/bash

REPORT_DIR="/root/pve_reports"
TIMESTAMP=$(date +"%d-%m-%Y_%H-%M-%S")
REPORT_FILE="${REPORT_DIR}/Module2_Report_${TIMESTAMP}.txt"

ISP="10201"
HQ_RTR="10202"
HQ_SRV="10203"
HQ_CLI="10204"
BR_RTR="10205"
BR_SRV="10206"

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
get_vm_name() { echo "${VM_NAMES[$1]:-$1}"; }

log_report() {
    local message="$1"
    local color="$2"
    echo -e "${color}${message}${NC}"
    echo "$message" >> "$REPORT_FILE"
}

check_task() {
    local vm_id="$1"
    local description="$2"
    local check_command="$3"
    local fact_command="$4"
    local vm_name=$(get_vm_name "$vm_id")

    local fact_output=$(qm guest exec "$vm_id" -- /bin/bash -c "$fact_command" 2>&1)
    local fact_exitcode=$(echo "$fact_output" | grep -oP '"exitcode"\s*:\s*\K[0-9]+' | head -1)
    local fact_data=$(echo "$fact_output" | grep -oP '"out-data"\s*:\s*"\K[^"]*' | sed 's/\\n/\n/g' | tr -d '\r' | sed -n '1p')
    
    [[ -z "$fact_data" ]] && fact_data=$(echo "$fact_output" | grep -oP '"err-data"\s*:\s*"\K[^"]*' | sed 's/\\n/\n/g' | tr -d '\r' | sed -n '1p')
    
    if [[ -z "$fact_data" ]]; then
        if [[ "$fact_exitcode" == "0" ]]; then
            fact_data="[OK]"
        elif [[ -z "$fact_exitcode" ]]; then
            log_report "[ FAIL ] $vm_name: $description -> нет ответа" "$RED"
            return 1
        else
            log_report "[ FAIL ] $vm_name: $description -> exitcode: ${fact_exitcode}" "$RED"
            return 1
        fi
    fi

    local check_output=$(qm guest exec "$vm_id" -- /bin/bash -c "$check_command" 2>&1)
    local check_exitcode
    echo "$check_output" | grep -E -q '"exitcode"\s*:\s*0' && check_exitcode=0 || check_exitcode=1

    if [[ "$check_exitcode" == "0" ]]; then
        log_report "[ OK ] $vm_name: $description -> ${fact_data}" "$GREEN"
        return 0
    else
        log_report "[ FAIL ] $vm_name: $description -> Ошибка (Факт: ${fact_data})" "$RED"
        return 1
    fi
}

check_service() {
    local vm_id="$1"
    local service_name="$2"
    local fact_cmd="systemctl is-active $service_name 2>/dev/null || echo 'inactive'"
    local check_cmd="systemctl is-active --quiet $service_name"
    check_task "$vm_id" "Сервис ${service_name}" "$check_cmd" "$fact_cmd"
}

# ============================================================
# НАЧАЛО
# ============================================================
echo "Отчет о проверке практических заданий Module 2" > "$REPORT_FILE"
echo "Дата и время: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "============================================================" >> "$REPORT_FILE"

log_report ""
log_report "=== НАЧАЛО ПРОВЕРКИ МОДУЛЬ 2 ===" "$YELLOW"

# ============================================================
# ЗАДАНИЕ 1: Samba DC
# ============================================================
log_report ""
log_report "--- Задание 1: Samba DC (BR-SRV) ---" "$YELLOW"
check_service "$BR_SRV" "samba"

log_report "DNS записи:"
check_task "$BR_SRV" "DNS hq-srv -> 192.168.1.10" \
    "samba-tool dns query localhost au-team.irpo hq-srv A -U administrator%'P@ssw0rd' 2>/dev/null | grep -q '192.168.1.10'" \
    "samba-tool dns query localhost au-team.irpo hq-srv A -U administrator%'P@ssw0rd' 2>/dev/null | grep 'A:' | awk '{print \$2}' || echo 'not_found'"

check_task "$BR_SRV" "DNS hq-rtr -> 192.168.1.1" \
    "samba-tool dns query localhost au-team.irpo hq-rtr A -U administrator%'P@ssw0rd' 2>/dev/null | grep -q '192.168.1.1'" \
    "samba-tool dns query localhost au-team.irpo hq-rtr A -U administrator%'P@ssw0rd' 2>/dev/null | grep 'A:' | awk '{print \$2}' || echo 'not_found'"

check_task "$BR_SRV" "DNS br-rtr -> 192.168.3.1" \
    "samba-tool dns query localhost au-team.irpo br-rtr A -U administrator%'P@ssw0rd' 2>/dev/null | grep -q '192.168.3.1'" \
    "samba-tool dns query localhost au-team.irpo br-rtr A -U administrator%'P@ssw0rd' 2>/dev/null | grep 'A:' | awk '{print \$2}' || echo 'not_found'"

check_task "$BR_SRV" "DNS web -> 172.16.1.1" \
    "samba-tool dns query localhost au-team.irpo web A -U administrator%'P@ssw0rd' 2>/dev/null | grep -q '172.16.1.1'" \
    "samba-tool dns query localhost au-team.irpo web A -U administrator%'P@ssw0rd' 2>/dev/null | grep 'A:' | awk '{print \$2}' || echo 'not_found'"

check_task "$BR_SRV" "DNS docker -> 172.16.2.1" \
    "samba-tool dns query localhost au-team.irpo docker A -U administrator%'P@ssw0rd' 2>/dev/null | grep -q '172.16.2.1'" \
    "samba-tool dns query localhost au-team.irpo docker A -U administrator%'P@ssw0rd' 2>/dev/null | grep 'A:' | awk '{print \$2}' || echo 'not_found'"

log_report "Пользователи Samba:"
for i in {1..5}; do
    check_task "$BR_SRV" "User hquser$i" \
        "samba-tool user list 2>/dev/null | grep -q 'hquser$i'" \
        "samba-tool user list 2>/dev/null | grep 'hquser$i' || echo 'not_found'"
done

log_report "Группа hq:"
check_task "$BR_SRV" "Группа hq с пользователями" \
    "samba-tool group listmembers hq 2>/dev/null | grep -q 'hquser1'" \
    "samba-tool group listmembers hq 2>/dev/null | tr '\n' ' '"

# ============================================================
# ЗАДАНИЕ 2: RAID
# ============================================================
log_report ""
log_report "--- Задание 2: RAID (HQ-SRV) ---" "$YELLOW"
check_task "$HQ_SRV" "RAID1 /dev/md1" \
    "grep -q 'md1' /proc/mdstat" \
    "grep md1 /proc/mdstat | head -1"
check_task "$HQ_SRV" "Монтирование /raid" \
    "mount | grep -q '/dev/md1 on /raid'" \
    "mount | grep '/dev/md1' | awk '{print \$3}'"

# ============================================================
# ЗАДАНИЕ 3: NFS
# ============================================================
log_report ""
log_report "--- Задание 3: NFS (HQ-SRV + HQ-CLI) ---" "$YELLOW"
check_service "$HQ_SRV" "nfs-server"
check_task "$HQ_SRV" "NFS экспорт /raid/nfs" \
    "showmount -e localhost 2>/dev/null | grep -q '/raid/nfs'" \
    "showmount -e localhost 2>/dev/null | grep '/raid/nfs' | awk '{print \$1}'"
check_task "$HQ_SRV" "Права /raid/nfs (777)" \
    "stat -c '%a' /raid/nfs 2>/dev/null | grep -q '777'" \
    "stat -c '%a' /raid/nfs 2>/dev/null"
check_task "$HQ_CLI" "Монтирование NFS /mnt/nfs" \
    "mount | grep -q '/mnt/nfs'" \
    "mount | grep '/mnt/nfs' | awk '{print \$1}'"

# ============================================================
# ЗАДАНИЕ 4: NTP Chrony
# ============================================================
log_report ""
log_report "--- Задание 4: NTP Chrony ---" "$YELLOW"
check_task "$ISP" "Chrony сервер" \
    "grep -q 'local stratum 6' /etc/chrony.conf" \
    "grep 'local stratum' /etc/chrony.conf"
check_task "$HQ_SRV" "NTP синхронизация с 172.16.1.1" \
    "chronyc sources 2>/dev/null | grep -q '172.16.1.1'" \
    "chronyc sources 2>/dev/null | grep '172.16.1.1' | awk '{print \$2}' | head -1 || echo 'not_synced'"
check_task "$BR_RTR" "NTP синхронизация с 172.16.1.1" \
    "chronyc sources 2>/dev/null | grep -q '172.16.1.1'" \
    "chronyc sources 2>/dev/null | grep '172.16.1.1' | awk '{print \$2}' | head -1 || echo 'not_synced'"
check_task "$BR_SRV" "NTP синхронизация с 172.16.1.1" \
    "chronyc sources 2>/dev/null | grep -q '172.16.1.1'" \
    "chronyc sources 2>/dev/null | grep '172.16.1.1' | awk '{print \$2}' | head -1 || echo 'not_synced'"
check_task "$HQ_CLI" "NTP синхронизация с 172.16.1.1" \
    "chronyc sources 2>/dev/null | grep -q '172.16.1.1'" \
    "chronyc sources 2>/dev/null | grep '172.16.1.1' | awk '{print \$2}' | head -1 || echo 'not_synced'"

# ============================================================
# ЗАДАНИЕ 5: Ansible
# ============================================================
log_report ""
log_report "--- Задание 5: Ansible (BR-SRV) ---" "$YELLOW"
check_task "$BR_SRV" "Ansible ping HQ-SRV" \
    "cd /etc/ansible && ansible HQ-SRV -m ping 2>/dev/null | grep -q 'SUCCESS'" \
    "cd /etc/ansible && ansible HQ-SRV -m ping 2>/dev/null | grep -E 'SUCCESS|UNREACHABLE' | head -1"
check_task "$BR_SRV" "Ansible ping HQ-RTR" \
    "cd /etc/ansible && ansible HQ-RTR -m ping 2>/dev/null | grep -q 'SUCCESS'" \
    "cd /etc/ansible && ansible HQ-RTR -m ping 2>/dev/null | grep -E 'SUCCESS|UNREACHABLE' | head -1"
check_task "$BR_SRV" "Ansible ping BR-RTR" \
    "cd /etc/ansible && ansible BR-RTR -m ping 2>/dev/null | grep -q 'SUCCESS'" \
    "cd /etc/ansible && ansible BR-RTR -m ping 2>/dev/null | grep -E 'SUCCESS|UNREACHABLE' | head -1"
check_task "$BR_SRV" "Ansible ping HQ-CLI" \
    "cd /etc/ansible && ansible HQ-CLI -m ping 2>/dev/null | grep -q 'SUCCESS'" \
    "cd /etc/ansible && ansible HQ-CLI -m ping 2>/dev/null | grep -E 'SUCCESS|UNREACHABLE' | head -1"

# ============================================================
# ЗАДАНИЕ 6: Docker
# ============================================================
log_report ""
log_report "--- Задание 6: Docker (BR-SRV) ---" "$YELLOW"
check_service "$BR_SRV" "docker"
check_task "$BR_SRV" "Docker site" \
    "docker ps --filter name=site --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" \
    "docker ps --filter name=site --format '{{.Status}}' 2>/dev/null || echo 'not_running'"
check_task "$BR_SRV" "Docker db" \
    "docker ps --filter name=db --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" \
    "docker ps --filter name=db --format '{{.Status}}' 2>/dev/null || echo 'not_running'"

# ============================================================
# ЗАДАНИЕ 7: LAMP
# ============================================================
log_report ""
log_report "--- Задание 7: LAMP (HQ-SRV) ---" "$YELLOW"
check_service "$HQ_SRV" "httpd2"
check_service "$HQ_SRV" "mariadb"
check_task "$HQ_SRV" "Файл index.php" \
    "test -f /var/www/html/index.php" \
    "ls -la /var/www/html/index.php 2>/dev/null | awk '{print \$NF}' || echo 'not_found'"
check_task "$HQ_SRV" "БД webdb" \
    "mariadb -e 'USE webdb; SHOW TABLES;' 2>/dev/null | grep -q 'webdb'" \
    "mariadb -e 'USE webdb; SHOW TABLES;' 2>/dev/null | head -2 | tail -1 || echo 'error'"

# ============================================================
# ЗАДАНИЕ 8: DNAT
# ============================================================
log_report ""
log_report "--- Задание 8: DNAT (HQ-RTR + BR-RTR) ---" "$YELLOW"
check_task "$HQ_RTR" "DNAT 2011->192.168.1.10" \
    "nft list ruleset 2>/dev/null | grep -q 'dport 2011 dnat to 192.168.1.10'" \
    "nft list ruleset 2>/dev/null | grep 'dport 2011' | grep -oP 'dnat to \K[^ ]+' | tr -d ' ' | head -1 || echo 'not_found'"

check_task "$HQ_RTR" "DNAT 8081->192.168.1.10:80" \
    "nft list ruleset 2>/dev/null | grep -q 'dport 8081 dnat to 192.168.1.10:80'" \
    "nft list ruleset 2>/dev/null | grep 'dport 8081' | grep -oP 'dnat to \K[^ ]+' | tr -d ' ' | head -1 || echo 'not_found'"

check_task "$BR_RTR" "DNAT {8081,2011}->192.168.3.10" \
    "nft list ruleset 2>/dev/null | grep -E 'dport.*\{.*(8081|2011).*\}' | grep -q 'dnat to 192.168.3.10'" \
    "nft list ruleset 2>/dev/null | grep -E 'dport.*\{.*(8081|2011).*\}' | grep -oP 'dnat to \K[0-9.]+' | tr -d ' ' | head -1 || echo 'not_found'"

# ============================================================
# ЗАДАНИЕ 9-10: Nginx reverse proxy
# ============================================================
log_report ""
log_report "--- Задание 9-10: Nginx reverse proxy (ISP) ---" "$YELLOW"
check_service "$ISP" "nginx"
check_task "$ISP" "web proxy -> 172.16.1.10:8081" \
    "grep -q 'proxy_pass http://172.16.1.10:8081' /etc/nginx/sites-enabled.d/r-proxy.conf 2>/dev/null" \
    "grep 'proxy_pass http://172.16.1.10:8081' /etc/nginx/sites-enabled.d/r-proxy.conf 2>/dev/null || echo 'not_found'"
check_task "$ISP" "docker proxy -> 172.16.2.10:8081" \
    "grep -q 'proxy_pass http://172.16.2.10:8081' /etc/nginx/sites-enabled.d/r-proxy.conf 2>/dev/null" \
    "grep 'proxy_pass http://172.16.2.10:8081' /etc/nginx/sites-enabled.d/r-proxy.conf 2>/dev/null || echo 'not_found'"
check_task "$ISP" "Basic auth WEB" \
    "test -f /etc/nginx/.htpasswd && grep -q 'Khariton' /etc/nginx/.htpasswd" \
    "cat /etc/nginx/.htpasswd 2>/dev/null | cut -d: -f1 || echo 'file_not_found'"

# ============================================================
# ЗАДАНИЕ 11: Браузер на HQ-CLI
# ============================================================
log_report ""
log_report "--- Задание 11: Браузер (HQ-CLI) ---" "$YELLOW"
check_task "$HQ_CLI" "Yandex Browser" \
    "rpm -q yandex-browser-stable 2>/dev/null || dpkg -l yandex-browser-stable 2>/dev/null | grep -q '^ii'" \
    "rpm -q yandex-browser-stable 2>/dev/null || dpkg -l yandex-browser-stable 2>/dev/null | grep 'yandex' | awk '{print \$2, \$3}' | head -1 || echo 'not_installed'"

# ============================================================
# СТАТИСТИКА
# ============================================================
log_report ""
log_report "=== СТАТИСТИКА ПРОВЕРКИ ===" "$YELLOW"
total=$(grep -c '^\[' "$REPORT_FILE")
ok=$(grep -c '^\[ OK \]' "$REPORT_FILE")
fail=$(grep -c '^\[ FAIL \]' "$REPORT_FILE")
log_report "Всего проверок: $total" "$BLUE"
log_report "Успешно: $ok" "$GREEN"
log_report "Провалено: $fail" "$RED"
[[ $fail -eq 0 ]] && log_report "СТАТУС: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ!" "$GREEN" || log_report "СТАТУС: ПРОБЛЕМ ($fail)" "$RED"

log_report ""
log_report "=== ПРОВЕРКА ЗАВЕРШЕНА ===" "$YELLOW"
log_report "Отчет сохранен в: $REPORT_FILE" "$YELLOW"
echo -e "${GREEN}Готово: $REPORT_FILE${NC}"