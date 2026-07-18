# mayday电子物料

一个非官方、非商业的五月天歌迷桌面项目。目前包含 Codex 动态宠物“卜卜”、Codex 剩余额度面板，以及 BTC/USDT、ETH/USDT 实时价格。

![卜卜动作总览](shared/preview/卜卜动作总览.png)

## 下载

请在项目右侧的 **Releases** 中选择对应系统：

- `卜卜-macOS-Universal-v1.0.0.zip`：macOS 13+，Apple 芯片与 Intel Mac。
- `卜卜-Windows-10-11-v1.0.0.zip`：Windows 10/11，x64 与 ARM64。

两个压缩包的名称、根目录和安装入口都明确标注了系统，不能混用。

## 使用方法

### macOS

1. 完整解压 `卜卜-macOS-Universal-v1.0.0.zip`。
2. 双击 `安装卜卜-macOS.command`。
3. 如果系统拦截，请右键安装文件并选择“打开”。
4. 退出并重新打开 Codex。

### Windows

1. 完整解压 `卜卜-Windows-10-11-v1.0.0.zip`，不要在压缩包预览窗口中运行。
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
- macOS 面板使用原生 AppKit，30 ms 跟随，并读取 Codex 保存的可见宠物尺寸。
- Windows 面板使用 WPF 与桌面合成器逐帧事件跟随；拖动时暂停额度、行情和诊断刷新，减少跟随延迟。
- 两个平台都不需要管理员权限，也不需要 API Key。

## 隐私

项目不包含作者的用户名、邮箱、绝对路径、API Key、访问令牌、账号缓存、聊天记录或真实额度数据。面板只在本机读取 Codex 已登录账号的额度；行情来自 Binance 公共现货接口。诊断日志会脱敏用户目录、邮箱和常见令牌格式。详见 [PRIVACY.md](PRIVACY.md)。

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
