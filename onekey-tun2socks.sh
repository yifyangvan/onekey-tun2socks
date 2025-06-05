#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

error() {
    echo -e "${RED}[错误]${NC} $1"
}

step() {
    echo -e "${PURPLE}[步骤]${NC} $1"
}

if [ "$EUID" -ne 0 ]; then
    error "请使用 root 权限运行此脚本，例如: sudo $0"
    exit 1
fi

show_usage() {
    echo -e "${CYAN}使用方法:${NC} $0 [选项]"
    echo -e "${CYAN}选项:${NC}"
    echo -e "  ${GREEN}-i, --install${NC}    安装 tun2socks (可选参数: alice 或 legend)"
    echo -e "  ${GREEN}-u, --uninstall${NC}  卸载 tun2socks"
    echo -e "  ${GREEN}-h, --help${NC}       显示此帮助信息"
    echo
    echo -e "${CYAN}示例:${NC}"
    echo -e "  $0 -i alice    安装 Alice 版本的 tun2socks"
    echo -e "  $0 -i legend   安装 Legend 版本的 tun2socks"
    echo -e "  $0 -u          卸载 tun2socks"
}

INSTALL=false
UNINSTALL=false
MODE="alice"

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--install)
            INSTALL=true
            if [[ $2 != -* ]] && [[ -n $2 ]]; then
                MODE="$2"
                shift 2
            else
                shift
            fi
            ;;
        -u|--uninstall)
            UNINSTALL=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
done

if [ "$INSTALL" = false ] && [ "$UNINSTALL" = false ]; then
    error "请指定安装 (-i) 或卸载 (-u) 操作"
    show_usage
    exit 1
fi

uninstall_tun2socks() {
    SERVICE_FILE="/etc/systemd/system/tun2socks.service"
    CONFIG_DIR="/etc/tun2socks"
    BINARY_PATH="/usr/local/bin/tun2socks"

    step "正在停止并禁用 tun2socks 服务..."
    if systemctl is-active --quiet tun2socks.service; then
        systemctl stop tun2socks.service
        success "tun2socks 服务已停止。"
    else
        info "tun2socks 服务未在运行。"
    fi

    if systemctl is-enabled --quiet tun2socks.service; then
        systemctl disable tun2socks.service
        success "tun2socks 服务已禁用开机自启。"
    else
        info "tun2socks 服务未设置开机自启。"
    fi

    step "正在移除 systemd 服务文件..."
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        success "systemd 服务文件 ($SERVICE_FILE) 已删除。"
        info "重新加载 systemd 配置..."
        systemctl daemon-reload
        info "重置服务失败状态 (如果存在)..."
        systemctl reset-failed tun2socks.service &>/dev/null || true
    else
        warning "systemd 服务文件 ($SERVICE_FILE) 未找到。"
    fi

    step "正在移除配置文件和目录..."
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        success "配置文件目录 ($CONFIG_DIR) 已删除。"
    else
        warning "配置文件目录 ($CONFIG_DIR) 未找到。"
    fi

    step "正在移除 tun2socks 二进制文件..."
    if [ -f "$BINARY_PATH" ]; then
        rm -f "$BINARY_PATH"
        success "tun2socks 二进制文件 ($BINARY_PATH) 已删除。"
    else
        warning "tun2socks 二进制文件 ($BINARY_PATH) 未找到。"
    fi

    success "卸载完成。"
}

