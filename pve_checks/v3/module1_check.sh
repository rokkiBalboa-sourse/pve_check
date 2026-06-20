#!/bin/bash

# --- Настройки ---
REPORT_DIR="/root/pve_reports"
TIMESTAMP=$(date +"%d-%m-%Y_%H-%M-%S")
REPORT_FILE="${REPORT_DIR}/Module_Check_Report_${TIMESTAMP}.txt"

# ID виртуальных машин
ISP="10101"
HQ_RTR="10102"
HQ_SRV="10103"
HQ_CLI="10104"
BR_RTR="10105"
BR_SRV="10106"

# Массив с именами ВМ для отображения
declare -A VM_NAMES
VM_NAMES[$ISP]="ISP"
VM_NAMES[$HQ_RTR]="HQ-RTR"
VM_NAMES[$HQ_SRV]="HQ-SRV"
VM_NAMES[$HQ_CLI]="HQ-CLI"
VM_NAMES[$BR_RTR]="BR-RTR"
VM_NAMES[$BR_SRV]="BR-SRV"

# Цвета для консоли
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Создаем директорию для отчетов
mkdir -p "$REPORT_DIR"

# --- Функция получения имени ВМ ---
get_vm_name() {
    local vm_id="$1"
    echo "${VM_NAMES[$vm_id]:-$vm_id}"
}

# --- Функция логирования ---
log_report() {
    local message="$1"
    local color="$2"
    echo -e "${color}${message}${NC}"
    echo "$message" >> "$REPORT_FILE"
}

# --- Функция проверки ВМ (QEMU Guest Agent) ---
check_task() {
    local vm_id="$1"
    local description="$2"
    local check_command="$3"
    local fact_command="$4"
    local vm_name
    vm_name=$(get_vm_name "$vm_id")

    # === ПОЛУЧЕНИЕ ФАКТА ===
    local fact_output
    fact_output=$(qm guest exec "$vm_id" -- /bin/bash -c "$fact_command" 2>&1)
    
    # Парсим exitcode
    local fact_exitcode
    fact_exitcode=$(echo "$fact_output" | grep -oP '"exitcode"\s*:\s*\K[0-9]+' | head -1)
    
    # Извлекаем данные из "out-data"
    local fact_data
    fact_data=$(echo "$fact_output" | grep -oP '"out-data"\s*:\s*"\K[^"]*' | sed 's/\\n/\n/g' | head -1)
    
    # Если out-data пустой, пробуем err-data
    if [[ -z "$fact_data" ]]; then
        fact_data=$(echo "$fact_output" | grep -oP '"err-data"\s*:\s*"\K[^"]*' | sed 's/\\n/\n/g' | head -1)
    fi
    
    # Если всё ещё пусто, проверяем exitcode
    if [[ -z "$fact_data" ]]; then
        if [[ "$fact_exitcode" == "0" ]]; then
            fact_data="[OK]"
        elif [[ -z "$fact_exitcode" ]]; then
            fact_data="Ошибка выполнения: нет ответа от QEMU Guest Agent"
            log_report "[ FAIL ] $vm_name: $description -> $fact_data" "$RED"
            return 1
        else
            fact_data="Ошибка выполнения (exitcode: ${fact_exitcode})"
            log_report "[ FAIL ] $vm_name: $description -> $fact_data" "$RED"
            return 1
        fi
    fi

    # === ПРОВЕРКА ===
    local check_output
    check_output=$(qm guest exec "$vm_id" -- /bin/bash -c "$check_command" 2>&1)
    
    # Ищем "exitcode":0 с игнорированием пробелов
    local check_exitcode
    if echo "$check_output" | grep -E -q '"exitcode"\s*:\s*0'; then
        check_exitcode=0
    else
        check_exitcode=1
    fi

    if [[ "$check_exitcode" == "0" ]]; then
        log_report "[ OK ] $vm_name: $description -> ${fact_data}" "$GREEN"
        return 0
    else
        # Пытаемся получить ошибку из err-data
        local error_data
        error_data=$(echo "$check_output" | grep -oP '"err-data"\s*:\s*"\K[^"]*' | sed 's/\\n/\n/g' | head -1)
        if [[ -n "$error_data" ]]; then
            log_report "[ FAIL ] $vm_name: $description -> Ошибка: ${error_data} (Факт: ${fact_data})" "$RED"
        else
            log_report "[ FAIL ] $vm_name: $description -> Ошибка (Факт: ${fact_data})" "$RED"
        fi
        return 1
    fi
}

