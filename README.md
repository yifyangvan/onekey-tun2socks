# 一键添加Socks5 IPv4出口

以下命令适用于Alice的纯IPv6免费机，需确保Alice的DNS设置正确

```
curl -sSL https://raw.githubusercontent.com/hkfires/onekey-tun2socks/main/onekey-tun2socks-alice.sh | sudo bash
```

以下命令适用于LegendVPS的纯IPv6免费机，会自动更换DNS64进行下载，下载后会恢复为原先的DNS

```
curl -sSL https://raw.githubusercontent.com/hkfires/onekey-tun2socks/main/onekey-tun2socks-legend.sh | sudo bash
```