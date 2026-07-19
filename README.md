<p align="center">
  <img src="shared/community/bubu-wechat-group.jpg" alt="卜卜电子物料交流群二维码" width="420">
</p>

<p align="center">
  老师们可以加群<br>
  突然好多人找我要，我估计会有 bug<br>
  有问题在群里问我就行，如果有版本更新我也会在群里说<br>
  我无限 token，随便改<br>
  下周抽空再做个 MaydayLand Codex 看板皮肤<br>
  想要什么也都可以跟我说 有空我就可以做
</p>

# mayday卜卜电子物料

一个非官方、非商业的五月天歌迷桌面项目。目前包含 Codex 动态宠物“卜卜”、Codex 剩余额度面板，以及 BTC/USDT、ETH/USDT 实时价格。

![卜卜动作总览](shared/preview/卜卜动作总览.png)

## 下载

请在项目右侧的 **Releases** 中选择对应系统：

- `Mayday-Bubu-macOS-Universal-v1.0.6.zip`：macOS 12.3+，Apple 芯片与 Intel Mac。
- `Mayday-Bubu-Windows-10-11-v1.0.0.zip`：Windows 10/11，x64 与 ARM64。

两个压缩包的名称、根目录和安装入口都明确标注了系统，不能混用。

## 使用方法

### macOS

1. 完整解压 `Mayday-Bubu-macOS-Universal-v1.0.6.zip`。
2. 双击 `安装卜卜-macOS.command`。
3. 如果出现“Apple 无法验证”提示，点“完成”，不要点“移到废纸篓”。
4. 双击包内的 `安装被拦截-打开隐私与安全.html`；页面会尝试自动跳转，如果没跳转就点蓝色按钮。
5. 在“隐私与安全”中点击“仍要打开”或“Open Anyway”，输入 Mac 登录密码，再重新双击安装文件。
6. 如果跳转仍有问题，双击 `如果仍无法打开-Apple官方步骤.webloc`。
7. 退出并重新打开 Codex。

### Windows

1. 完整解压 `Mayday-Bubu-Windows-10-11-v1.0.0.zip`，不要在压缩包预览窗口中运行。
2. 双击 `安装卜卜-Windows.cmd`。
3. 完全退出并重新打开 Codex。
4. 公司电脑限制 PowerShell 时，可运行 `兼容安装-只装宠物.cmd`；宠物仍可使用，但不会安装额度面板。

## 当前动作

- 默认：卜卜戴黑框眼镜，坐在完整办公椅上使用带蓝色萝卜标志的电脑。
- 鼠标悬停：卜卜拿起咖啡杯喝咖啡。
- 向左拖动：保留头顶三瓣装饰，变成无手脚圆球，在立式麦克风前唱歌。
- 向右拖动：变成无手脚圆球，弹奏深蓝色电吉他。
- 额度面板：跟随在卜卜头顶约 14 px；额度每 5 分钟更新，BTC/ETH 每 5 秒更新，可隐藏和显示。

## 性能与兼容性

- 宠物图集固定为 Codex v2 的 8×11、1536×2288 WebP；Mac 与 Windows 使用同一份已验证图集，避免跨平台动作变形。
- macOS 面板使用原生 AppKit，30 ms 跟随；箭头对齐宠物可见中心，与头顶保持 14 个逻辑像素。定位不依赖显示器编号，兼容 Retina、外接屏、旧版 `anchor` 状态和不同宠物尺寸。
- Windows 面板使用 WPF 与桌面合成器逐帧事件跟随；拖动时暂停额度、行情和诊断刷新，减少跟随延迟。
- 两个平台都不需要管理员权限，也不需要 API Key。

## 源码目录

- `shared/`：跨平台宠物图集与预览。
- `macos/`：AppKit 面板源码和安装器模板。
- `windows/`：WPF/PowerShell 面板源码和安装器模板。
- `scripts/`：构建、校验和隐私审计脚本。
- `dist/`：当前可直接下载的 Mac/Windows 压缩包。

## 开发与构建

macOS 需要 Xcode Command Line Tools：

```bash
./scripts/build-macos-release.sh
```

Windows 10/11 使用 Windows PowerShell 5.1：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-windows-release.ps1
```

## 许可与声明

本项目的原创代码使用 MIT License。五月天名称、相关视觉元素、角色灵感和素材不属于 MIT 授权范围；项目与五月天、相信音乐及相关权利方无官方关系。发布或二次使用前请阅读 [ASSET-NOTICE.md](ASSET-NOTICE.md)。