# --- Функция проверки конфигурации ВМ (qm config) ---
check_vm_config() {
    local vm_id="$1"
    local description="$2"
    local search_pattern="$3"
    local vm_name
    vm_name=$(get_vm_name "$vm_id")

    local config_output
    config_output=$(qm config "$vm_id" 2>&1)
    
    local fact_data
    fact_data=$(echo "$config_output" | grep "$search_pattern" | head -1)
    
    if [[ -z "$fact_data" ]]; then
        fact_data=$(echo "$config_output" | grep -E "$(echo "$search_pattern" | sed 's/=.*//')" | head -1)
        [[ -z "$fact_data" ]] && fact_data="Строка не найдена в конфигурации"
    fi

    if echo "$config_output" | grep -q "$search_pattern"; then
        log_report "[ OK ] $vm_name (qm config): $description -> ${fact_data}" "$GREEN"
        return 0
    else
        log_report "[ FAIL ] $vm_name (qm config): $description -> Ошибка (Факт: ${fact_data})" "$RED"
        return 1
    fi
}

# --- Проверка VLAN на net6 ---
check_vm_vlan_net6() {
    local vm_id="$1"
    local expected_tag="$2"
    local vm_name
    vm_name=$(get_vm_name "$vm_id")
    local net_interface="net6"
    local description="VLAN tag=${expected_tag} на интерфейсе ${net_interface}"
    
    local config_output
    config_output=$(qm config "$vm_id" 2>&1)
    
    local interface_line
    interface_line=$(echo "$config_output" | grep "^${net_interface}:" | head -1)
    
    if [[ -z "$interface_line" ]]; then
        log_report "[ FAIL ] $vm_name (qm config): $description -> Интерфейс ${net_interface} не найден в конфигурации" "$RED"
        local all_nets
        all_nets=$(echo "$config_output" | grep "^net[0-9]:" | tr '\n' '; ')
        log_report "       Доступные интерфейсы: ${all_nets}" "$YELLOW"
        return 1
    fi
    
    local current_tag
    current_tag=$(echo "$interface_line" | grep -oP 'tag=\K[0-9]+' || echo "not_set")
    
    if [[ "$current_tag" == "$expected_tag" ]]; then
        log_report "[ OK ] $vm_name (qm config): $description -> tag=${current_tag}" "$GREEN"
        log_report "       ${interface_line}" "$BLUE"
        return 0
    elif [[ "$current_tag" == "not_set" ]]; then
        log_report "[ FAIL ] $vm_name (qm config): $description -> VLAN tag не установлен на ${net_interface}" "$RED"
        log_report "       Строка: ${interface_line}" "$YELLOW"
        return 1
    else
        log_report "[ FAIL ] $vm_name (qm config): $description -> Ошибка (Факт: tag=${current_tag})" "$RED"
        log_report "       Строка: ${interface_line}" "$YELLOW"
        return 1
    fi
}

# ============================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ПРОВЕРОК ОС
# ============================================================

# 1. Проверка hostname
check_hostname() {
    local vm_id="$1"
    local expected="$2"
    local fact_cmd="hostname"
    local check_cmd="hostname | tr -dc 'a-zA-Z0-9' | grep -iq '$(echo "$expected" | tr -dc 'a-zA-Z0-9')'"
    check_task "$vm_id" "Hostname (${expected})" "$check_cmd" "$fact_cmd"
}

