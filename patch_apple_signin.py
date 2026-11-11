#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Apple 登录插件（@capacitor-community/apple-sign-in 7.1.0）· iPad 修复补丁
=======================================================================

【为什么需要它】
App Store 第 4 次拒审（2026-11-10，Submission 538ddac8-680f-4658-90ad-c7081cb1ee5a）
的 2.1(a) 根因：
    审核设备 = iPad Air 11-inch (M3)
    插件的 ASAuthorizationController 只设了 delegate，没设 presentationContextProvider，
    也没有在主线程驱动 performRequests()。
    → iPhone 上系统会回退到 key window，所以「本地自测是好的」；
    → iPad 上必须有显式 anchor 才能定位授权弹窗，缺了即报 AuthorizationError 1000(.unknown)。
    → 审核员点「通过 Apple 登录」弹不出授权框 = 核心功能不可用 = 2.1(a) 被拒。

【本脚本做三件事（幂等）】
  1) authorize 内：把 performRequests() 包进 DispatchQueue.main.async，并补
     authorizationController.presentationContextProvider = self
  2) 文件末尾追加 extension，实现 ASAuthorizationControllerPresentationContextProviding
  3) 回调里 identityToken! / authorizationCode! 的强制解包改为安全取值
     （原本 token 为 nil 会直接崩溃）

【设计原则（与项目既有习惯一致）】
  - 幂等：已打过的补丁用标记 '[PATCHED-BY-PLAYTOSTAR]' 识别，重复运行安全；
  - 锚点缺失即报错退出（exit 1），绝不静默放过——静默放过比不修更坏；
  - 只改这一处，不触碰 SPM 结构 / 前端 / entitlements。

【接入位置】
  mobile/codemagic.yaml 的 scripts 里，「Install npm dependencies」之后新增：
      - name: Patch Apple Sign-In plugin (iPad presentation anchor)
        script: python3 "$CM_BUILD_DIR/patch_apple_signin.py"

【验证】
  构建日志应打印 "补丁完成"，且不再出现
  "CapacitorCommunityAppleSignIn is built for Capacitor 7, it might cause issues"
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

REL_PLUGIN_SWIFT = os.path.join(
    'node_modules',
    '@capacitor-community',
    'apple-sign-in',
    'ios',
    'Sources',
    'SignInWithApple',
    'Plugin.swift',
)
PLUGIN_SWIFT = os.path.join(HERE, REL_PLUGIN_SWIFT)

MARKER = '[PATCHED-BY-PLAYTOSTAR]'

# ---------------------------------------------------------------- 补丁 1
# 原代码（片段）：
#     let authorizationController = ASAuthorizationController(authorizationRequests: [request])
#     authorizationController.delegate = self
#     authorizationController.performRequests()
OLD_PERFORM = """        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.performRequests()
"""

NEW_PERFORM = """        // %s
        // ASAuthorizationController 是 UIKit 组件：
        //  ① performRequests() 必须在主线程驱动（Capacitor 插件方法跑在 bridge 后台队列，
        //     非主线程会间歇性失败并报 error 1000）；
        //  ② iPad 上必须显式指定 presentationContextProvider 作为弹窗锚点，
        //     否则授权 sheet 无法定位、报 ASAuthorizationError.Code.unknown(1000)。
        //     iPhone 上系统会回退到 key window，所以这个缺陷只在 iPad 上暴露。
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        }
""" % MARKER

# ---------------------------------------------------------------- 补丁 2
# 强制解包 → 安全取值
_TAB = ' ' * 16

OLD_TOKEN = '\n'.join([
    _TAB + '"identityToken": String(data: appleIDCredential.identityToken!, encoding: .utf8),',
    _TAB + '"authorizationCode": String(data: appleIDCredential.authorizationCode!, encoding: .utf8)',
])

# ⚠️ 用 Python 单引号字符串逐行拼接，避免三引号里 `?? ""` 与收尾 `"""` 粘连
#    导致生成的 Swift 字符串字面量少一个引号（会直接编译失败）。
NEW_TOKEN = '\n'.join([
    _TAB + '// ' + MARKER + ' 原为 identityToken! / authorizationCode! 强制解包，',
    _TAB + '// 凭证缺失时会直接崩溃；改为安全取值，nil 时返回空串，',
    _TAB + "// 由前端 `if (!r.identityToken) throw new Error('未获取到 Apple 凭证，请重试')` 兜底。",
    _TAB + '"identityToken": appleIDCredential.identityToken.flatMap { String(data: $0, encoding: .utf8) } ?? "",',
    _TAB + '"authorizationCode": appleIDCredential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""',
])

