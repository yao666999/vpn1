#!/bin/bash
#===============================================================
# Pi Network VPN 安装脚本 - 优化版
# 功能：自动安装并配置 SoftEther VPN 和 FRPS 服务
#===============================================================

# 颜色定义
LIGHT_GREEN='\033[1;32m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置参数
## VPN配置
ADMIN_PASSWORD="123Qaz123456!"
VPN_HUB="DEFAULT"
VPN_USER="pi"
VPN_PASSWORD="45rtygfqewuvh"
## DHCP配置
DHCP_START="192.168.30.10"
DHCP_END="192.168.30.20"
DHCP_MASK="255.255.255.0"
DHCP_GW="192.168.30.1"
DHCP_DNS1="192.168.30.1"
DHCP_DNS2="8.8.8.8"
## FRPS配置
FRPS_PORT="7000"
FRPS_UDP_PORT="7001"
FRPS_KCP_PORT="7002"
FRPS_DASHBOARD_PORT="31410"
FRPS_TOKEN="2345tfghjhfqfv"
FRPS_DASHBOARD_USER="admin"
FRPS_DASHBOARD_PWD="admin"
## 软件版本
SOFTETHER_VERSION="v4.41-9782-beta"
SOFTETHER_DATE="2022.11.17"
FRP_VERSION="v0.44.0"

# 静默模式标志
SILENT_MODE=true