# 2. Проверка IP-адреса
check_ip() {
    local vm_id="$1"
    local interface="$2"
    local expected_ip="$3"
    local fact_cmd="ip -br a show $interface 2>/dev/null | awk '{print \$3}' | head -1"
    local check_cmd="ip -br a show $interface 2>/dev/null | grep -E -o '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | grep -q '${expected_ip}'"
    check_task "$vm_id" "IP адрес ${interface} (${expected_ip})" "$check_cmd" "$fact_cmd"
}

# 3. Проверка пользователя в /etc/shadow (показываем статус блокировки)
check_user_not_locked() {
    local vm_id="$1"
    local user="$2"
    local fact_cmd="PASS=\$(getent shadow '$user' 2>/dev/null | cut -d: -f2); if [[ -z \"\$PASS\" ]]; then echo 'user_not_found'; elif [[ \"\$PASS\" =~ ^[!*] ]]; then echo 'LOCKED'; else echo 'ACTIVE'; fi"
    local check_cmd="getent shadow '$user' 2>/dev/null | cut -d: -f2 | grep -q -v '^[!*]'"
    check_task "$vm_id" "Пользователь ${user} не заблокирован" "$check_cmd" "$fact_cmd"
}

# 4. Проверка прав sudo (проверяем файл в /etc/sudoers.d/ или группу wheel)
check_sudo() {
    local vm_id="$1"
    local user="$2"
    
    local fact_cmd="if [[ -f /etc/sudoers.d/$user ]]; then cat /etc/sudoers.d/$user 2>/dev/null; elif groups $user 2>/dev/null | grep -q wheel; then echo 'user in wheel group'; else echo 'no sudo config found'; fi"
    local check_cmd="if [[ -f /etc/sudoers.d/$user ]]; then grep -q 'NOPASSWD' /etc/sudoers.d/$user 2>/dev/null; elif groups $user 2>/dev/null | grep -q wheel; then grep -q '%wheel.*NOPASSWD\|%WHEEL_USERS.*NOPASSWD' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; else false; fi"
    
    check_task "$vm_id" "Sudo права ${user}" "$check_cmd" "$fact_cmd"
}

# 5. Проверка порта SSH
check_ssh_port() {
    local vm_id="$1"
    local expected_port="$2"
    
    local fact_cmd="grep -E '^Port ' /etc/openssh/sshd_config 2>/dev/null | awk '{print \$2}' || echo 'Port not found'"
    local check_cmd="PORT=\$(grep -E '^Port ' /etc/openssh/sshd_config 2>/dev/null | awk '{print \$2}'); [[ \"\$PORT\" == '${expected_port}' ]] && systemctl is-active --quiet sshd"
    
    check_task "$vm_id" "SSH порт (${expected_port})" "$check_cmd" "$fact_cmd"
}

# 6. Проверка запущенного сервиса
check_service() {
    local vm_id="$1"
    local service_name="$2"
    local fact_cmd="systemctl is-active $service_name 2>/dev/null || echo 'inactive/dead'"
    local check_cmd="systemctl is-active --quiet $service_name"
    check_task "$vm_id" "Сервис ${service_name}" "$check_cmd" "$fact_cmd"
}

# 7. ИСПРАВЛЕННАЯ проверка DNS записей (прямая)
check_dns_record() {
    local vm_id="$1"
    local record_name="$2"
    local expected_value="$3"
    
    # Факт: получаем IP из DNS записи (отсекаем "server:" и другие лишние строки)
    local fact_cmd="RESULT=\$(host $record_name 127.0.0.1 2>/dev/null); if echo \"\$RESULT\" | grep -q 'has address'; then echo \"\$RESULT\" | grep 'has address' | awk '{print \$NF}'; elif echo \"\$RESULT\" | grep -q 'NXDOMAIN'; then echo 'NXDOMAIN'; else echo 'not_resolved'; fi"
    
    # Проверка: сравниваем полученный IP с ожидаемым
    local check_cmd="host $record_name 127.0.0.1 2>/dev/null | grep -q '$expected_value'"
    
    check_task "$vm_id" "DNS запись ${record_name} -> ${expected_value}" "$check_cmd" "$fact_cmd"
}

