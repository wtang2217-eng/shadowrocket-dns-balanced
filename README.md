# Shadowrocket 日常高性能 + 加密分流 DNS 配置

这是一份可直接导入 Shadowrocket 的完整规则配置，基于 Johnshall 的 `sr_top500_whitelist_ad.conf`，补充稳定版可用的加密分流 DNS 与日常性能参数。它不是“所有 DNS 都跟随代理”的严格隐私配置。配置不含代理节点、订阅令牌或任何账号凭据。

## 直接导入

Raw 地址：

https://raw.githubusercontent.com/wtang2217-eng/shadowrocket-dns-balanced/main/sr_top500_whitelist_ad_dns_balanced.conf

在 Shadowrocket 中进入“配置”，点右上角“+”，粘贴上面的 Raw 地址并下载；选中它后，把首页“全局路由”设为“配置”，再断开并重新连接一次。

## 默认优化

- AliDNS 与 DNSPod 加密 DoH 并行解析，兼顾中国大陆 CDN 命中和日常延迟。
- 备用 DNS 只用 IP 字面量的加密 DoH，禁止回退到 iOS、路由器或运营商的系统 DNS。
- `dns-direct-system = false`，DIRECT 规则也不借用系统 DNS。
- `dns-direct-fallback-proxy = true`，直连解析失败时通过代理重试，提高弱网可用性。
- `hijack-dns` 只拦截常见公共 DNS 的 53 端口，不全局劫持局域网 DNS，兼顾 NAS、公司网络和认证门户。
- `block-quic = always-allow` 保留代理连接的 QUIC/HTTP/3，避免上传被强制回落到 TCP；需在 Shadowrocket 的设置、订阅和节点三处开启 UDP 转发。
- 默认关闭 IPv6，避免节点或网络未完整支持双栈时出现绕行与泄漏。
- 节点不支持 UDP 时直接拒绝，不让流量意外改道。
- 每次构建静态合并 AWAvenue `Only.Ads` 小型纯广告列表，并对 Johnshall 已有拒绝规则去重；不在手机端叠加大型远程广告集合。

## 海豚页面资源的取舍

海豚“周边产品 / Ruleset”页面列的是多平台资源导航，并不是所有项目都应同时加入：

- Loyalsoldier、MetaCubeX、CHIZI、DustinWin、SagerNet 的 `.dat`、`.mrs`、`.srs`、YAML、JSON 等分别面向 V2Ray、Mihomo 或 sing-box，不能直接作为 Shadowrocket 原生规则。
- blackmatrix7 的 Shadowrocket 专用文本可以按需使用；本配置保留 Johnshall 已带的 AppleNews 规则，不额外叠加约二十万条广告集合。
- anti-AD、217heidai 与 Cats-Team 都是优秀的大型替代源，但与现有广告规则高度重叠；全部叠加会增加下载、解析、内存与误杀。
- AWAvenue `Only.Ads` 只有约 606 条人工分类的纯广告规则，构建后通常只净增约 500 条，作为小型补强更适合性能档。
- Sub-Store、Sublink Worker、ConfigFlow、Script Hub、SubCase 和公共订阅转换站只处理订阅或格式，不提升 Shadowrocket 的运行时性能，因此不接入这份公开 Raw。

## 自动更新与防损坏

GitHub Actions 每天在 Johnshall 发布后自动执行：

1. 先用本地夹具测试构建器；
2. 下载 Johnshall 完整配置与 AWAvenue `Only.Ads`；
3. 校验必要区段、规则语法、最小规则数量和 UTF-8 无 BOM；
4. 只覆盖受管理的 DNS/性能项，保留其余上游配置；
5. 仅在生成物变化时提交。

如果上游返回 404、验证码页面、截断文件或规则数量异常，构建会失败并保留上一份可用配置。

本地复现：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BuildShadowrocketBalancedDns.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -OutputDirectory . -MinimumRuleCount 50000 -MinimumAddonRuleCount 500
```

## Shadowrocket 建议设置

节点延迟测试建议使用 `CONNECT` 方法；自动测速间隔可设为 600 秒、超时 5 秒、容差 50–100 ms，避免节点在微小延迟波动时频繁跳换。配置本身不包含节点，节点仍由你在 Shadowrocket 中单独添加或订阅。

日常均衡默认允许 QUIC。若节点不支持 UDP，配置仍会按 `udp-policy-not-supported-behaviour = REJECT` 拒绝 UDP，避免真实流量意外直连；此时应换用支持 UDP 的节点，而不是把回退改成 `DIRECT`。

## 安全边界

- 这是“日常均衡”的分流 DNS：DIRECT 域名使用本地加密 AliDNS/DNSPod，PROXY 域名由代理端解析。检测站显示 AliDNS、DNSPod、Cloudflare 或代理机房递归器并不等于运营商明文 DNS 泄漏，也不保证 DNS 与代理出口同地。
- `hijack-dns` 能接管硬编码的传统 UDP/TCP 53 查询，但不能普遍拦截应用自己实现的 DoH、DoT 或 DoQ。
- Shadowrocket 断开或 VPN 切换窗口不受本配置保护。
- DIRECT 网站仍能看到设备的真实出口 IP；DNS 防泄漏不等于所有流量匿名。
- 做 DNS 泄漏测试时，先临时关闭 iCloud Private Relay /“限制 IP 地址跟踪”，并同时测试 Wi-Fi 与蜂窝网络。
- 不要把私人订阅 URL 放进公共转换站或公开仓库；查询串中的 `url=` 只是可逆编码，不是加密。
- 上游包含 URL Rewrite / MITM 段；不安装证书也不影响主要分流和 DNS，但相关重写功能可能不会完整生效。

## 上游与许可

- [Johnshall/Shadowrocket-ADBlock-Rules-Forever](https://github.com/Johnshall/Shadowrocket-ADBlock-Rules-Forever)
- [LOWERTOP/Shadowrocket 手册](https://github.com/LOWERTOP/Shadowrocket/wiki/)
- [AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule)
- [海豚应用与规则资源导航](https://www.haitunt.org/app.html)
- [MetaCubeX/Mihomo 文档](https://wiki.metacubex.one/)

Johnshall 派生部分采用 CC BY-SA 4.0，AWAvenue `Only.Ads` 采用 GNU GPL v3。GNU GPL v3 是 CC BY-SA 4.0 的单向兼容许可证；组合生成物及本仓库新增构建代码按 GNU GPL v3 分发，同时保留各上游的归属和变更声明。

完整说明见 [NOTICE.md](NOTICE.md)，GNU GPL v3 正文见 [LICENSE](LICENSE)。