install_tun2socks() {
    RESOLV_CONF="/etc/resolv.conf"
    RESOLV_CONF_BAK="/etc/resolv.conf.bak"
    WAS_IMMUTABLE=false

    step "检查 /etc/resolv.conf 锁定状态..."
    if lsattr -d "$RESOLV_CONF" 2>/dev/null | grep -q -- '-i-'; then
        info "/etc/resolv.conf 文件当前被锁定 (immutable)，尝试解锁..."
        chattr -i "$RESOLV_CONF" || { error "无法解锁 /etc/resolv.conf，请检查权限。"; exit 1; }
        WAS_IMMUTABLE=true
        success "解锁成功。"
    else
        info "/etc/resolv.conf 未被锁定。"
    fi

    step "备份当前 DNS 配置..."
    cp "$RESOLV_CONF" "$RESOLV_CONF_BAK" || { warning "备份 DNS 配置失败，可能文件不存在或权限不足。"; }

    if [ "$MODE" = "alice" ]; then
        step "设置 Alice DNS64 服务器..."
        cat > "$RESOLV_CONF" <<EOF
nameserver 2602:fc59:b0:9e::64
nameserver 2a14:67c0:103:c::a
EOF
    else
        step "设置 Legend DNS64 服务器..."
        cat > "$RESOLV_CONF" <<EOF
nameserver 2602:fc59:b0:9e::64
EOF
    fi

    REPO="heiher/hev-socks5-tunnel"
    INSTALL_DIR="/usr/local/bin"
    CONFIG_DIR="/etc/tun2socks"
    SERVICE_FILE="/etc/systemd/system/tun2socks.service"
    BINARY_PATH="$INSTALL_DIR/tun2socks"

    step "获取最新版本下载链接..."
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep "browser_download_url" | grep "linux-x86_64" | cut -d '"' -f 4)

    if [ -z "$DOWNLOAD_URL" ]; then
        error "未找到适用于 linux-x86_64 的二进制文件下载链接，请检查网络或手动下载。"
        exit 1
    fi

    step "正在下载最新二进制文件："
    info "$DOWNLOAD_URL"
    trap 'warning "下载被中断或失败，尝试恢复 DNS..."; if [ -f "$RESOLV_CONF_BAK" ]; then mv "$RESOLV_CONF_BAK" "$RESOLV_CONF"; if [ "$WAS_IMMUTABLE" = true ]; then chattr +i "$RESOLV_CONF"; fi; else warning "未找到备份，无法恢复。"; if [ "$WAS_IMMUTABLE" = true ]; then chattr +i "$RESOLV_CONF"; fi; fi; exit 1' INT TERM EXIT
    curl -L -o "$BINARY_PATH" "$DOWNLOAD_URL"
    trap - INT TERM EXIT

    step "恢复原始 DNS 配置..."
    if [ -f "$RESOLV_CONF_BAK" ]; then
        mv "$RESOLV_CONF_BAK" "$RESOLV_CONF"
        success "DNS 配置已恢复。"

        if [ "$WAS_IMMUTABLE" = true ]; then
            info "重新锁定 /etc/resolv.conf..."
            chattr +i "$RESOLV_CONF" || warning "无法重新锁定 /etc/resolv.conf。"
            success "锁定完成。"
        fi
    else
        warning "未找到 DNS 备份文件 ($RESOLV_CONF_BAK)，无法自动恢复。"
        if [ "$WAS_IMMUTABLE" = true ]; then
             warning "尝试锁定当前的 /etc/resolv.conf (注意：内容可能不是原始配置)..."
             chattr +i "$RESOLV_CONF" || warning "无法锁定 /etc/resolv.conf。"
        fi
    fi

    chmod +x "$BINARY_PATH"

    step "创建配置文件..."
    mkdir -p "$CONFIG_DIR"
    CONFIG_FILE="$CONFIG_DIR/config.yaml"

    if [ "$MODE" = "alice" ]; then
        SOCKS_PORT=""
        while true; do
            info "请为 Alice 模式选择 SOCKS5 出口端口:"
            echo "  1) 香港机房IP (端口: 10000)"
            echo "  2) 香港家宽   (端口: 20000)"
            echo "  3) 台湾家宽   (端口: 30000)"
            echo "  4) 新加坡     (端口: 10001)"
            read -r -p "请输入选项 (1-4，默认为1): " port_choice

            case "$port_choice" in
                1|"")
                    SOCKS_PORT=10000
                    info "已选择端口: 10000 (香港机房IP)"
                    break
                    ;;
                2)
                    SOCKS_PORT=20000
                    info "已选择端口: 20000 (香港家宽)"
                    break
                    ;;
                3)
                    SOCKS_PORT=30000
                    info "已选择端口: 30000 (台湾家宽)"
                    break
                    ;;
                4)
                    SOCKS_PORT=10001
                    info "已选择端口: 10001 (新加坡)"
                    break
                    ;;
                *)
                    error "无效的选择，请输入 1, 2, 3, 或 4。"
                    ;;
            esac
        done

        cat > "$CONFIG_FILE" <<EOF
