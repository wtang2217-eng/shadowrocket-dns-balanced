# Shadowrocket 高性能分流与严格 DNS 配置

本仓库提供两份可直接导入 Shadowrocket 的完整配置，规则基于 Johnshall 的 `sr_top500_whitelist_ad.conf`。配置不包含代理节点、订阅令牌或任何账号凭据。

## 直接导入

严格 DNS 版（业务 DNS 经代理，推荐隐私优先）：

https://raw.githubusercontent.com/wtang2217-eng/shadowrocket-dns-balanced/main/sr_top500_whitelist_ad_dns_strict.conf

日常均衡版（本地加密 DNS，推荐中国大陆 CDN 与兼容性优先）：

https://raw.githubusercontent.com/wtang2217-eng/shadowrocket-dns-balanced/main/sr_top500_whitelist_ad_dns_balanced.conf

在 Shadowrocket 中进入“配置”，点右上角“+”，粘贴 Raw 地址并下载；选中配置后，把首页“全局路由”设为“配置”，再断开并重新连接一次。

## 两种 DNS 模式

严格版：

- 本机需要解析的业务域名使用 Cloudflare IP DoH，经默认代理发送；备用 Google IP DoH 同样经代理，绝不回退 `system`。
- `proxy-dns-server` 使用 AliDNS IP DoH 加密直连，只负责在代理尚未建立时解析节点域名，避免“先有代理还是先解析节点”的循环。
- 删除已弃用的 `bypass-system` 和旧 `bypass-tun`，不依赖系统 DNS。
- 代理不可用时 DNS 也可能不可用，这是严格模式的 fail-closed 行为。

均衡版：

- DIRECT 域名使用 AliDNS/DNSPod 加密 DoH，兼顾中国大陆 CDN 命中与日常延迟。
- PROXY 域名通常由代理服务器远端解析。
- 检测站显示 AliDNS、DNSPod、Cloudflare 或代理机房递归器，不等同于运营商明文 DNS 泄漏，但 DNS 不保证与代理出口同地。

两版都使用 `dns-direct-system = false`、非系统备用 DNS、`block-quic = always-allow` 与 `udp-policy-not-supported-behaviour = REJECT`。支持 UDP 的节点可使用 QUIC/HTTP/3；节点不支持 UDP 时不会偷偷改为直连。

## 上传性能说明

规则配置不会给上传设置 Mbps 上限。若 Speedtest 出现下载正常、上传接近固定的 5 Mbps，同时负载延迟显著升高，优先检查节点或机场上行限速、Hysteria v1 的 `upmbps`、代理链、线路拥塞；WireGuard 节点再单独测试 MTU。

Shadowrocket 的“设置 → UDP”、订阅详情、节点详情三处都需要开启 UDP 转发。不要把 `udp-policy-not-supported-behaviour` 改成 `DIRECT`，否则 UDP 可能暴露真实出口。

## 规则与广告过滤

- 每次构建静态合并 AWAvenue `Only.Ads` 小型纯广告列表，并与 Johnshall 现有拒绝规则语义去重。
- 不叠加 anti-AD、217heidai、Cats-Team 等十万级大型集合，避免增加下载、内存、误杀和编译负担。
- Loyalsoldier、MetaCubeX、CHIZI、DustinWin、SagerNet 的 `.dat`、`.mrs`、`.srs`、YAML、JSON 等并非 Shadowrocket 原生完整配置格式，不直接混入。
- Sub-Store、Sublink Worker、ConfigFlow、Script Hub、SubCase 与公共订阅转换站只处理订阅或格式，不提升 Shadowrocket 运行时吞吐。

## 自动更新与防损坏

GitHub Actions 每天执行：

1. 用本地夹具测试构建器；
2. 下载 Johnshall 完整配置与 AWAvenue `Only.Ads`；
3. 校验必要区段、规则规模、Strict/ Balanced DNS 参数和 UTF-8 无 BOM；
4. 同时生成均衡版、严格版与扩展配置；
5. 只在生成物发生变化时提交。

如果上游返回 404、验证码页面、截断文件或规则数量异常，构建会失败并保留上一份可用配置。

本地复现：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BuildShadowrocketBalancedDns.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -OutputDirectory . -MinimumRuleCount 50000 -MinimumAddonRuleCount 500
```

## 安全边界

- 严格版的准确承诺是：所有由 Shadowrocket 本机管理的业务 DNS 不使用系统 DNS，并经代理发送；代理类域名仍可能由节点远端 DNS 解析。
- 若节点地址是域名，节点启动解析会使用直连但加密的 `proxy-dns-server`；节点地址本身使用 IP 才能消除此例外。
- `hijack-dns` 只能接管列出的传统 UDP/TCP 53 DNS，不能普遍强制第三方 App 放弃自带 DoH、DoT、DoQ 或 iCloud Private Relay。
- Shadowrocket 断开或 VPN 切换窗口不受配置保护；DIRECT 网站仍能看到设备真实出口 IP。
- DNS 检测页显示的是递归解析器，不是代理出口 IP；两者地址不同本身不能证明泄漏。
- 排障时请临时关闭 iCloud Private Relay、“限制 IP 地址跟踪”和其他 DNS/VPN 描述文件，再同时检查检测页与 Shadowrocket“数据 → DNS”日志。
- 不要把私人订阅 URL 放进公共转换站或公开仓库；查询串中的 `url=` 只是可逆编码，不是加密。

## 上游与许可

- [Johnshall/Shadowrocket-ADBlock-Rules-Forever](https://github.com/Johnshall/Shadowrocket-ADBlock-Rules-Forever)
- [LOWERTOP/Shadowrocket 手册](https://github.com/LOWERTOP/Shadowrocket/wiki/)
- [AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule)
- [海豚应用与规则资源导航](https://www.haitunt.org/app.html)
- [MetaCubeX/Mihomo 文档](https://wiki.metacubex.one/)

Johnshall 派生部分采用 CC BY-SA 4.0，AWAvenue `Only.Ads` 采用 GNU GPL v3。组合生成物及本仓库新增构建代码按 GNU GPL v3 分发，同时保留各上游归属和变更声明。

完整说明见 [NOTICE.md](NOTICE.md)，GNU GPL v3 正文见 [LICENSE](LICENSE)。
