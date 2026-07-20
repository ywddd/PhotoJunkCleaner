import Foundation
import UIKit
import Vision
import CoreImage

struct ClassificationResult {
    let category: JunkCategory?
    let confidence: Double
    let reasons: [String]
    let hasQRCode: Bool
    let ocrText: String
}

/// 本地 Vision 规则分类
/// - 快速模式：只跑 fast OCR + 条码，不二次精扫
/// - 精准模式：弱结果再 accurate 精扫
final class ImageClassifierService {
    static let shared = ImageClassifierService()

    /// true = 允许二次 accurate（更慢更准）
    var preciseMode: Bool = false

    private init() {
        strongTakeout = Self.prep(Self.strongTakeoutKW)
        weakTakeout = Self.prep(Self.weakTakeoutKW)
        strongLogistics = Self.prep(Self.strongLogisticsKW)
        weakLogistics = Self.prep(Self.weakLogisticsKW)
        strongPayment = Self.prep(Self.strongPaymentKW)
        weakPayment = Self.prep(Self.weakPaymentKW)
        strongVerify = Self.prep(Self.strongVerifyKW)
        strongChat = Self.prep(Self.strongChatKW)
    }

    // MARK: - 关键词分层：强特征单命中即可；弱特征需 ≥2 或组合

    private static let strongTakeoutKW: [String] = [
        "美团", "美团外卖", "饿了么", "ele.me", "eleme", "keeta",
        "抖音外卖", "京东外卖", "淘宝闪购", "蜂鸟配送", "蜂鸟",
        "meituan", "foodpanda", "uber eats",
        "再来一单", "联系骑手", "骑手正在", "预计送达", "取餐码",
        "准时宝", "外卖订单", "无需餐具", "配送费", "餐盒费",
        "肯德基", "kfc", "麦当劳", "mcdonald", "星巴克", "瑞幸",
        "必胜客", "汉堡王", "华莱士", "塔斯汀", "蜜雪冰城", "库迪"
    ]

    private static let weakTakeoutKW: [String] = [
        "外卖", "骑手", "配送中", "正在配送", "已取餐", "待取餐",
        "取餐柜", "出餐", "打包费", "神券", "满减", "起送",
        "月售", "收餐地址", "超值换购", "点外卖", "餐品"
    ]

    private static let strongLogisticsKW: [String] = [
        "顺丰", "中通", "圆通", "韵达", "申通", "极兔", "德邦",
        "菜鸟驿站", "菜鸟裹裹", "丰巢", "快递柜", "取件码",
        "京东快递", "京东物流", "运单号", "快递单号", "物流单号",
        "派件中", "派送中", "已签收", "请凭取件码", "驿站"
    ]

    private static let weakLogisticsKW: [String] = [
        "快递", "物流", "运单", "包裹", "揽收", "代收点", "自提柜",
        "快递员", "取件", "运输中"
    ]

    private static let strongPaymentKW: [String] = [
        "支付成功", "转账成功", "微信支付", "支付宝", "付款码", "收款码",
        "交易成功", "云闪付", "付款成功", "退款成功", "收款成功"
    ]

    private static let weakPaymentKW: [String] = [
        "转账", "收款", "账单", "到账", "付款", "扣款"
    ]

    private static let strongVerifyKW: [String] = [
        "验证码", "动态码", "校验码", "短信验证", "请勿泄露",
        "切勿告知", "登录验证", "otp", "verification code"
    ]

    private static let strongChatKW: [String] = [
        "按住说话", "按住 说话", "对方正在输入", "撤回了一条消息",
        "语音通话", "视频通话", "企业微信"
    ]

    private let strongTakeout: [String]
    private let weakTakeout: [String]
    private let strongLogistics: [String]
    private let weakLogistics: [String]
    private let strongPayment: [String]
    private let weakPayment: [String]
    private let strongVerify: [String]
    private let strongChat: [String]

    private static func prep(_ list: [String]) -> [String] {
        list.map { $0.lowercased() }
    }

    // MARK: - Public

