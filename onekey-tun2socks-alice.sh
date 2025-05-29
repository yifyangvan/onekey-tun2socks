#!/bin/bash
set -e

# 检查是否以 root 身份运行

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本，例如: sudo $0"
    exit 1
fi

RESOLV_CONF="/etc/resolv.conf"
RESOLV_CONF_BAK="/etc/resolv.conf.bak"
WAS_IMMUTABLE=false

echo "检查 /etc/resolv.conf 锁定状态..."
if lsattr -d "$RESOLV_CONF" 2>/dev/null | grep -q -- '-i-'; then
    echo "/etc/resolv.conf 文件当前被锁定 (immutable)，尝试解锁..."
    chattr -i "$RESOLV_CONF" || { echo "错误：无法解锁 /etc/resolv.conf，请检查权限。"; exit 1; }
    WAS_IMMUTABLE=true
    echo "解锁成功。"
else
    echo "/etc/resolv.conf 未被锁定。"
fi

echo "备份当前 DNS 配置..."
cp "$RESOLV_CONF" "$RESOLV_CONF_BAK" || { echo "警告：备份 DNS 配置失败，可能文件不存在或权限不足。"; }

echo "设置 Alice DNS64 服务器..."
cat > "$RESOLV_CONF" <<EOF
nameserver 2602:fc59:b0:9e::64
nameserver 2a14:67c0:103:c::a
EOF

# 配置参数

REPO="heiher/hev-socks5-tunnel"

# 获取最新版本 linux-x86_64 二进制下载链接

DOWNLOAD_URL=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep "browser_download_url" | grep "linux-x86_64" | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "未找到适用于 linux-x86_64 的二进制文件下载链接，请检查网络或手动下载。"
    exit 1
fi

# 定义安装路径和文件位置

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/tun2socks"
SERVICE_FILE="/etc/systemd/system/tun2socks.service"
BINARY_PATH="$INSTALL_DIR/tun2socks"

echo "正在下载最新二进制文件："
echo "$DOWNLOAD_URL"
# 使用 trap 确保即使 curl 失败或被中断也能尝试恢复 DNS 和锁定状态
trap 'echo "下载被中断或失败，尝试恢复 DNS..."; if [ -f "$RESOLV_CONF_BAK" ]; then mv "$RESOLV_CONF_BAK" "$RESOLV_CONF"; if [ "$WAS_IMMUTABLE" = true ]; then chattr +i "$RESOLV_CONF"; fi; else echo "警告：未找到备份，无法恢复。"; if [ "$WAS_IMMUTABLE" = true ]; then chattr +i "$RESOLV_CONF"; fi; fi; exit 1' INT TERM EXIT
curl -L -o "$BINARY_PATH" "$DOWNLOAD_URL"
# 下载成功后清除 trap
trap - INT TERM EXIT


echo "恢复原始 DNS 配置..."
if [ -f "$RESOLV_CONF_BAK" ]; then
    mv "$RESOLV_CONF_BAK" "$RESOLV_CONF"
    echo "DNS 配置已恢复。"

    # 如果原来是锁定的，重新锁定
    if [ "$WAS_IMMUTABLE" = true ]; then
        echo "重新锁定 /etc/resolv.conf..."
        chattr +i "$RESOLV_CONF" || echo "警告：无法重新锁定 /etc/resolv.conf。"
        echo "锁定完成。"
    fi
else
    echo "警告：未找到 DNS 备份文件 ($RESOLV_CONF_BAK)，无法自动恢复。"
    if [ "$WAS_IMMUTABLE" = true ]; then
         echo "尝试锁定当前的 /etc/resolv.conf (注意：内容可能不是原始配置)..."
         chattr +i "$RESOLV_CONF" || echo "警告：无法锁定 /etc/resolv.conf。"
    fi
fi

chmod +x "$BINARY_PATH"

echo "创建配置文件..."
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
cat > "$CONFIG_FILE" <<'EOF'
tunnel:
  name: tun0
  mtu: 8500
  multi-queue: true
  ipv4: 198.18.0.1

socks5:
  port: 40000
  address: '2a14:67c0:100::af'
  udp: 'udp'
  username: 'alice'
  password: 'alicefofo123..@'
  mark: 438
EOF

echo "生成 systemd 服务文件 (tun2socks.service)..."
MAIN_IP=$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')
RULE_ADD_FROM_MAIN_IP=""
RULE_DEL_FROM_MAIN_IP=""

if [ -n "$MAIN_IP" ]; then
    echo "检测到 IPv4 地址: $MAIN_IP"
    echo "将添加规则以允许源 IP 为 $MAIN_IP 的流量通过主路由表。"
    # 定义要插入的规则行
    RULE_ADD_FROM_MAIN_IP="ExecStartPost=/sbin/ip rule add from $MAIN_IP lookup main pref 15"
    RULE_DEL_FROM_MAIN_IP="ExecStop=/sbin/ip rule del from $MAIN_IP lookup main pref 15"
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Tun2Socks Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=$BINARY_PATH $CONFIG_FILE

ExecStartPost=/sbin/ip -6 rule add fwmark 438 lookup main pref 10
ExecStartPost=/sbin/ip route add default dev tun0 table 20
ExecStartPost=/sbin/ip rule add lookup 20 pref 20
$RULE_ADD_FROM_MAIN_IP

ExecStop=/sbin/ip -6 rule del fwmark 438 lookup main pref 10
ExecStop=/sbin/ip route del default dev tun0 table 20
ExecStop=/sbin/ip rule del lookup 20 pref 20
$RULE_DEL_FROM_MAIN_IP

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "重新加载 systemd 配置..."
systemctl daemon-reload

echo "设置服务开机自启动..."
systemctl enable tun2socks.service

echo "启动服务..."
systemctl start tun2socks.service

echo "安装完成！您可以使用 'systemctl status tun2socks.service' 查看服务状态。"
