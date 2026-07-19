# 卜卜 macOS 版

## 安装

1. 完整解压 `Mayday-Bubu-macOS-Universal-v1.0.7.zip` 或 `Mayday-Bubu-macOS-Universal-Codex-Only-v1.0.7.zip`。
2. 双击 `安装卜卜-macOS.command`。
3. 如果出现“Apple 无法验证”提示，点“完成”，不要点“移到废纸篓”。
4. 双击 `安装被拦截-打开隐私与安全.html`；页面会尝试自动跳转，如果没跳转就点蓝色按钮。
5. 在“隐私与安全”中点击“仍要打开”或“Open Anyway”，输入 Mac 登录密码确认，再重新双击安装文件。
6. 如果跳转仍有问题，双击 `如果仍无法打开-Apple官方步骤.webloc`。
7. 重新打开 Codex；安装器会优先自动选中卜卜。

“仍要打开”按钮只会在尝试启动安装文件后出现，并会保留约一小时。
[查看 Apple 官方的允许步骤](https://support.apple.com/guide/mac-help/mh40616/mac)。

## 要求

- macOS 12.3+
- Apple 芯片或 Intel Mac
- 已安装并登录 Codex

## 功能

- 安装 Codex v2 宠物卜卜。
- 原生 AppKit 额度面板，约 30 ms 跟随卜卜；面板箭头和卜卜可见中心对齐，箭头尖端到头顶固定为 14 个逻辑像素。
- 按实时窗口坐标匹配宠物锚点，不再依赖易变的显示器编号；兼容 Retina 缩放、多屏负坐标和旧版 Codex 的 `anchor` 记录。
- 找不到宠物窗口时会读取 Codex 保存的位置；仍无法定位时会先显示在当前屏幕右上角，不再无提示消失。
- 安装结束前会检查面板进程和运行状态文件，首次启动失败会自动重试。
- Codex 额度每 5 分钟更新。
- 完整版的 BTC/USDT、ETH/USDT 每 5 秒更新。
- `Codex-Only` 版只保留额度，面板会自动缩短，并且不会请求 BTC/ETH 行情。
- 不需要管理员权限或 API Key。

## 检查与卸载

- `检查卜卜-macOS.command`：检查宠物、Universal 2 架构、签名、面板进程、运行状态、跟随定位和额度；完整版本还会检查行情。
- `卸载卜卜-macOS.command`：只移除卜卜和本项目面板。
