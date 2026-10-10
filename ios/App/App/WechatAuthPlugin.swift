import Foundation
import Capacitor
import WechatOpenSDK

/**
 * 微信「移动应用」授权登录插件（iOS）。
 * 与安卓 WechatAuthPlugin 完全对齐：JS 端 registerPlugin("WechatAuth").login() -> { code }。
 * 拿到 code 后由前端 POST 后端 /api/auth/wechat-mobile 换取业务 token；AppSecret 只在后端。
 */
@objc(WechatAuthPlugin)
public class WechatAuthPlugin: CAPPlugin, CAPBridgedPlugin {
    // CAPBridgedPlugin 必需：jsName 必须与 JS 端 registerPlugin("WechatAuth") 完全一致，
    // 否则 Capacitor 注册循环（CapacitorBridge.registerPlugins）虽能在 packageClassList
    // 找到本类，却因 `as? CapacitorPlugin`（CAPPlugin & CAPBridgedPlugin）失败而跳过，
    // 运行时报 “"WechatAuth" plugin is not implemented on ios”。
    public let identifier = "WechatAuthPlugin"
    public let jsName = "WechatAuth"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "login", returnType: CAPPluginReturnPromise)
    ]

    private static let appId = "wxd0ef5d487ac33750"
    private static let universalLink = "https://playtostar.com/app/"

    private var savedCall: CAPPluginCall?

    override public func load() {
        WXApi.registerApp(Self.appId, universalLink: Self.universalLink)

        // 自定义 scheme 回调（旧路径）
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenUrl(_:)),
            name: .capacitorOpenURL, object: nil)
        // Universal Link 回调（新路径）。Capacitor 通知里给的是 URL，
        // 微信需要 NSUserActivity，这里用 URL 重建。
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleUniversalLink(_:)),
            name: .capacitorOpenUniversalLink, object: nil)
    }

    @objc public func login(_ call: CAPPluginCall) {
        guard WXApi.isWXAppInstalled() else {
            call.reject("未安装微信客户端")
            return
        }
        savedCall = call
        let req = SendAuthReq()
        req.scope = "snsapi_userinfo"
        req.state = "playtostar_auth"
        WXApi.send(req) { [weak self] success in
            if !success {
                call.reject("拉起微信失败")
                self?.savedCall = nil
            }
        }
    }

    /// Capacitor 以 object 字典（["url": URL]）形式 post，兼容 userInfo / 直接 URL。
    private func url(from notification: Notification) -> URL? {
        if let dict = notification.object as? [String: Any], let u = dict["url"] as? URL {
            return u
        }
        if let u = notification.userInfo?["url"] as? URL {
            return u
        }
        return notification.object as? URL
    }

    @objc private func handleOpenUrl(_ notification: Notification) {
        guard let url = url(from: notification) else { return }
        _ = WXApi.handleOpen(url, delegate: self)
    }

    @objc private func handleUniversalLink(_ notification: Notification) {
        guard let url = url(from: notification) else { return }
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        WXApi.handleOpenUniversalLink(activity, delegate: self)
    }
}

extension WechatAuthPlugin: WXApiDelegate {
    public func onReq(_ req: BaseReq) {
        // 微信向本 App 发起请求；登录场景无需处理
    }

    public func onResp(_ resp: BaseResp) {
        guard let auth = resp as? SendAuthResp else { return }
        if auth.errCode == 0, let code = auth.code, !code.isEmpty {
            savedCall?.resolve(["code": code])
        } else {
            let msg = auth.errStr.isEmpty ? "微信授权失败或已取消" : auth.errStr
            savedCall?.reject(msg)
        }
        savedCall = nil
    }
}
