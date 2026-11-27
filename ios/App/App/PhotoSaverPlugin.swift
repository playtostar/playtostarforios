import Foundation
import Capacitor
import UIKit
import Photos

/**
 * 自研「保存图片到系统相册」插件（iOS）。
 *
 * 背景：原 nativeShare 只能写缓存后弹系统分享面板，由用户手动选“存储图像”。
 * 本插件通过 PHPhotoLibrary 直接写入相册，提供更原生的保存能力（App Store 4.2
 * Minimum Functionality 差异化），并让 NSPhotoLibraryAddUsageDescription 权限声明
 * 真正被使用。仅申请 addOnly（只写不读），最小化权限。
 *
 * JS 端：registerPlugin("PhotoSaver").saveImage({ dataUrl })
 * dataUrl 形如 data:image/png;base64,xxxx；成功 resolve，失败 reject。
 */
@objc(PhotoSaverPlugin)
public class PhotoSaverPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PhotoSaverPlugin"
    public let jsName = "PhotoSaver"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "saveImage", returnType: CAPPluginReturnPromise)
    ]

    @objc public func saveImage(_ call: CAPPluginCall) {
        guard let dataUrl = call.getString("dataUrl") else {
            call.reject("缺少 dataUrl")
            return
        }

        // 去掉 data:<mime>;base64, 前缀，兼容直接传入纯 base64
        let base64: String
        if let range = dataUrl.range(of: ",") {
            base64 = String(dataUrl[range.upperBound...])
        } else {
            base64 = dataUrl
        }

        guard let data = Data(base64Encoded: base64), let image = UIImage(data: data) else {
            call.reject("图片数据无效")
            return
        }

        // 仅申请“添加”权限（iOS 14+），不读取相册
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    call.reject("未获得相册写入权限", "PHOTO_PERMISSION_DENIED")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            call.resolve()
                        } else {
                            call.reject(error?.localizedDescription ?? "保存到相册失败")
                        }
                    }
                })
            }
        }
    }
}
