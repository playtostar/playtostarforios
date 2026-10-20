# PlayToStar（实况起点）iOS 上架完整指南

> 技术栈：Capacitor 8（套壳）+ React/Vite + NestJS + SQLite（**不是 Flutter**）
> 关键参数（全平台固定，勿改）：
> - **Bundle ID：`com.playtostar.app`**
> - **Apple Team ID：`L8C773X7VY`**（个人账号，年费 688）
> - 微信移动应用 AppID：`wxd0ef5d487ac33750`（已通过，安卓在用）
> - 微信 Universal Links：`https://playtostar.com/app/`
> - 版本：1.662 / 构建号（CFBundleVersion）26
>
> 本工程 Capacitor 插件走 **Swift Package Manager（SPM，无 Podfile）**；
> 微信 OpenSDK 走**手动 XCFramework**（已在 `App/Frameworks` 并写入工程，无需再操作）。

---

## 总览：从上到下 9 个阶段

| 阶段 | 在哪做 | 产出 |
|---|---|---|
| 1. 配置 App ID 与能力 | Apple Developer 后台 | App ID 开启 Sign in with Apple + Associated Domains |
| 2. 制作分发证书并导出 p12 | Mac 钥匙串访问 | `cert/distribution.p12` |
| 3. 制作描述文件 | Apple Developer 后台 | `cert/App.mobileprovision` |
| 4. 微信开放平台补 iPhone/iPad | 微信开放平台 | 微信 iOS 登录可用（可能二次审核） |
| 5. 部署 AASA 文件 | 服务器（一键包） | Universal Link 可被系统校验 |
| 6. 打 IPA | 租的远程 Mac | `ipa_output/App.ipa` |
| 7. 上传 App Store Connect | Transporter | 构建出现在 TestFlight |
| 8. 创建 App + 填资料 + 提审 | App Store Connect | 提交审核 |
| 9. TestFlight 测试 | iPhone/iPad | 验证微信/Apple 登录、滚动、返回 |

> 方案 A（Codemagic）与方案 B（Mac 本地）二选一。
> **你已租远程 Mac，直接走方案 B（阶段 6 的脚本）最省事**；方案 A 的配置也保留在包里，以后可再试。

---

## 阶段 1 · 配置 App ID 与能力（Apple Developer 后台）

1. 打开 https://developer.apple.com/account → **Certificates, Identifiers & Profiles** → **Identifiers**。
2. 找到 `com.playtostar.app`（没有就点 **+** 新建，选 **App IDs → App**，Description 填 `PlayToStar`，Bundle ID 选 Explicit 填 `com.playtostar.app`）。
3. 在 Capabilities 列表里勾选这两项（必须，否则登录必崩/必拒）：
   - ✅ **Sign In with Apple**
   - ✅ **Associated Domains**
4. 点 **Save / Continue** 保存。

> 这一步只是在 App ID 上"登记能力"；描述文件（阶段 3）会把这些能力带进去。

---

## 阶段 2 · 制作分发证书并导出 p12（在远程 Mac 上）

> 目的：拿到一个 `Apple Distribution` 证书，导出为 `.p12`（含私钥），供脚本非交互签名。

1. 远程 Mac 打开 **钥匙串访问（Keychain Access）** → 菜单 **证书助理 → 从证书颁发机构请求证书…**。
2. 填你的开发者 Apple ID 邮箱，选 **存储到磁盘**，生成 `CertificateSigningRequest.certSigningRequest`（CSR）。
3. 回 Apple Developer 后台 → **Certificates → +** → 选 **Apple Distribution** → 上传刚才的 CSR → 生成后下载 `distribution.cer`，双击导入钥匙串。
4. 钥匙串访问 → "我的证书"里找到 **Apple Distribution: … (L8C773X7VY)**，右键（含其下私钥一起）→ **导出** → 格式选 **个人信息交换 (.p12)** → 设置一个导出密码（**这个密码就是脚本的 `P12_PASSWORD`**）。
5. 把导出的文件命名为 `distribution.p12`，放进工程的 `cert/` 目录。

---

## 阶段 3 · 制作描述文件（.mobileprovision）

