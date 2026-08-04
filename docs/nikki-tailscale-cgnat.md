# Nikki 路由器代理与 Tailscale CGNAT 地址冲突排障

本文记录 `home` 路由器执行 `opkg update` 失败时的诊断结论、验证方法和处理方案。

## 问题结论

这次故障不是软件源配置错误，也不是 Tailscale 地址配置错误，而是运营商分配的 CGNAT 地址与 Tailscale 使用的地址段重叠。

| 项目 | 地址 |
| --- | --- |
| `home` WAN/PPPoE | `100.69.240.221` |
| `home` Tailscale | `100.88.61.53` |
| Tailscale 地址段 | `100.64.0.0/10` |

`100.69.240.221` 是运营商分配的 WAN 地址，不是 Tailscale 地址，但它同样落在 `100.64.0.0/10` 内。Tailscale 的反欺骗规则因此把被本机代理重定向后的连接误判为来自非 `tailscale0` 接口的伪造 Tailscale 地址。

实际丢包规则为：

```text
iifname != "tailscale0*" ip saddr 100.64.0.0/10 drop
```

诊断时该规则累计丢弃了 `2120` 个包；计数器会随运行时间变化。

## 数据包路径

```text
opkg 发起连接
  -> 使用 PPPoE 地址 100.69.240.221 作为源地址
  -> Nikki“路由器代理”将连接 REDIRECT 到本地 :7891
  -> 数据包从 lo 进入 INPUT
  -> Tailscale 发现源地址属于 100.64.0.0/10，但入口不是 tailscale0
  -> ts-input 反欺骗规则 DROP
```

`company` 路由器没有出现同样的问题，是因为它的 WAN 地址为 `192.168.0.121`，不在 Tailscale 地址段内。两台路由器的软件版本和相关规则基本一致，差异主要在 WAN 地址。

## 方案一：关闭路由器本机代理

这是不要求路由器自身流量经过代理时的首选方案，简单且稳定。

LuCI 路径：

```text
Nikki -> 代理配置 -> 路由器代理 -> 取消“启用”
```

该设置只关闭路由器自身的透明代理，`opkg`、`wget`、`curl` 等本机进程会直接从 WAN 发出。“局域网代理”是独立开关，电脑和手机仍可继续使用 Nikki。

命令行对应操作：

```sh
uci set nikki.proxy.router_proxy='0'
uci commit nikki
/etc/init.d/nikki restart
```

恢复路由器本机代理：

```sh
uci set nikki.proxy.router_proxy='1'
uci commit nikki
/etc/init.d/nikki restart
```

## 方案二：保留本机代理并放行当前 WAN 地址

如果必须让路由器本机流量经过 Nikki，可以在 `ts-input` 的 DROP 规则前，精确放行：

- 入口接口为 `lo`；
- 源地址为当前 PPPoE WAN 地址；
- 只放行当前地址的 `/32`，不放行整个 `100.64.0.0/10`。

临时验证命令：

```sh
WAN_IP="$(ip -4 route get 1.1.1.1 | sed -n 's/.* src \([^ ]*\).*/\1/p')"

iptables -I ts-input 1 \
  -i lo \
  -s "$WAN_IP/32" \
  -m comment --comment allow-local-cgnat-redirect \
  -j ACCEPT
```

确认规则顺序：

```sh
iptables -nvL ts-input --line-numbers
```

临时规则应位于反欺骗 DROP 规则之前。然后测试：

```sh
opkg update
nft list chain ip filter ts-input
```

上述插入方式用于验证，重启 Nikki、Tailscale 或重新加载防火墙后可能丢失。正式使用时应做成 WAN hotplug 脚本，动态读取 PPPoE 地址，并在 Tailscale 启动或重建 `ts-input` 规则后重新插入。由于 PPPoE 地址可能变化，不能把当前地址永久硬编码。

## Nikki 访问控制的边界

Nikki 的“路由器代理 -> 访问控制”可以按用户、用户组和 cgroup 决定本机进程走代理或绕过。当前配置大致为：

```text
dnsmasq、sysntpd、tailscale 等系统服务 -> 绕过
其他本机进程 -> 默认代理
```

`opkg` 以 root 运行，且没有独立 cgroup。把 root 加入绕过规则虽然可以让 `opkg` 直连，但也会放过大量其他系统进程，范围太大。因此这不是本故障的精确修复，不建议优先采用。

## 建议

- 不要求路由器本机走代理：关闭“路由器代理”，采用方案一。
- 必须让路由器本机走代理：采用方案二，并只放行当前 WAN `/32`。
- 只是偶尔运行 `opkg update`：更新前临时关闭“路由器代理”，完成后再恢复。
- 不要为方便而放行整个 `100.64.0.0/10`，否则会削弱 Tailscale 的反欺骗保护。

截至本文记录时，只进行了只读诊断和页面查看，尚未修改路由器配置。
