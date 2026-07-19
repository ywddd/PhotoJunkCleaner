# 用 GitHub Actions 云端编译 PhotoJunkCleaner

本机（iPhone / Minis）**无法**直接产出可安装的 iOS `.ipa`。  
可以：把工程推到 GitHub → Actions 用 **macOS + Xcode** 自动编译 → 下载产物。

---

## 你能拿到什么

| 产物 | 说明 | 能否直接装到手机 |
|------|------|------------------|
| **unsigned.ipa / .app** | 默认 workflow 产出，**未签名** | ❌ 需用 Sideloadly / 自己证书重签 |
| **signed IPA**（可选） | 配置 Apple 证书 Secrets 后 | ✅ 装到证书对应设备 |

> 免费 Apple ID **很难**在 CI 里稳定签名；推荐本机 Xcode 自签，或付费开发者账号导出证书给 Actions。

---

## 方式 A：一键上传（推荐，需你的 Token）

1. 打开 [GitHub → Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)  
2. 新建 **Fine-grained** 或 classic token，权限至少：  
   - `repo`（创建仓库 + 推送）  
3. 在 Minis 里添加环境变量（点下面链接）：

[设置 GITHUB_TOKEN](minis://settings/environments?create_key=GITHUB_TOKEN&create_value=&create_note=GitHub%20PAT%20for%20push%20PhotoJunkCleaner)

4. 回来跟我说：**「用 GitHub 上传并构建」**  
   我会执行：创建公开/私有仓库 → push → 触发 Actions。

可选环境变量：

| 变量 | 含义 |
|------|------|
| `GITHUB_TOKEN` | 必填，PAT |
| `GITHUB_USERNAME` | 可选，默认用 API 读登录名 |
| `GITHUB_REPO` | 可选，默认 `PhotoJunkCleaner` |
| `GITHUB_PRIVATE` | `1` = 私有仓库，默认公开 |

---

## 方式 B：你自己在电脑上推送

```bash
# 1. 解压工程
tar -xzf PhotoJunkCleaner.tar.gz
cd PhotoJunkCleaner

# 2. 初始化并推送
git init
git add .
git commit -m "PhotoJunkCleaner v1.1.0"
git branch -M main
# 先在 GitHub 网页新建空仓库 PhotoJunkCleaner，再：
git remote add origin https://github.com/<你的用户名>/PhotoJunkCleaner.git
git push -u origin main
```

或用 GitHub CLI：

```bash
gh repo create PhotoJunkCleaner --public --source=. --remote=origin --push
```

---

## 下载编译产物

1. 打开仓库 → **Actions**  
2. 选中 **iOS Build** 工作流 → 最新 run  
3. 底部 **Artifacts** → 下载 `PhotoJunkCleaner-unsigned`  
4. 解压得到：  
   - `PhotoJunkCleaner-unsigned.ipa`  
   - `PhotoJunkCleaner.app`

### 装到手机（未签名 IPA）

1. Mac 安装 [Sideloadly](https://sideloadly.io)  
2. 拖入 `PhotoJunkCleaner-unsigned.ipa`  
3. 登录 Apple ID → Start（会用你的账号重签）  
4. 手机：设置 → 通用 → VPN与设备管理 → 信任  

详见 [SIDELOAD.md](./SIDELOAD.md)。

---

## 可选：CI 里产出「已签名 IPA」

需要 **付费 Apple Developer**（或企业）证书：

在仓库 **Settings → Secrets and variables → Actions** 添加：

| Secret | 内容 |
|--------|------|
| `BUILD_CERTIFICATE_BASE64` | 导出的 `.p12` 的 base64 |
| `P12_PASSWORD` | p12 密码 |
| `BUILD_PROVISION_PROFILE_BASE64` | `.mobileprovision` 的 base64 |
| `KEYCHAIN_PASSWORD` | 任意临时钥匙串密码 |
| `TEAM_ID` | 10 位 Team ID |
| `BUNDLE_ID` | 与描述文件一致的 Bundle ID |

导出 p12 / profile 的 base64（在 Mac 上）：

```bash
base64 -i Certificates.p12 | pbcopy          # → BUILD_CERTIFICATE_BASE64
base64 -i profile.mobileprovision | pbcopy  # → BUILD_PROVISION_PROFILE_BASE64
```

配置后，workflow 的 **signed-ipa** job 会自动跑，产物为 `PhotoJunkCleaner-signed-ipa`。

---

## 本地一条命令编译（Mac）

```bash
cd PhotoJunkCleaner
xcodebuild \
  -project PhotoJunkCleaner.xcodeproj \
  -scheme PhotoJunkCleaner \
  -sdk iphoneos \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd \
  build
```

有签名时直接用 Xcode **Product → Archive** 更简单。

---

## 限制说明（请知悉）

1. **Minis / iSH 无法调用 Xcode**，不能在手机上直接编出 App。  
2. GitHub Actions **免费额度**有限（私有仓库 macOS 分钟数较少）。  
3. **未签名 IPA 不能**直接隔空投送安装，必须重签。  
4. 免费 Apple ID 自签约 7 天过期，需重装。  

---

有 `GITHUB_TOKEN` 后直接说「上传到 GitHub 并构建」即可。
