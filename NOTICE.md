# 第三方来源与变更说明

本仓库的生成配置整合了以下公开来源：

1. [Johnshall/Shadowrocket-ADBlock-Rules-Forever](https://github.com/Johnshall/Shadowrocket-ADBlock-Rules-Forever)，原始规则采用 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)。
2. [TG-Twilight/AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule)，`Only.Ads` 规则采用 [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.html)。

2026-08-15 的主要改动：

- 为 Shadowrocket 稳定版增加加密 DNS、显式加密备用 DNS、DIRECT 禁用系统 DNS、常见公共 Do53 劫持和代理侧 QUIC 控制。
- 构建时静态拉取 AWAvenue `Only.Ads`，仅接受三类 Shadowrocket 域名规则，转为 `REJECT` 并依据现有拒绝后缀语义去重。
- 增加规则数量、格式、幂等、编码和截断保护，以及每日 GitHub Actions 自动刷新。
- 未加入代理节点、订阅令牌、账号凭据或公共订阅转换服务。

GNU GPL v3 已被 Creative Commons 列为 CC BY-SA 4.0 的单向兼容许可证。组合生成物与本仓库新增构建代码按 GNU GPL v3 分发；各上游部分仍保留其原始归属、许可声明和变更说明。本仓库与上述项目作者不存在官方隶属或背书关系。