# 补丁 2 落盘后必须逐字出现的期望片段（防止引号/转义类静默错误）
EXPECTED_TOKEN_LINES = [
    _TAB + '"identityToken": appleIDCredential.identityToken.flatMap { String(data: $0, encoding: .utf8) } ?? "",',
    _TAB + '"authorizationCode": appleIDCredential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""',
]

# ---------------------------------------------------------------- 补丁 2.5
# 确保 import UIKit（presentationAnchor 里用到 UIApplication / UIWindow）
OLD_IMPORTS = """import Foundation
import Capacitor
import AuthenticationServices
"""

NEW_IMPORTS = """import Foundation
import Capacitor
import AuthenticationServices
import UIKit // %s presentationAnchor(for:) 需要 UIApplication / UIWindow
""" % MARKER

# ---------------------------------------------------------------- 补丁 3
# 追加 presentationAnchor 实现（以 extension 形式，避免改动类声明行）
APPEND_EXTENSION = """

// ============================================================
// %s presentation anchor（iPad 必需）
// ============================================================
// 以 extension 形式声明 conformance，不改动 `public class SignInWithApple:` 那一行，
// 减少与上游版本的锚点耦合。Swift 允许在 extension 中新增协议 conformance，
// 因此上方 `authorizationController.presentationContextProvider = self` 可正常编译。
extension SignInWithApple: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // 优先用 Capacitor 当前的 viewController 所在 window（与 webView 同场景，最准）。
        if let anchor = self.bridge?.viewController?.view.window {
            return anchor
        }
        // 兜底：多场景 / 时序竞态下取处于前台场景的 key window。
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive
                    || $0.activationState == .foregroundInactive
            }
            .flatMap { $0.windows }
        if let key = windows.first(where: { $0.isKeyWindow }) {
            return key
        }
        if let first = windows.first {
            return first
        }
        // 最后兜底：不依赖 UIApplication.shared.windows（iOS 15+ 已弃用），
        // 直接返回一个空锚点，避免 force unwrap 崩溃。
        return ASPresentationAnchor()
    }
}
""" % MARKER


def fail(msg: str) -> None:
    print('')
    print('=' * 62)
    print('❌ 补丁失败：%s' % msg)
    print('=' * 62)
    print('插件文件：%s' % PLUGIN_SWIFT)
    print('')
    print('可能原因：上游插件升级后源码结构变化，脚本锚点失配。')
    print('处理：请人工核对插件源码，更新本脚本中的 OLD_PERFORM / OLD_TOKEN 锚点后重跑。')
    print('注意：**不要**为了「让构建跑过」而注释掉本步骤——')
    print('      iPad 上的 Apple 登录会退回 error 1000，2.1(a) 必再被拒。')
    sys.exit(1)