# 8. ИСПРАВЛЕННАЯ проверка DNS PTR записей (обратная)
check_dns_ptr() {
    local vm_id="$1"
    local ip_address="$2"
    local expected_name="$3"
    
    # Факт: получаем имя из PTR записи
    local fact_cmd="RESULT=\$(host $ip_address 127.0.0.1 2>/dev/null); if echo \"\$RESULT\" | grep -q 'pointer'; then echo \"\$RESULT\" | grep 'pointer' | awk '{print \$NF}'; elif echo \"\$RESULT\" | grep -q 'NXDOMAIN'; then echo 'NXDOMAIN'; else echo 'not_resolved'; fi"
    
    # Проверка: сравниваем полученное имя с ожидаемым
    local check_cmd="host $ip_address 127.0.0.1 2>/dev/null | grep -q '$expected_name'"
    
    check_task "$vm_id" "PTR запись ${ip_address} -> ${expected_name}" "$check_cmd" "$fact_cmd"
}

# 9. Проверка DHCP диапазона в dnsmasq
check_dhcp_config() {
    local vm_id="$1"
    local config_line="$2"
    local fact_cmd="grep 'dhcp-range' /etc/dnsmasq.conf 2>/dev/null | head -1 || echo 'not_found'"
    local check_cmd="grep -q '${config_line}' /etc/dnsmasq.conf"
    check_task "$vm_id" "DHCP конфигурация dnsmasq" "$check_cmd" "$fact_cmd"
}

# 10. Проверка NAT (nftables)
check_nat() {
    local vm_id="$1"
    local interface="$2"
    local fact_cmd="nft list ruleset 2>/dev/null | grep -A2 'postrouting' | grep -E 'oifname|masquerade' | head -1 || echo 'not_found'"
    local check_cmd="nft list ruleset 2>/dev/null | grep -q 'oifname \"${interface}\" masquerade'"
    check_task "$vm_id" "NAT (маскарадинг) на ${interface}" "$check_cmd" "$fact_cmd"
}

# 11. Проверка GRE туннеля
check_gre_tunnel() {
    local vm_id="$1"
    local tunnel_name="$2"
    local local_ip="$3"
    local remote_ip="$4"
    local fact_cmd="cat /etc/net/ifaces/${tunnel_name}/options 2>/dev/null | grep -E 'TUNLOCAL|TUNREMOTE' | tr '\n' ' ' || echo 'not_found'"
    local check_cmd="grep -q 'TUNLOCAL=${local_ip}' /etc/net/ifaces/${tunnel_name}/options 2>/dev/null && grep -q 'TUNREMOTE=${remote_ip}' /etc/net/ifaces/${tunnel_name}/options"
    check_task "$vm_id" "GRE туннель ${tunnel_name} (лок. ${local_ip}, удал. ${remote_ip})" "$check_cmd" "$fact_cmd"
}

# 12. Проверка SSH подключения (с sshpass и игнорированием ключей)
check_ssh_connection() {
    local vm_id="$1"
    local target_ip="$2"
    local target_port="$3"
    local ssh_user="$4"
    
    local fact_cmd="sshpass -p 'P@ssw0rd' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p ${target_port} ${ssh_user}@${target_ip} 'hostname' 2>&1 || echo 'SSH_FAILED'"
    local check_cmd="sshpass -p 'P@ssw0rd' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p ${target_port} ${ssh_user}@${target_ip} 'hostname' &>/dev/null"
    
    check_task "$vm_id" "SSH до ${ssh_user}@${target_ip}:${target_port}" "$check_cmd" "$fact_cmd"
}

# ============================================================
# НАЧАЛО ТЕСТИРОВАНИЯ
# ============================================================

# Инициализация отчета
echo "Отчет о проверке практических заданий (PVE QEMU Guest Agent + qm config)" > "$REPORT_FILE"
echo "Дата и время: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "============================================================" >> "$REPORT_FILE"

log_report ""
log_report "=== НАЧАЛО ПРОВЕРКИ ===" "$YELLOW"
log_report ""