# 日志函数
log_info() {
    # 子步骤静默处理
    if [[ "$SILENT_MODE" == "true" ]]; then
        return
    fi
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_step() {
    # 主要步骤始终显示
    echo -e "${YELLOW}[$1/$2] $3${NC}"
}

log_success() {
    # 成功信息始终显示
    echo -e "${GREEN}[成功]${NC} $1"
}

log_error() {
    # 错误信息始终显示
    echo -e "${RED}[错误]${NC} $1"
    exit 1
}

log_sub_step() {
    # 子步骤静默处理
    if [[ "$SILENT_MODE" == "true" ]]; then
        return
    fi
    echo -e "${GREEN}[$1/$2]$3${NC}"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 或 root 权限运行脚本"
    fi
}

# 卸载系统监控服务
uninstall_monitoring() {
    log_step "1" "7" "卸载系统监控服务..."
    
    # 停止并禁用服务
    systemctl stop uniagent.service hostguard.service >/dev/null 2>&1
    systemctl disable uniagent.service hostguard.service >/dev/null 2>&1
    
    # 删除服务文件
    rm -f /etc/systemd/system/uniagent.service
    rm -f /etc/systemd/system/hostguard.service
    
    # 重载守护进程
    systemctl daemon-reexec >/dev/null 2>&1
    systemctl daemon-reload >/dev/null 2>&1
    
    # 结束进程
    pkill -9 uniagentd 2>/dev/null || true
    pkill -9 hostguard 2>/dev/null || true
    pkill -9 uniagent 2>/dev/null || true
    
    # 删除文件
    rm -rf /usr/local/uniagent
    rm -rf /usr/local/hostguard
    rm -rf /usr/local/uniag
    rm -rf /var/log/uniagent /etc/uniagent /usr/bin/uniagentd
    
    log_success "监控服务卸载完成"
}

# 安装依赖
install_dependencies() {
    log_step "2" "7" "安装编译工具和依赖..."
    
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || log_error "更新软件源失败"
    apt-get install -y -qq build-essential libreadline-dev zlib1g-dev wget >/dev/null 2>&1 || log_error "安装依赖失败"
    
    log_success "依赖安装完成"
}

# 安装SoftEther VPN
install_softether() {
    log_step "3" "7" "安装SoftEther VPN..."
    
    # 如果已存在，先停止并删除
    if [ -d "/usr/local/vpnserver" ]; then
        /usr/local/vpnserver/vpnserver stop >/dev/null 2>&1
        rm -rf /usr/local/vpnserver
    fi
    
    # 下载和安装
    cd /usr/local/ || log_error "无法进入/usr/local目录"
    
    local SOFTETHER_FILE="softether-vpnserver-${SOFTETHER_VERSION}-${SOFTETHER_DATE}-linux-x64-64bit.tar.gz"
    log_info "下载SoftEther VPN..."
    wget -q "https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/${SOFTETHER_VERSION}/${SOFTETHER_FILE}" >/dev/null 2>&1 || log_error "下载SoftEther VPN失败"
    
    log_info "解压并编译SoftEther VPN..."
    tar -zxf ${SOFTETHER_FILE} >/dev/null 2>&1 || log_error "解压SoftEther VPN失败"
    cd vpnserver || log_error "无法进入vpnserver目录"
    make -j$(nproc) >/dev/null 2>&1 || log_error "编译SoftEther VPN失败"
    
    # 启动VPN服务器
    log_info "启动VPN服务器..."
    /usr/local/vpnserver/vpnserver start >/dev/null 2>&1 || log_error "启动VPN服务器失败"
    sleep 3
    
    # 配置VPN服务器
    configure_vpn
    
    # 创建systemd服务
    create_vpn_service
    
    log_success "SoftEther VPN安装与配置完成"
}

# 配置VPN服务器
configure_vpn() {
    log_info "配置VPN服务器..."
    local VPNCMD="/usr/local/vpnserver/vpncmd"
    
    # 设置管理密码
    log_sub_step "1" "8" "设置管理密码..."
    ${VPNCMD} localhost /SERVER /CMD ServerPasswordSet ${ADMIN_PASSWORD} >/dev/null 2>&1
    
    # 删除旧的HUB
    log_sub_step "2" "8" "删除旧的HUB..."
    ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD HubDelete ${VPN_HUB} >/dev/null 2>&1 || true
    
    # 创建新的HUB - 去掉不支持的/YES参数
    log_sub_step "3" "8" "创建新的HUB..."
    { sleep 2; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD HubCreate ${VPN_HUB} /PASSWORD:${ADMIN_PASSWORD} >/dev/null 2>&1
    
    # 启用Secure NAT
    log_sub_step "4" "8" "启用Secure NAT..."
    { sleep 2; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD SecureNatEnable >/dev/null 2>&1
    
    # 设置SecureNAT
    log_sub_step "5" "8" "设置SecureNAT..."
    { sleep 2; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD DhcpSet \
        /START:${DHCP_START} /END:${DHCP_END} /MASK:${DHCP_MASK} /EXPIRE:2000000 \
        /GW:${DHCP_GW} /DNS:${DHCP_DNS1} /DNS2:${DHCP_DNS2} /DOMAIN:none /LOG:no >/dev/null 2>&1
    
    # 创建用户
    log_sub_step "6" "8" "创建用户名..."
    { sleep 2; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} \
        /CMD UserCreate ${VPN_USER} /GROUP:none /REALNAME:none /NOTE:none >/dev/null 2>&1
    
    # 设置用户密码
    log_sub_step "7" "8" "创建用户密码..."
    { sleep 2; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} \
        /CMD UserPasswordSet ${VPN_USER} /PASSWORD:${VPN_PASSWORD} >/dev/null 2>&1
    
    # 禁用所有日志
    log_sub_step "8" "8" "禁用所有日志..."
    { sleep 2; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable packet >/dev/null 2>&1
    { sleep 2; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable security >/dev/null 2>&1
}

# 创建VPN服务
create_vpn_service() {
    log_info "创建VPN服务..."
    
    cat > /etc/systemd/system/vpn.service <<EOF
[Unit]
Description=SoftEther VPN Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStop=/usr/local/vpnserver/vpnserver stop
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now vpn >/dev/null 2>&1 || log_error "启用VPN服务失败"
}

# 卸载FRPS服务
uninstall_frps() {
    log_info "卸载FRPS服务..."
    
    # 停止并禁用FRPS服务
    systemctl stop frps >/dev/null 2>&1 || true
    systemctl disable frps >/dev/null 2>&1 || true
    
    # 删除服务文件
    rm -f /etc/systemd/system/frps.service
    
    # 删除FRPS二进制文件和配置文件
    rm -rf /usr/local/frp
    rm -rf /etc/frp
    
    # 重载守护进程
    systemctl daemon-reload >/dev/null 2>&1
    
}

# 安装FRPS服务
install_frps() {
    log_step "4" "7" "安装FRPS服务..."
    
    # 先卸载FRPS服务
    uninstall_frps
    
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    
    cd /usr/local/ || log_error "无法进入/usr/local目录"
    
    # 下载和解压
    log_info "下载FRPS..."
    wget -q "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" >/dev/null 2>&1 || log_error "下载FRPS失败"
    
    log_info "安装FRPS..."
    tar -zxf ${FRP_FILE} >/dev/null 2>&1 || log_error "解压FRPS失败"
    cd ${FRP_NAME} || log_error "无法进入FRPS目录"
    
    mkdir -p /usr/local/frp
    cp frps /usr/local/frp/ >/dev/null 2>&1 || log_error "复制FRPS二进制文件失败"
    chmod +x /usr/local/frp/frps
    
    # 创建配置文件
    mkdir -p /etc/frp
    cat > /etc/frp/frps.ini <<EOF
[common]
bind_addr = 0.0.0.0
bind_port = ${FRPS_PORT}
bind_udp_port = ${FRPS_UDP_PORT}
kcp_bind_port = ${FRPS_KCP_PORT}
dashboard_addr = 0.0.0.0
dashboard_port = ${FRPS_DASHBOARD_PORT}
authentication_method = token
token = ${FRPS_TOKEN}
dashboard_user = ${FRPS_DASHBOARD_USER}
dashboard_pwd = ${FRPS_DASHBOARD_PWD}
log_level = silent
disable_log_color = true
EOF
    
    # 创建服务
    cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/frp/frps -c /etc/frp/frps.ini
Restart=on-failure
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now frps >/dev/null 2>&1 || log_error "启用FRPS服务失败"
    log_success "FRPS 安装完成并启动成功"
}

# 安装BBR
install_bbr() {
    log_step "5" "7" "安装BBR并选择BBR+CAKE加速模块..."
    
    cd /usr/local/ || log_error "无法进入/usr/local目录"
    wget --no-check-certificate -q -O tcpx.sh https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh >/dev/null 2>&1 || log_error "下载BBR脚本失败"
    chmod +x tcpx.sh
    echo -e "13" | ./tcpx.sh >/dev/null 2>&1
    
    log_success "BBR安装完成"
}

# 设置定时维护
setup_maintenance() {
    log_step "6" "7" "设置定时维护..."
    
    cat > /etc/systemd/system/monthly-reboot.service <<EOF
[Unit]
Description=Monthly Reboot

[Service]
Type=oneshot
ExecStart=/sbin/reboot
EOF
    
    cat > /etc/systemd/system/monthly-reboot.timer <<EOF
[Unit]
Description=Monthly Reboot Timer

[Timer]
OnCalendar=*-*-1 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now monthly-reboot.timer >/dev/null 2>&1 || log_error "启用定时维护失败"
    
    log_success "定时维护设置完成"
}

# 清理临时文件
cleanup() {
    log_step "7" "7" "清理临时缓存文件..."
    
    rm -rf /usr/local/frp_* /usr/local/softether-vpnserver-v4* /usr/local/frp_*_linux_amd64
    rm -rf /usr/local/vpnserver/packet_log /usr/local/vpnserver/security_log /usr/local/vpnserver/server_log
    
    log_success "临时文件清理完成"
}

# 显示安装结果
show_results() {
    echo -e "\n${YELLOW}>>> SoftEtherVPN & FRPS服务状态：${NC}"
    systemctl is-active vpn
    systemctl is-active frps
    
    echo -e "\n${YELLOW}>>> BBR加速状态：${NC}"
    sysctl net.ipv4.tcp_congestion_control | awk '{print $3}'
    
    echo -e "\n${YELLOW}>>> VPN信息：${NC}"
    echo -e "服务器地址: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    echo -e "VPN 服务密码: ${ADMIN_PASSWORD}"
    echo -e "VPN 用户名: ${VPN_USER}"
    echo -e "VPN 密码: ${VPN_PASSWORD}"
    echo -e "FRPS 密码: ${FRPS_TOKEN}"
    
    echo -e "\n${LIGHT_GREEN}✅ 安装已完成 - 脚本运行成功！${NC}"
}

# 主函数
main() {
    check_root
    uninstall_monitoring
    install_dependencies
    install_softether
    install_frps
    install_bbr
    setup_maintenance
    cleanup
    show_results
}

# 执行主函数
main