1. Apple Developer 后台 → **Profiles → +** → 选 **App Store Connect**（分发用）→ Continue。
2. App ID 选 `com.playtostar.app`。
3. 证书选阶段 2 的 **Apple Distribution** 证书。
4. 命名（如 `PlayToStar AppStore`），生成并下载，命名为 `App.mobileprovision`，放进 `cert/`。
5. **自检（脚本会自动做，这里帮助理解）**：该描述文件必须含
   - `com.apple.developer.applesignin`（Sign in with Apple）
   - `com.apple.developer.associated-domains`（Universal Link / 微信）

   若阶段 1 没勾能力就生成了描述文件，会缺这两项 → 回阶段 1 勾上，**重新生成并下载描述文件**。

---

## 阶段 4 · 微信开放平台补 iPhone / iPad 信息

> 你已有"已通过"的移动应用「实况起点」（AppID `wxd0ef5d487ac33750`），只需补 iOS 平台。

1. 登录 https://open.weixin.qq.com → 管理中心 → 移动应用 → 实况起点 → **修改应用平台信息**。
2. **iPhone 应用**：开发 iPhone 应用选 **是**；
   - Bundle ID：`com.playtostar.app`
   - 测试版本 Bundle ID：`com.playtostar.app`
   - Universal Links：`https://playtostar.com/app/`
   - 应用已上架：当前选 **否**（上架通过后再改回 **是**；未上架且已认证主体，微信登录限 100 次/天，测试够用）。
3. **iPad 应用**：同样选是，参数一致（本工程 TARGETED_DEVICE_FAMILY = "1,2"，iPhone+iPad 通用）。
4. 提交。**补平台可能触发微信二次审核**，留意审核状态；审核期间可先用 Apple 登录或限额内测试。

---

## 阶段 5 · 部署 AASA（Universal Link 校验文件）

微信与系统会访问下面这个地址来校验 Universal Link：

```
https://playtostar.com/.well-known/apple-app-site-association
```

已为你准备一键部署包 `aasa_deploy_v01.tar.gz`（顶层短目录名）。在服务器执行：

```bash
cd /www/wwwroot/upload
tar -xzf aasa_deploy_v01.tar.gz
bash aasa_deploy_v01/deploy.sh
```

部署后验证（浏览器直接打开，应能下载/显示 JSON，且 Content-Type 为 `application/json`）：

```
https://playtostar.com/.well-known/apple-app-site-association
```

文件内 `appID` 必须是 `L8C773X7VY.com.playtostar.app`，paths 覆盖 `/app/`。

> AASA 由系统/微信缓存，首次安装 App 时拉取；改完后**重装一次 App** 最稳。

---

## 阶段 6 · 打 IPA（方案 B：远程 Mac 本地，推荐）

### 6.1 准备远程 Mac 环境（一次性）

- App Store 安装 **Xcode**（最新正式版），打开一次完成组件安装；终端执行：
  ```bash
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
  ```
- 安装 **Node 22 LTS**（https://nodejs.org ，或用 nvm）。验证：`node -v` 必须是 v22+。
- 把整个工程目录拷到远程 Mac（路径**不要太深、不要含中文/空格**，避免后续签名与 Windows 260 路径问题）。

### 6.2 放入证书

```
工程根/cert/distribution.p12        （阶段 2）
工程根/cert/App.mobileprovision     （阶段 3）
```

### 6.3 一条命令打包

在**工程根目录**（含 `package.json`、`ios/`、`build_ipa_local.sh` 的那一层）执行：

```bash
chmod +x build_ipa_local.sh
P12_PASSWORD='你的p12导出密码' TEAM_ID='L8C773X7VY' ./build_ipa_local.sh
```

脚本会自动完成：环境检查 → npm ci → cap sync ios → 微信集成自检 →
安装描述文件 → 导入 p12 到临时钥匙串（退出自动清理）→ 解析 SPM（无 pod install）→
archive → 导出 IPA。

成功后 IPA 在：`工程根/ipa_output/App.ipa`。

可选环境变量：

- `BUILD_NUMBER=27`（再次上传必须比上次大，默认 26）
- `EXPORT_METHOD=ad-hoc`（默认 app-store；想装指定设备测试用 ad-hoc）
- `GIT_URL=... GIT_BRANCH=main`（让脚本现场 clone 仓库构建，不用本地代码）

> 工程已集成微信 xcframework，正常无需运行 `setup_wechat.sh`；
> 只有当工程被 `cap add ios` 重置、自检报缺微信时，才在 `ios/App` 目录执行 `bash setup_wechat.sh`。

---

## 阶段 7 · 上传 App Store Connect

**方式一（推荐，图形）**：远程 Mac 的 App Store 安装 **Transporter** → 把 `App.ipa` 拖进去 → 点 **交付**。

