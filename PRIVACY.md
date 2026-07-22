# 隐私说明

## 仓库与发布包不包含

- 作者或测试者的本机用户名、邮箱、主目录和绝对路径；
- GitHub Token、API Key、Cookie、密码或其他访问凭据；
- Codex 聊天内容、账号缓存、真实额度百分比或重置时间；
- 安装测试产生的日志、健康状态文件和诊断报告。

## 运行时数据

- Codex 额度由本机 `codex app-server` 提供，只用于面板显示，不上传到本项目的服务器。
- 任务列表只在本机读取 Codex `session_index.jsonl` 中的任务 ID 与正式任务名称、`.codex-global-state.json` 中的未读任务 ID，并与对应会话中的开始、完成、等待输入标记匹配；这些数据用于让未查看的完成任务留在面板中，并在用户点开任务后移除。旧版 Codex 没有相关索引时才读取最新用户任务文字并使用短时完成提示作为回退。任务名称、任务文字与已读状态不写入诊断日志，也不上传。
- BTC/USDT 使用 Binance 公共行情接口，不需要 API Key。
- Mac 日志位于当前用户的 `~/Library/Logs`；Windows 日志位于当前用户的 `%LOCALAPPDATA%\BubuPet`。
- Windows 日志和诊断报告会替换用户目录、邮箱及常见 Token 格式，并且不会记录额度百分比。

## 发布前审计

维护者应运行：

```bash
./scripts/privacy-audit.sh
```

发布包还应在全新临时目录中解压并重新执行校验，避免把本机缓存、日志或绝对路径带入压缩包。