# ============================================================
# ЗАДАНИЕ 1: Имена хостов и базовая сеть
# ============================================================
log_report "--- Задание 1: Имена хостов и Настройка IP адресов ---" "$YELLOW"

log_report "Имена хостов:"
check_hostname "$ISP" "isp.au-team.irpo"
check_hostname "$HQ_RTR" "hq-rtr.au-team.irpo"
check_hostname "$HQ_SRV" "hq-srv.au-team.irpo"
check_hostname "$HQ_CLI" "hq-cli.au-team.irpo"
check_hostname "$BR_RTR" "br-rtr.au-team.irpo"
check_hostname "$BR_SRV" "br-srv.au-team.irpo"

log_report ""
log_report "IP адреса (кроме ISP):"
# BR-RTR
check_ip "$BR_RTR" "enp7s1" "172.16.60.2/28"
check_ip "$BR_RTR" "enp7s2" "192.168.0.1/28"
# BR-SRV
check_ip "$BR_SRV" "enp7s1" "192.168.0.2/28"
# HQ-RTR
check_ip "$HQ_RTR" "enp7s1" "172.16.50.2/28"
check_ip "$HQ_RTR" "vlan113" "192.168.100.1/27"
check_ip "$HQ_RTR" "vlan213" "192.168.200.1/24"
check_ip "$HQ_RTR" "vlan813" "192.168.99.1/29"
# HQ-SRV
check_ip "$HQ_SRV" "enp7s1" "192.168.100.2/27"

# ============================================================
# ЗАДАНИЕ 2: NAT на ISP + IP адреса ISP
# ============================================================
log_report ""
log_report "--- Задание 2: NAT, форвардинг и IP адреса ISP ---" "$YELLOW"

log_report "IP адреса ISP:"
check_ip "$ISP" "enp7s2" "172.16.50.1/28"
check_ip "$ISP" "enp7s3" "172.16.60.1/28"

log_report ""
log_report "NAT и форвардинг:"
check_nat "$ISP" "enp7s1"
check_task "$ISP" "IP форвардинг (net.ipv4.ip_forward=1)" "sysctl net.ipv4.ip_forward | grep -q '= 1'" "sysctl net.ipv4.ip_forward | awk '{print \$3}'"

# ============================================================
# ЗАДАНИЕ 3: Пользователи и права
# ============================================================
log_report ""
log_report "--- Задание 3: Пользователи ---" "$YELLOW"
# HQ-SRV и BR-SRV: sshuser
check_user_not_locked "$HQ_SRV" "sshuser"
check_sudo "$HQ_SRV" "sshuser"
check_user_not_locked "$BR_SRV" "sshuser"
check_sudo "$BR_SRV" "sshuser"
# HQ-RTR и BR-RTR: net_admin
check_user_not_locked "$HQ_RTR" "net_admin"
check_sudo "$HQ_RTR" "net_admin"
check_user_not_locked "$BR_RTR" "net_admin"
check_sudo "$BR_RTR" "net_admin"

# ============================================================
# ЗАДАНИЕ 4: Проверка VLAN на Hardware (qm config)
# ============================================================
log_report ""
log_report "--- Задание 4: Проверка оборудования (qm config): VLAN на net6 ---" "$BLUE"

log_report "Проверка HQ-SRV (net6, tag=113)..."
check_vm_vlan_net6 "$HQ_SRV" "113"

log_report "Проверка HQ-CLI (net6, tag=213)..."
check_vm_vlan_net6 "$HQ_CLI" "213"

log_report ""
log_report "Дополнительная проверка: bridge на net6"
check_vm_config "$HQ_SRV" "Наличие bridge на интерфейсе net6" "net6.*bridge="
check_vm_config "$HQ_CLI" "Наличие bridge на интерфейсе net6" "net6.*bridge="

# ============================================================
# ЗАДАНИЕ 5: Настройка SSH + Тест SSH подключения
# ============================================================
log_report ""
log_report "--- Задание 5: Настройка SSH ---" "$YELLOW"

