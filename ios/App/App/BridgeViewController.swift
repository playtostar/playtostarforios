import UIKit
import Capacitor

/**
 * 自定义桥接控制器。
 * 根因：Capacitor 8 用 SPM 集成时，node_modules 里的插件（App/Share/StatusBar 等）
 * 会随 SPM 包清单被自动注册；但直接放在 App target 内的「本地自定义插件」
 * WechatAuthPlugin 不属于任何 SPM 包、不在自动注册清单里，即使它：
 *   - 在 Compile Sources、二进制里有类符号、实现了 CAPBridgedPlugin，
 * 运行时仍报 “"WechatAuth" plugin is not implemented on ios”。
 * 解法（官方 Custom Native iOS Code）：在 capacitorDidLoad（bridge 已建好、
 * JS 开始加载之前）显式 registerPluginInstance。SceneDelegate 用本控制器
 * 替换默认 CAPBridgeViewController，注入确定生效、不依赖 storyboard。
 */
class BridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(WechatAuthPlugin())
    }
}
