# 备用：在 Xcode 里新建工程再拖入源码

若 `project.pbxproj` 打开异常，用此方法 2 分钟即可：

1. Mac 打开 **Xcode → File → New → Project → iOS → App**
2. 填写：
   - Product Name: `PhotoJunkCleaner`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - 取消勾选 Tests（可选）
3. 保存到任意文件夹
4. 删除 Xcode 自动生成的 `ContentView.swift` / `*App.swift`（或整份替换）
5. 把本目录 `PhotoJunkCleaner/` 下所有源码与资源拖进工程（勾选 Copy items if needed）
6. 用本目录 `Info.plist` 替换，或在 Target → Info 添加：
   - Privacy - Photo Library Usage Description
   - Privacy - Photo Library Additions Usage Description
7. Signing 选你的 Team，改 Bundle ID，连真机 ⌘R

源码入口：`PhotoJunkCleanerApp.swift` + `Views/ContentView.swift`