**方式二（命令行）**：到 https://appleid.apple.com 给本账号生成一个 **App 专用密码**，然后：

```bash
xcrun altool --upload-app -f "ipa_output/App.ipa" -t ios \
  -u "你的开发者AppleID邮箱" -p "App专用密码"
```

上传后等几分钟～半小时，构建会出现在 **App Store Connect → TestFlight**，并自动做加密合规（因已声明 `ITSAppUsesNonExistentEncryption=false`，一般无需额外操作）。

---

## 阶段 8 · 创建 App、填资料、提交审核

1. 打开 https://appstoreconnect.apple.com → **我的 App → + → 新建 App**：
   - 名称：实况起点（若被占用，用"实况起点 PlayToStar"）
   - 主要语言：简体中文
   - Bundle ID：`com.playtostar.app`
   - SKU：任意唯一标识，如 `playtostar001`
   - 用户访问：完全访问。
2. **App 隐私**：数据收集声明。本 App 收集：用户内容（帖子/评论/加点方案）、用户标识（登录标识）；
   - 微信/Apple 登录用于"App 功能"，不用于追踪；不勾选广告追踪（IDFA）。
   - 如实填写，**不用于第三方广告/追踪**可大幅降低审核风险。
3. **版本信息**（1.662）：
   - 截图：按 App Store Connect 要求提供各尺寸（6.7" iPhone、12.9" iPad 等；可用模拟器或真机截图）。
   - 描述、关键词、技术支持网址（`https://playtostar.com`）、隐私政策网址（必填，放你站点的隐私政策页）。
   - 年龄分级：按问卷如实选（本 App 无赌博/暴力，足球题材一般 4+）。
4. **登录演示账号**（审核被拒重灾区）：在"App 审核信息"里提供一个**可直接登录的测试账号密码**，
   并备注：可使用"微信登录 / Apple 登录"，或使用提供的测试账号。
5. 选中等处理的构建（阶段 7 上传、出现在下拉里的那个）→ **添加以提交审核** → 提交。

---

## 阶段 9 · TestFlight 测试（提审前后都要做）

1. TestFlight → 把自己的 Apple ID 加为**内部测试员**（内部测试无需合规评审，立即可测）。
2. iPhone / iPad 装 TestFlight，安装本构建，重点回归：
   - **微信登录**：能拉起微信、授权后回到 App 并登录成功（验证阶段 4/5 已生效）。
   - **Apple 登录**：能拉起 Face ID/Touch ID 授权并登录。
   - **页面可上下滚动**（1.662 已修复 `ios.scrollEnabled`）。
   - **iPad 顶部不被状态栏遮挡**（iPhone12 已正常，重点测 iPad mini 竖/横屏）。
   - **左边缘右滑返回**、**账号注销/拉黑/举报/删除内容**（UGC 合规，不做必拒）。

---

## 附 A · 审核高频驳回点对照（本工程处理情况）

| 条款 | 要求 | 本工程 |
|---|---|---|
| 账号登录 | 第三方（微信）登录的 App **必须**同时提供 **Sign in with Apple** | 已提供双登录 |
| 账号删除 | 必须能在 App 内**注销账号**（不只是退出） | 需确认入口已上线 |
| UGC 治理 | 用户产生内容必须能**举报、拉黑作者**，并有内容审核机制 | 举报/拉黑已做，需自测 |
| 隐私数据 | 相册等权限要有用途描述；隐私政策可访问 | Info.plist 已配，需提供隐私政策 URL |
| 内容版权 | eFootball/球员素材存在 IP 风险 | **无法保证过审**，被问及时需说明数据来源/性质 |
| 支付 | 数字内容/会员不得用微信支付绕开 IAP | 本微信 SDK 用 **NoPay 版**（不含支付），规避此项 |

## 附 B · 开工前最终检查清单

- [ ] App ID 已勾 Sign in with Apple + Associated Domains
- [ ] `cert/distribution.p12` 已放好并记住密码
- [ ] `cert/App.mobileprovision` 已放好（含上述两项授权）
- [ ] 微信开放平台 iPhone/iPad 已提交，Bundle ID / UL 正确
- [ ] AASA 已部署且浏览器可访问
- [ ] 远程 Mac：Xcode 已初始化、Node 为 v22+
- [ ] App 内：账号注销、举报、拉黑、隐私政策 URL 已就绪
- [ ] 构建号 ≥26，且每次重新上传递增