tunnel:
  name: tun0
  mtu: 8500
  multi-queue: true
  ipv4: 198.18.0.1

socks5:
  port: $SOCKS_PORT
  address: '2a14:67c0:116::1'
  udp: 'udp'
  username: 'alice'
  password: 'alicefofo123..OVO'
  mark: 438
EOF
    else
        cat > "$CONFIG_FILE" <<'EOF'
tunnel:
  name: tun0
  mtu: 8500
  multi-queue: true
  ipv4: 198.18.0.1

socks5:
  port: 8888
  address: '2001:db8:1234::6666'
  udp: 'udp'
  mark: 438
EOF
    fi

    step "生成 systemd 服务文件 (tun2socks.service)..."
    
    if [ "$MODE" = "alice" ]; then
        MAIN_IP=$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')
        RULE_ADD_FROM_MAIN_IP=""
        RULE_DEL_FROM_MAIN_IP=""

        if [ -n "$MAIN_IP" ]; then
            info "检测到 IPv4 地址: $MAIN_IP"
            info "将添加规则以允许源 IP 为 $MAIN_IP 的流量通过主路由表。"
            RULE_ADD_FROM_MAIN_IP="ExecStartPost=/sbin/ip rule add from $MAIN_IP lookup main pref 15"
            RULE_DEL_FROM_MAIN_IP="ExecStop=/sbin/ip rule del from $MAIN_IP lookup main pref 15"
        fi
    fi

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Tun2Socks Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=$BINARY_PATH $CONFIG_FILE

ExecStartPost=/sbin/ip rule add fwmark 438 lookup main pref 10
ExecStartPost=/sbin/ip -6 rule add fwmark 438 lookup main pref 10
ExecStartPost=/sbin/ip route add default dev tun0 table 20
ExecStartPost=/sbin/ip rule add lookup 20 pref 20
${RULE_ADD_FROM_MAIN_IP}

ExecStartPost=/sbin/ip rule del fwmark 438 lookup main pref 10
ExecStartPost=/sbin/ip -6 rule del fwmark 438 lookup main pref 10
ExecStop=/sbin/ip route del default dev tun0 table 20
ExecStop=/sbin/ip rule del lookup 20 pref 20
${RULE_DEL_FROM_MAIN_IP}

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    step "重新加载 systemd 配置..."
    systemctl daemon-reload

    step "设置服务开机自启动..."
    systemctl enable tun2socks.service

    step "启动服务..."
    systemctl start tun2socks.service

    success "安装完成！"
    echo
    info "服务管理命令："
    echo -e "  ${GREEN}查看状态${NC}：systemctl status tun2socks.service"
    echo -e "  ${GREEN}启动服务${NC}：systemctl start tun2socks.service"
    echo -e "  ${GREEN}停止服务${NC}：systemctl stop tun2socks.service"
    echo -e "  ${GREEN}重启服务${NC}：systemctl restart tun2socks.service"
    echo -e "  ${GREEN}查看日志${NC}：journalctl -u tun2socks.service"
    echo -e "  ${GREEN}实时查看日志${NC}：journalctl -u tun2socks.service -f"
    echo
    info "配置文件位置："
    echo -e "  ${GREEN}服务配置${NC}：/etc/systemd/system/tun2socks.service"
    echo -e "  ${GREEN}程序配置${NC}：/etc/tun2socks/config.yaml"
    echo -e "  ${GREEN}程序位置${NC}：/usr/local/bin/tun2socks"
    echo
    info "如需卸载，请运行：$0 -u"
}

if [ "$UNINSTALL" = true ]; then
    uninstall_tun2socks
fi

if [ "$INSTALL" = true ]; then
    if [ "$MODE" != "alice" ] && [ "$MODE" != "legend" ]; then
        error "无效的安装模式 '$MODE'，请使用 'alice' 或 'legend'"
        exit 1
    fi
    install_tun2socks
fi