    func classify(image: UIImage, isScreenshot: Bool, forceAccurate: Bool = false) async -> ClassificationResult {
        guard let cgImage = cgImage(from: image) else {
            return empty(isScreenshot: isScreenshot)
        }

        // 快路径：条码优先；有码可跳过 OCR（极大加速二维码页）
        let barcodeOnly = await detectBarcodesOnly(cgImage: cgImage)
        if barcodeOnly.hasQR || barcodeOnly.count > 0 {
            return ClassificationResult(
                category: .qrCode,
                confidence: barcodeOnly.hasQR ? 0.95 : 0.78,
                reasons: [barcodeOnly.hasQR ? "检测到二维码" : "检测到条码"],
                hasQRCode: barcodeOnly.hasQR,
                ocrText: ""
            )
        }

        let accurate = forceAccurate || preciseMode
        let pass = await ocrPass(cgImage: cgImage, accurate: accurate)
        var result = score(ocrText: pass, isScreenshot: isScreenshot)

        // 精准模式：仅当「有弱文字但未分类」才二次 accurate（快速模式永不二次）
        if preciseMode && !forceAccurate && !accurate {
            let shouldRefine =
                (result.category == nil && isScreenshot && pass.count >= 4)
                || (result.category == .genericScreenshot && pass.count >= 8)
            if shouldRefine {
                let pass2 = await ocrPass(cgImage: cgImage, accurate: true)
                let r2 = score(ocrText: pass2, isScreenshot: isScreenshot)
                if better(r2, than: result) { result = r2 }
            }
        }

        return result
    }

    private func empty(isScreenshot: Bool) -> ClassificationResult {
        ClassificationResult(
            category: isScreenshot ? .genericScreenshot : nil,
            confidence: isScreenshot ? 0.35 : 0,
            reasons: isScreenshot ? ["系统标记为截图"] : [],
            hasQRCode: false,
            ocrText: ""
        )
    }

    private func better(_ a: ClassificationResult, than b: ClassificationResult) -> Bool {
        let ar = rank(a.category)
        let br = rank(b.category)
        if ar != br { return ar > br }
        return a.confidence > b.confidence
    }

    private func rank(_ c: JunkCategory?) -> Int {
        guard let c else { return 0 }
        switch c {
        case .takeout, .logistics, .qrCode, .payment, .verification: return 3
        case .chatSnippet: return 2
        case .genericScreenshot, .otherJunk: return 1
        }
    }

    // MARK: - Vision