log_report "Проверка конфигурации SSH:"
check_ssh_port "$HQ_SRV" "2013"
check_ssh_port "$BR_SRV" "2013"
check_task "$HQ_SRV" "SSH AllowUsers sshuser" "grep -q 'AllowUsers sshuser' /etc/openssh/sshd_config" "grep 'AllowUsers' /etc/openssh/sshd_config | head -1"
check_task "$HQ_SRV" "SSH Banner" "grep -q 'Authorized access only' /etc/openssh/ssh_banner" "cat /etc/openssh/ssh_banner 2>/dev/null || echo 'no_banner'"
check_task "$BR_SRV" "SSH AllowUsers sshuser" "grep -q 'AllowUsers sshuser' /etc/openssh/sshd_config" "grep 'AllowUsers' /etc/openssh/sshd_config | head -1"
check_task "$BR_SRV" "SSH Banner" "grep -q 'Authorized access only' /etc/openssh/ssh_banner" "cat /etc/openssh/ssh_banner 2>/dev/null || echo 'no_banner'"

log_report ""
log_report "Тест SSH подключения:"
check_ssh_connection "$HQ_RTR" "192.168.100.2" "2013" "sshuser"
check_ssh_connection "$BR_RTR" "192.168.0.2" "2013" "sshuser"

# ============================================================
# ЗАДАНИЕ 6: GRE туннель
# ============================================================
log_report ""
log_report "--- Задание 6: GRE туннель ---" "$YELLOW"
check_gre_tunnel "$HQ_RTR" "gre1" "172.16.50.2" "172.16.60.2"
check_gre_tunnel "$BR_RTR" "gre1" "172.16.60.2" "172.16.50.2"
check_ip "$HQ_RTR" "gre1" "10.10.10.1/30"
check_ip "$BR_RTR" "gre1" "10.10.10.2/30"
check_task "$HQ_RTR" "Пинг 10.10.10.2 через GRE" "ping -c 3 10.10.10.2 &>/dev/null" "ping -c 3 10.10.10.2 2>&1 | tail -1"

# ============================================================
# ЗАДАНИЕ 7: OSPF (FRR)
# ============================================================
log_report ""
log_report "--- Задание 7: OSPF (FRR) ---" "$YELLOW"
check_service "$HQ_RTR" "frr"
check_service "$BR_RTR" "frr"
check_task "$HQ_RTR" "ospfd в /etc/frr/daemons" "grep -q 'ospfd=yes' /etc/frr/daemons" "grep 'ospfd' /etc/frr/daemons"
check_task "$BR_RTR" "ospfd в /etc/frr/daemons" "grep -q 'ospfd=yes' /etc/frr/daemons" "grep 'ospfd' /etc/frr/daemons"
check_task "$HQ_RTR" "OSPF аутентификация на gre1" "grep -A5 'interface gre1' /etc/frr/frr.conf | grep -q 'ip ospf authentication'" "grep -A5 'interface gre1' /etc/frr/frr.conf | grep 'ip ospf authentication' || echo 'not_found'"
check_task "$BR_RTR" "OSPF аутентификация на gre1" "grep -A5 'interface gre1' /etc/frr/frr.conf | grep -q 'ip ospf authentication'" "grep -A5 'interface gre1' /etc/frr/frr.conf | grep 'ip ospf authentication' || echo 'not_found'"

# ============================================================
# ЗАДАНИЕ 8: NAT на HQ-RTR и BR-RTR
# ============================================================
log_report ""
log_report "--- Задание 8: NAT ---" "$YELLOW"
check_nat "$HQ_RTR" "enp7s1"
check_nat "$BR_RTR" "enp7s1"

# ============================================================
# ЗАДАНИЕ 9: DNS и DHCP
# ============================================================
log_report ""
log_report "--- Задание 9: DNS и DHCP ---" "$YELLOW"
check_service "$HQ_RTR" "dnsmasq"
check_dhcp_config "$HQ_RTR" "dhcp-range=interface:vlan213,192.168.200.2,192.168.200.2,255.255.255.240,6h"
check_task "$HQ_RTR" "DNS перенаправлен на 192.168.100.2" "grep -q 'nameserver 192.168.100.2' /etc/net/ifaces/vlan113/resolv.conf" "cat /etc/net/ifaces/vlan113/resolv.conf 2>/dev/null || echo 'not_set'"

