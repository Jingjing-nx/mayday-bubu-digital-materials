# 隐私说明

## 仓库与发布包不包含

- 作者或测试者的本机用户名、邮箱、主目录和绝对路径；
- GitHub Token、API Key、Cookie、密码或其他访问凭据；
- Codex 聊天内容、账号缓存、真实额度百分比或重置时间；
- 安装测试产生的日志、健康状态文件和诊断报告。

## 运行时数据

- Codex 额度由本机 `codex app-server` 提供，只用于面板显示，不上传到本项目的服务器。
- BTC/USDT 与 ETH/USDT 使用 Binance 公共行情接口，不需要 API Key。
- Mac 日志位于当前用户的 `~/Library/Logs`；Windows 日志位于当前用户的 `%LOCALAPPDATA%\BubuPet`。
- Windows 日志和诊断报告会替换用户目录、邮箱及常见 Token 格式，并且不会记录额度百分比。

## 发布前审计

维护者应运行：

```bash
./scripts/privacy-audit.sh
```

发布包还应在全新临时目录中解压并重新执行校验，避免把本机缓存、日志或绝对路径带入压缩包。
