import Foundation
import Capacitor

/**
 * 系统外部浏览器插件（iOS），与安卓 ExternalBrowserPlugin 对齐。
 * JS 端：registerPlugin('ExternalBrowser').open({ url })
 * 通过 UIApplication.shared.open 交给 Safari 等系统浏览器，
 * 不占用 App 内 WebView，返回 App 后页面状态保持。
 */
@objc(ExternalBrowserPlugin)
public class ExternalBrowserPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "ExternalBrowserPlugin"
    public let jsName = "ExternalBrowser"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise)
    ]

    @objc public func open(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url"), let url = URL(string: urlString) else {
            call.reject("缺少有效 url")
            return
        }
        guard url.scheme == "https" || url.scheme == "http" else {
            call.reject("仅支持 http/https 链接")
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    call.resolve()
                } else {
                    call.reject("无法打开外部浏览器")
                }
            }
        }
    }
}