# ============================================================
# ЗАДАНИЕ 10: DNS сервер на HQ-SRV (ИСПРАВЛЕН ВЫВОД)
# ============================================================
log_report ""
log_report "--- Задание 10: DNS сервер (bind) ---" "$YELLOW"
check_service "$HQ_SRV" "bind"

log_report "Прямые записи (A):"
check_dns_record "$HQ_SRV" "hq-rtr.au-team.irpo" "192.168.100.1"
check_dns_record "$HQ_SRV" "hq-srv.au-team.irpo" "192.168.100.2"
check_dns_record "$HQ_SRV" "br-rtr.au-team.irpo" "192.168.0.1"
check_dns_record "$HQ_SRV" "br-srv.au-team.irpo" "192.168.0.2"

log_report "Обратные записи (PTR):"
check_dns_ptr "$HQ_SRV" "192.168.100.1" "hq-rtr.au-team.irpo"
check_dns_ptr "$HQ_SRV" "192.168.100.2" "hq-srv.au-team.irpo"

# ============================================================
# ЗАДАНИЕ 11: Часовой пояс (ДОБАВЛЕН ISP)
# ============================================================
log_report ""
log_report "--- Задание 11: Часовой пояс ---" "$YELLOW"
check_task "$ISP" "Timezone Asia/Novosibirsk" "timedatectl | grep -q 'Asia/Novosibirsk'" "timedatectl | grep 'Time zone' | awk '{print \$3}'"
check_task "$HQ_RTR" "Timezone Asia/Novosibirsk" "timedatectl | grep -q 'Asia/Novosibirsk'" "timedatectl | grep 'Time zone' | awk '{print \$3}'"
check_task "$HQ_SRV" "Timezone Asia/Novosibirsk" "timedatectl | grep -q 'Asia/Novosibirsk'" "timedatectl | grep 'Time zone' | awk '{print \$3}'"
check_task "$HQ_CLI" "Timezone Asia/Novosibirsk" "timedatectl | grep -q 'Asia/Novosibirsk'" "timedatectl | grep 'Time zone' | awk '{print \$3}'"
check_task "$BR_RTR" "Timezone Asia/Novosibirsk" "timedatectl | grep -q 'Asia/Novosibirsk'" "timedatectl | grep 'Time zone' | awk '{print \$3}'"
check_task "$BR_SRV" "Timezone Asia/Novosibirsk" "timedatectl | grep -q 'Asia/Novosibirsk'" "timedatectl | grep 'Time zone' | awk '{print \$3}'"

# ============================================================
# ФИНАЛЬНАЯ СТАТИСТИКА
# ============================================================
log_report ""
log_report "=== СТАТИСТИКА ПРОВЕРКИ ===" "$YELLOW"

total_checks=$(grep -c '^\[' "$REPORT_FILE")
ok_checks=$(grep -c '^\[ OK \]' "$REPORT_FILE")
fail_checks=$(grep -c '^\[ FAIL \]' "$REPORT_FILE")

log_report "Всего проверок: $total_checks" "$BLUE"
log_report "Успешно: $ok_checks" "$GREEN"
log_report "Провалено: $fail_checks" "$RED"

if [[ $fail_checks -eq 0 ]]; then
    log_report "СТАТУС: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ УСПЕШНО!" "$GREEN"
else
    log_report "СТАТУС: ОБНАРУЖЕНЫ ПРОБЛЕМЫ (провалено ${fail_checks} проверок)" "$RED"
fi

log_report ""
log_report "=== ПРОВЕРКА ЗАВЕРШЕНА ===" "$YELLOW"
log_report "Отчет сохранен в: $REPORT_FILE" "$YELLOW"

echo ""
echo -e "${GREEN}Готово. Файл отчета: $REPORT_FILE${NC}"