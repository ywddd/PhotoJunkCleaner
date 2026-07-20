## PhotoJunkCleaner 0.9.0（预发布）

本地 Vision 分类 + OCR + 可选云端视觉。

# 废图清理 (PhotoJunkCleaner) v1.1

智能识别并清理相册里的外卖截图、快递物流、二维码、支付页、验证码等「用完即弃」图片。  
**删除前必须人工勾选 + 二次确认**；删除后进入系统「最近删除」，可恢复。

- 平台：iOS 16+
- UI：SwiftUI
- 识别：Apple Vision（本地 OCR + 条码），照片不离开设备
- 安装：Mac + Xcode 自签，或见 [SIDELOAD.md](SIDELOAD.md)

---

## 功能一览（v1.1）

1. **分类识别**
   - 外卖（美团/饿了么/京东秒送等大量关键词）
   - 快递物流（顺丰/菜鸟/京东物流/运单号等）
   - 二维码 / 条码截图
   - 支付与账单
   - 验证码与通知
   - 聊天截图特征
   - 普通截图（默认**不**勾选删除）
2. **白名单保护**
   - 跳过「收藏」照片
   - 跳过用户指定的相册
3. **确认删除**
   - 结果页按分类展示，可多选/取消
   - 弹窗二次确认后才调用系统删除 API
4. **设置**
   - 仅截图 / 含近期照片
   - 扫描上限、置信度阈值
   - 相册白名单列表

---

## 在 Xcode 中运行（自签）

1. 拷贝本目录或解压 `PhotoJunkCleaner.tar.gz` 到 Mac
2. 打开 `PhotoJunkCleaner.xcodeproj`
3. **Signing & Capabilities**
   - Team：你的 Apple ID
   - Bundle Identifier：改成唯一，如 `com.yourname.PhotoJunkCleaner`
4. 连接 iPhone，选真机目标，⌘R
5. 若提示未信任：设置 → 通用 → VPN与设备管理 → 信任

备用：若工程文件异常，见 [CREATE_IN_XCODE.md](CREATE_IN_XCODE.md) 新建 SwiftUI 工程再拖入源码。

侧载（AltStore / Sideloadly）：见 [SIDELOAD.md](SIDELOAD.md)。

---

## 工程结构

```
PhotoJunkCleaner/
├── PhotoJunkCleaner.xcodeproj/
├── PhotoJunkCleaner/
│   ├── PhotoJunkCleanerApp.swift
│   ├── Info.plist
│   ├── Models/
│   │   ├── JunkCategory.swift
│   │   ├── JunkPhotoItem.swift
│   │   └── AppSettings.swift          # 偏好 + 白名单
│   ├── Services/
│   │   ├── PhotoLibraryService.swift  # 相册权限与候选集
│   │   ├── ImageClassifierService.swift # OCR/条码/关键词
│   │   └── ScanEngine.swift
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── ResultsView.swift
│   │   └── SettingsView.swift
│   └── Assets.xcassets/               # 含 AppIcon
├── scripts/generate_app_icon.py
├── README.md
├── CREATE_IN_XCODE.md
└── SIDELOAD.md
```

---

## 使用建议

1. 首次授权选 **所有照片**
2. 设置中打开「保护收藏」，并为重要相册加白名单
3. 先扫「截图」小批量试跑，检查分类是否合理
4. 结果页取消误伤项，再点删除并确认
5. 误删：打开系统「照片 → 最近删除」恢复

---

## 版本

| 版本 | 说明 |
|------|------|
| 1.0.0 | 首版：扫描、分类、确认删除 |
| 1.1.0 | 快递分类 + 关键词扩展；收藏/相册白名单；UI 优化；App 图标；侧载文档 |

---

## 免责声明

识别基于启发式关键词与 Vision，**不能保证 100% 准确**。请始终人工确认后再删除。作者不对误删数据负责。
