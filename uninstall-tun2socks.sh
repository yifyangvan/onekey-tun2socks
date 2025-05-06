#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本，例如: sudo $0"
    exit 1
fi

SERVICE_FILE="/etc/systemd/system/tun2socks.service"
CONFIG_DIR="/etc/tun2socks"
BINARY_PATH="/usr/local/bin/tun2socks"

echo "正在停止并禁用 tun2socks 服务..."
if systemctl is-active --quiet tun2socks.service; then
    systemctl stop tun2socks.service
    echo "tun2socks 服务已停止。"
else
    echo "tun2socks 服务未在运行。"
fi

if systemctl is-enabled --quiet tun2socks.service; then
    systemctl disable tun2socks.service
    echo "tun2socks 服务已禁用开机自启。"
else
    echo "tun2socks 服务未设置开机自启。"
fi

echo "正在移除 systemd 服务文件..."
if [ -f "$SERVICE_FILE" ]; then
    rm -f "$SERVICE_FILE"
    echo "systemd 服务文件 ($SERVICE_FILE) 已删除。"
    echo "重新加载 systemd 配置..."
    systemctl daemon-reload
    echo "重置服务失败状态 (如果存在)..."
    systemctl reset-failed tun2socks.service &>/dev/null || true
else
    echo "systemd 服务文件 ($SERVICE_FILE) 未找到。"
fi

echo "正在移除配置文件和目录..."
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo "配置文件目录 ($CONFIG_DIR) 已删除。"
else
    echo "配置文件目录 ($CONFIG_DIR) 未找到。"
fi

echo "正在移除 tun2socks 二进制文件..."
if [ -f "$BINARY_PATH" ]; then
    rm -f "$BINARY_PATH"
    echo "tun2socks 二进制文件 ($BINARY_PATH) 已删除。"
else
    echo "tun2socks 二进制文件 ($BINARY_PATH) 未找到。"
fi

echo "卸载完成。"
