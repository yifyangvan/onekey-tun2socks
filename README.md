# 给免费机一键添加Socks5 IPv4出口

## 快速开始

### 以下命令适用于Alice的纯IPv6免费机
```bash
curl -L https://raw.githubusercontent.com/hkfires/onekey-tun2socks/main/onekey-tun2socks.sh -o onekey-tun2socks.sh && chmod +x onekey-tun2socks.sh && sudo ./onekey-tun2socks.sh -i alice
```

### 注意事项
有IPv4的Alice机型使用Alice家宽Socks5出口时，需手动修改DNS（建议使用Alice V6的解锁DNS），由于家宽IP不在Alice V4 DNS的白名单内，会导致解析失败；机房Socks5出口不受此影响。

### 以下命令适用于LegendVPS的纯IPv6免费机
```bash
curl -L https://raw.githubusercontent.com/hkfires/onekey-tun2socks/main/onekey-tun2socks.sh -o onekey-tun2socks.sh && chmod +x onekey-tun2socks.sh && sudo ./onekey-tun2socks.sh -i legend
```

### 卸载
```bash
curl -L https://raw.githubusercontent.com/hkfires/onekey-tun2socks/main/onekey-tun2socks.sh -o onekey-tun2socks.sh && chmod +x onekey-tun2socks.sh && sudo ./onekey-tun2socks.sh -u
```

## 手动下载运行

1. 下载脚本：
```bash
curl -L https://raw.githubusercontent.com/hkfires/onekey-tun2socks/main/onekey-tun2socks.sh -o onekey-tun2socks.sh
```

2. 添加执行权限：
```bash
chmod +x onekey-tun2socks.sh
```

3. 查看帮助信息：
```bash
./onekey-tun2socks.sh -h
```

4. 运行脚本：
```bash
# 安装 Alice 版本
sudo ./onekey-tun2socks.sh -i alice

# 安装 Legend 版本
sudo ./onekey-tun2socks.sh -i legend

# 变更 Alice 出口
sudo ./onekey-tun2socks.sh -s

# 卸载
sudo ./onekey-tun2socks.sh -u
```

## 服务管理

安装完成后，可以使用以下命令管理服务：

```bash
# 查看服务状态
systemctl status tun2socks.service

# 启动服务
systemctl start tun2socks.service

# 停止服务
systemctl stop tun2socks.service

# 重启服务
systemctl restart tun2socks.service

# 查看日志
journalctl -u tun2socks.service
```