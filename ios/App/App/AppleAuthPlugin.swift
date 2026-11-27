import Foundation
import Capacitor
import AuthenticationServices
import UIKit

/**
 * 自研「通过 Apple 登录」插件（iOS）。
 *
 * 背景：第三方 @capacitor-community/apple-sign-in 的原生实现创建 ASAuthorizationController
 * 后只设 delegate，未设 presentationContextProvider / 未提供 ASPresentationAnchor。
 * iPhone 靠 key window 兜底可弹，iPad（多窗口 + iPadOS）缺锚点导致授权表无法呈现，
 * 触发 App Store 2.1(a) 核心功能不可用。本插件补齐：
 *   1. presentationContextProvider，显式返回当前 key window 作为锚点；
 *   2. 所有授权操作回主线程；
 *   3. identityToken / authorizationCode 安全解包，杜绝强制解包崩溃。
 *
 * JS 端：registerPlugin("AppleAuth").authorize({ clientId, redirectURI, scopes })
 * 返回结构与第三方保持一致：{ response: { user, email, givenName, familyName,
 * identityToken, authorizationCode } }，前端可无缝切换。
 */
@objc(AppleAuthPlugin)
public class AppleAuthPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AppleAuthPlugin"
    public let jsName = "AppleAuth"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "authorize", returnType: CAPPluginReturnPromise)
    ]

    private var currentCall: CAPPluginCall?

    @objc public func authorize(_ call: CAPPluginCall) {
        // 显式回主线程（ASAuthorizationController 必须在主线程创建并呈现）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("AppleAuth 插件已释放")
                return
            }
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = self.parseScopes(call)
            if let state = call.getString("state") {
                request.state = state
            }
            if let nonce = call.getString("nonce") {
                request.nonce = nonce
            }

            self.currentCall = call
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// 解析 scope 字符串（与第三方逻辑一致：含 "name" 给全名，含 "email" 给邮箱）。
    private func parseScopes(_ call: CAPPluginCall) -> [ASAuthorization.Scope]? {
        var scopes: [ASAuthorization.Scope] = []
        if let scopesStr = call.getString("scopes") {
            if scopesStr.contains("name") {
                scopes.append(.fullName)
            }
            if scopesStr.contains("email") {
                scopes.append(.email)
            }
        }
        return scopes.isEmpty ? nil : scopes
    }

    /// 找到当前用于呈现授权表的窗口（优先本插件 WebView 所在窗口，再回退前台 key window）。
    private func anchorWindow() -> UIWindow {
        if let window = self.bridge?.viewController?.view.window ?? self.bridge?.webView?.window {
            return window
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  scene.activationState == .foregroundActive else { continue }
            if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let anyWindow = windowScene.windows.first {
                return anyWindow
            }
        }
        // 再兜底：取任意 windowScene（不限激活态）上的窗口，避免返回无 scene 的空窗
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               let anyWindow = windowScene.windows.first {
                return anyWindow
            }
        }
        // 理论上不会走到；最后才返回空 window，避免返回 nil 崩溃
        return UIWindow()
    }
}

// MARK: - 授权结果回调
extension AppleAuthPlugin: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            currentCall?.reject("Apple 凭证类型不匹配")
            currentCall = nil
            return
        }

        var response: [String: Any] = ["user": credential.user]
        if let email = credential.email {
            response["email"] = email
        }
        if let givenName = credential.fullName?.givenName {
            response["givenName"] = givenName
        }
        if let familyName = credential.fullName?.familyName {
            response["familyName"] = familyName
        }
        // 安全解包：token / code 缺失时不崩溃，由前端判空处理
        if let tokenData = credential.identityToken,
           let identityToken = String(data: tokenData, encoding: .utf8) {
            response["identityToken"] = identityToken
        }
        if let codeData = credential.authorizationCode,
           let authorizationCode = String(data: codeData, encoding: .utf8) {
            response["authorizationCode"] = authorizationCode
        }

        currentCall?.resolve(["response": response])
        currentCall = nil
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            currentCall?.reject("用户取消了登录", "ERR_CANCELED", error)
        } else {
            // 透传 domain/code，便于前端日志与下次拒审定位真实错误，不再只返回泛化消息
            let ns = error as NSError
            currentCall?.reject(
                error.localizedDescription,
                "APPLE_AUTH_\(ns.domain)_\(ns.code)",
                error
            )
        }
        currentCall = nil
    }
}

// MARK: - 提供授权表锚点（修复 iPad 无法呈现的关键）
extension AppleAuthPlugin: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return anchorWindow()
    }
}