    private func cgImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        guard let ci = CIImage(image: image) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(ci, from: ci.extent)
    }

    private struct BarcodeHit {
        let hasQR: Bool
        let count: Int
    }

    private func detectBarcodesOnly(cgImage: CGImage) async -> BarcodeHit {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNDetectBarcodesRequest()
                // 只检 QR/常用，减少开销
                req.symbologies = [.qr, .ean13, .code128, .pdf417]
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([req])
                } catch {
                    cont.resume(returning: BarcodeHit(hasQR: false, count: 0))
                    return
                }
                let codes = (req.results as? [VNBarcodeObservation]) ?? []
                cont.resume(returning: BarcodeHit(
                    hasQR: codes.contains { $0.symbology == .qr },
                    count: codes.count
                ))
            }
        }
    }

    private func ocrPass(cgImage: CGImage, accurate: Bool) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let textReq = VNRecognizeTextRequest()
                textReq.recognitionLevel = accurate ? .accurate : .fast
                textReq.usesLanguageCorrection = false
                textReq.minimumTextHeight = accurate ? 0.012 : 0.025
                if #available(iOS 16.0, *) {
                    // 快扫只用简体+英文
                    textReq.recognitionLanguages = accurate ? ["zh-Hans", "zh-Hant", "en-US"] : ["zh-Hans", "en-US"]
                }
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([textReq])
                } catch {
                    cont.resume(returning: "")
                    return
                }
                let observations = (textReq.results as? [VNRecognizedTextObservation]) ?? []
                var lines: [String] = []
                lines.reserveCapacity(min(observations.count, 40))
                for obs in observations.prefix(60) {
                    guard let c = obs.topCandidates(1).first, c.confidence >= 0.28 else { continue }
                    lines.append(c.string)
                }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }

    // MARK: - Scoring

    private func score(ocrText: String, isScreenshot: Bool) -> ClassificationResult {
        let lower = ocrText.lowercased()
        if lower.isEmpty {
            return empty(isScreenshot: isScreenshot)
        }

        var scores: [JunkCategory: Double] = [:]
        var reasons: [JunkCategory: [String]] = [:]

        func add(_ cat: JunkCategory, _ pts: Double, _ reason: String) {
            scores[cat, default: 0] += pts
            var r = reasons[cat] ?? []
            if r.count < 5, !r.contains(reason) { r.append(reason); reasons[cat] = r }
        }

        // —— 外卖 ——
        let st = hits(lower, strongTakeout)
        if st > 0 {
            add(.takeout, min(0.98, 0.82 + Double(st - 1) * 0.05), "外卖强特征×\(st)")
        }
        let wt = hits(lower, weakTakeout)
        if wt >= 2 {
            add(.takeout, min(0.9, 0.45 + Double(wt) * 0.1), "外卖弱特征×\(wt)")
        } else if wt == 1 && st == 0 {
            // 单弱特征不够，除非截图 + 金额符号
            if isScreenshot && (ocrText.contains("¥") || ocrText.contains("￥") || lower.contains("元")) {
                add(.takeout, 0.55, "外卖弱特征+金额")
            }
        }
        if (lower.contains("骑手") || lower.contains("配送")) &&
            (lower.contains("送达") || lower.contains("取餐") || ocrText.contains("¥") || ocrText.contains("￥")) {
            add(.takeout, 0.3, "配送场景")
        }

        // —— 快递 ——
        let sl = hits(lower, strongLogistics)
        if sl > 0 {
            add(.logistics, min(0.96, 0.8 + Double(sl - 1) * 0.05), "快递强特征×\(sl)")
        }
        let wl = hits(lower, weakLogistics)
        if wl >= 2 {
            add(.logistics, min(0.88, 0.4 + Double(wl) * 0.1), "快递弱特征×\(wl)")
        }

        // —— 支付 ——
        let sp = hits(lower, strongPayment)
        if sp > 0 {
            add(.payment, min(0.95, 0.8 + Double(sp - 1) * 0.05), "支付强特征×\(sp)")
        }
        let wp = hits(lower, weakPayment)
        if wp >= 2 && isScreenshot {
            add(.payment, 0.55, "支付弱特征×\(wp)")
        }

        // —— 验证码 ——
        let sv = hits(lower, strongVerify)
        if sv > 0 {
            add(.verification, min(0.94, 0.78 + Double(sv - 1) * 0.05), "验证码特征")
        }

        // —— 聊天 ——
        let sc = hits(lower, strongChat)
        if sc > 0 && isScreenshot {
            add(.chatSnippet, min(0.85, 0.6 + Double(sc - 1) * 0.08), "聊天界面")
        }

        // 截图兜底：仅当完全没命中其它类时
        if isScreenshot && scores.isEmpty {
            // 不再把「所有截图」都当废图堆进来——只给较低置信，且需要一定文字量
            if lower.count >= 6 {
                add(.genericScreenshot, 0.36, "系统截图")
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }) else {
            return ClassificationResult(category: nil, confidence: 0, reasons: [], hasQRCode: false, ocrText: ocrText)
        }

        var conf = min(0.99, best.value)
        if (reasons[best.key]?.count ?? 0) >= 2 { conf = min(0.99, conf + 0.04) }

        // 非截图抑制误报
        if !isScreenshot {
            switch best.key {
            case .takeout, .logistics, .qrCode, .payment, .verification:
                if conf < 0.5 {
                    return ClassificationResult(category: nil, confidence: conf * 0.4, reasons: [], hasQRCode: false, ocrText: ocrText)
                }
            default:
                if conf < 0.65 {
                    return ClassificationResult(category: nil, confidence: conf * 0.3, reasons: [], hasQRCode: false, ocrText: ocrText)
                }
            }
        }

        // 普通截图置信太低则丢弃（减少 499 张全进「普通截图」）
        if best.key == .genericScreenshot && conf < 0.4 {
            return ClassificationResult(category: nil, confidence: conf, reasons: reasons[best.key] ?? [], hasQRCode: false, ocrText: ocrText)
        }

        return ClassificationResult(
            category: best.key,
            confidence: conf,
            reasons: reasons[best.key] ?? [],
            hasQRCode: false,
            ocrText: ocrText
        )
    }

    private func hits(_ lower: String, _ keys: [String]) -> Int {
        var n = 0
        for k in keys where lower.contains(k) { n += 1 }
        return n
    }
}