def main() -> None:
    if not os.path.exists(PLUGIN_SWIFT):
        fail('未找到插件源码（请确认已执行 npm ci / npm install）')

    with open(PLUGIN_SWIFT, encoding='utf-8', newline='') as f:
        src = f.read()

    # ---------------- 幂等检查 ----------------
    if MARKER in src:
        print('✅ 补丁已存在（发现标记 %s），跳过。' % MARKER)
        # 仍做一次完整性自检，防止「半打补丁」
        missing = []
        if 'presentationContextProvider = self' not in src:
            missing.append('presentationContextProvider 赋值')
        if 'ASAuthorizationControllerPresentationContextProviding' not in src:
            missing.append('presentationAnchor 实现')
        if 'appleIDCredential.identityToken.flatMap' not in src:
            missing.append('identityToken 安全取值')
        if missing:
            fail('发现标记但补丁不完整，缺失：' + '、'.join(missing))
        print('   完整性自检通过（3/3）。')
        return

    original_len = len(src)

    # ---------------- 补丁 1 ----------------
    if 'presentationContextProvider = self' in src:
        # 上游若已自行修复，则无需补丁 1，但要确保主线程
        if 'DispatchQueue.main.async' not in src:
            fail('上游已有 presentationContextProvider 但未在主线程派发，需人工核对')
        print('ℹ️  上游已含 presentationContextProvider，跳过补丁 1')
    else:
        if OLD_PERFORM not in src:
            fail('补丁 1 锚点未命中（performRequests 片段与预期不符）')
        assert src.count(OLD_PERFORM) == 1, '补丁 1 锚点不唯一'
        src = src.replace(OLD_PERFORM, NEW_PERFORM)
        print('✅ 补丁 1：performRequests 已移入主线程 + 已设 presentationContextProvider')

    # ---------------- 补丁 2 ----------------
    if 'appleIDCredential.identityToken.flatMap' in src:
        print('ℹ️  上游已用安全取值，跳过补丁 2')
    else:
        if OLD_TOKEN not in src:
            fail('补丁 2 锚点未命中（identityToken 强制解包片段与预期不符）')
        assert src.count(OLD_TOKEN) == 1, '补丁 2 锚点不唯一'
        src = src.replace(OLD_TOKEN, NEW_TOKEN)
        print('✅ 补丁 2：identityToken / authorizationCode 强制解包已改安全取值')

    # ---------------- 补丁 2.5：import UIKit ----------------
    if 'import UIKit' in src:
        print('ℹ️  已含 import UIKit，跳过补丁 2.5')
    else:
        if OLD_IMPORTS not in src:
            fail('补丁 2.5 锚点未命中（import 段落与预期不符）')
        assert src.count(OLD_IMPORTS) == 1, '补丁 2.5 锚点不唯一'
        src = src.replace(OLD_IMPORTS, NEW_IMPORTS)
        print('✅ 补丁 2.5：已补充 import UIKit')

    # ---------------- 补丁 3 ----------------
    if 'ASAuthorizationControllerPresentationContextProviding' not in src:
        src = src.rstrip('\n') + '\n' + APPEND_EXTENSION
        print('✅ 补丁 3：已追加 presentationAnchor(for:) 实现')

    with open(PLUGIN_SWIFT, 'w', encoding='utf-8', newline='') as f:
        f.write(src)

    # ---------------- 落盘后自检 ----------------
    with open(PLUGIN_SWIFT, encoding='utf-8', newline='') as f:
        after = f.read()

    checks = {
        'import UIKit': 'import UIKit' in after,
        '主线程派发': 'DispatchQueue.main.async' in after,
        'presentationContextProvider 赋值': 'presentationContextProvider = self' in after,
        'presentationAnchor 实现': 'func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor' in after,
        '协议 conformance': 'extension SignInWithApple: ASAuthorizationControllerPresentationContextProviding' in after,
        # 注意：不能用 'identityToken!' 做判定——补丁自身的说明注释里也含该字样。
        # 必须针对真实解包写法（前缀 appleIDCredential.）判定。
        'identityToken 强制解包已清除': 'appleIDCredential.identityToken!' not in after,
        'authorizationCode 强制解包已清除': 'appleIDCredential.authorizationCode!' not in after,
    }
    bad = [k for k, v in checks.items() if not v]

    # 逐字断言：补丁 2 生成的 Swift 字符串行必须原样落盘
    # （曾出现过「三引号收尾粘连导致少一个引号」——自检通过但编译必败，此处兜住）
    for i, line in enumerate(EXPECTED_TOKEN_LINES, 1):
        if line not in after:
            bad.append('补丁 2 第 %d 行未按预期落盘（引号/转义异常）' % i)

    # Swift 语法底线：单引号与三引号收尾不会产生奇数个双引号
    if after.count('"') % 2 != 0:
        bad.append('文件内双引号总数为奇数，Swift 字符串字面量很可能未闭合')

    if bad:
        fail('落盘后自检未通过：' + '、'.join(bad))

    print('')
    print('补丁完成：%s' % PLUGIN_SWIFT)
    print('  文件长度 %d → %d 字节' % (original_len, len(after)))
    print('  自检 6/6 通过')
    print('')
    print('提审前请在 iPad 模拟器（横屏 + 竖屏）实测「通过 Apple 登录」必须弹出授权 sheet。')


if __name__ == '__main__':
    main()
