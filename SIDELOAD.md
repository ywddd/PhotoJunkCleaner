# 侧载安装说明（AltStore / Sideloadly / TrollStore）

适用于没有完整开发者账号、或希望在 iOS 上刷新签名的场景。  
**推荐仍优先用 Mac + Xcode 真机运行**（调试最稳）。侧载适合「只想装上用」。

> 合规提示：仅安装**你自己编译**的 App，不要安装来路不明的 ipa。以下工具请从官网获取。

---

## 一、先在 Mac 上打出可安装包

### 方式 A：Xcode Archive（推荐）

1. 打开 `PhotoJunkCleaner.xcodeproj`
2. Signing 选择你的 Apple ID Team，Bundle ID 改成唯一值  
   例：`com.你的名字.PhotoJunkCleaner`
3. 真机选中你的 iPhone，先 ⌘R 能跑通
4. 菜单 **Product → Archive**
5. Organizer 里 **Distribute App → Ad Hoc** 或 **Development**  
   - 免费账号通常只能 Development，且设备需已注册
6. 导出得到 `.ipa`

### 方式 B：命令行（有 Xcode）

```bash
# 在工程根目录
xcodebuild -scheme PhotoJunkCleaner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/PhotoJunkCleaner.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/PhotoJunkCleaner.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

`ExportOptions.plist` 示例（Development）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>你的TEAM_ID</string>
</dict>
</plist>
```

---

## 二、Sideloadly（Windows / Mac，较省事）

官网：https://sideloadly.io

1. 安装 Sideloadly，用线连接 iPhone，信任电脑
2. 填入 Apple ID（建议专用小号）
3. 拖入导出的 `.ipa` 或直接拖 `PhotoJunkCleaner.app`（部分版本支持）
4. 点击 Start，等待安装
5. iPhone：**设置 → 通用 → VPN与设备管理 → 信任**
6. 免费账号签名约 **7 天** 过期，到期用 Sideloadly 重新签一次

注意：

- 同一 Apple ID 同时侧载 App 数量有限（历史上常见 3 个限制，以实际为准）
- 不要在不可信网络输入主力账号密码

---

## 三、AltStore / AltServer

官网：https://altstore.io

1. Mac/PC 安装 **AltServer**，iPhone 安装 **AltStore**
2. 通过 AltServer 用 Apple ID 登录并安装 AltStore 到手机
3. 将 `.ipa` 用 AirDrop / iTunes 文件共享 / 浏览器 传到手机
4. 在 AltStore 中 **My Apps → +** 导入 ipa 安装
5. 保持电脑 AltServer 间歇在线，或使用邮件刷新插件（按官方文档），以便 **7 天自动刷新**

适合希望「尽量自动续签」的用户。

---

## 四、TrollStore（仅特定系统 / 设备）

若设备支持 TrollStore（一般需特定 iOS 版本与安装条件）：

- 可实现持久签名、不依赖 7 天刷新
- **仅**在你设备确实支持、且你理解风险时使用
- 安装渠道务必来自官方仓库说明，本项目不提供越狱教程

---

## 五、权限与首次启动

1. 打开「废图清理」
2. 照片权限选 **所有照片**（「有限访问」会漏扫）
3. 设置中打开：
   - 保护「收藏」
   - 需要的白名单相册
4. 先小范围扫描（例如最近 200 张截图）验证识别效果，再大批量清理
5. 删除后照片进入系统 **最近删除**，30 天内可恢复

---

## 六、常见问题

| 现象 | 处理 |
|------|------|
| 未受信任的开发者 | 设置 → 通用 → VPN与设备管理 → 信任 |
| 无法验证 App | 网络正常后重试；或重签 |
| 7 天后闪退 | 用 Xcode / Sideloadly / AltStore 重新签名安装 |
| 扫描很慢 | 降低扫描上限；仅扫截图；提高置信度阈值 |
| 误识别 | 结果页取消勾选；提高置信度；加白名单相册 |

---

## 七、与 Xcode 直装对比

| 方式 | 优点 | 缺点 |
|------|------|------|
| Xcode ⌘R | 调试方便、最稳 | 需 Mac |
| Sideloadly | 跨平台、步骤简单 | 需电脑刷新签名 |
| AltStore | 可自动刷新 | 配置稍繁 |
| TrollStore | 持久 | 设备/系统门槛高 |

**建议路径**：先用 Xcode 真机跑通 → 确认功能 OK → 再按需导出 ipa 侧载。
