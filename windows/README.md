# 卜卜 Windows 版

## 安装

1. 完整解压 `卜卜-Windows-10-11-v1.0.0.zip`。
2. 双击 `安装卜卜-Windows.cmd`。
3. 完全退出并重新打开 Codex。

安装器会先安装宠物，再安装可选的 WPF 额度面板。面板失败不会影响宠物本体。

## 要求

- Windows 10/11
- x64 或 ARM64
- 推荐启用系统自带 Windows PowerShell 5.1、WPF 和 WSH
- 不需要管理员权限、Python、Node.js、.NET SDK 或 API Key

## 低延迟跟随

- 优先跟随 Codex 原生宠物窗口，并按当前显示器 DPI 计算位置。
- 使用 Windows 桌面合成器逐帧事件移动面板。
- 拖动宠物时暂停额度、BTC/ETH 和健康日志刷新，停止后自动恢复。
- 原生窗口不可用时才使用保存坐标回退。

## 兼容入口

- `兼容安装-只装宠物.cmd`：公司电脑限制 PowerShell 时使用。
- `修复或启动看板.cmd`：覆盖并重启额度面板。
- `检查安装环境.cmd`：在桌面生成脱敏报告。
- `卸载卜卜-Windows.cmd`：卸载宠物和面板。

## 数据

Codex 额度只从本机服务读取；BTC/USDT 和 ETH/USDT 来自 Binance 公共现货行情。诊断日志会隐藏用户路径、邮箱和常见 Token，并且不记录真实额度百分比。
