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

/// 本地 Vision 规则分类：快扫(fast) + 必要时精扫(accurate)
final class ImageClassifierService {
    static let shared = ImageClassifierService()
    private init() {
        // 预编译小写关键词，避免每张图重复 lowercased()
        takeoutFast = Self.prep(Self.takeoutStrong)
        takeoutAll = Self.prep(Self.takeoutKeywords)
        logisticsAll = Self.prep(Self.logisticsKeywords)
        paymentAll = Self.prep(Self.paymentKeywords)
        verificationAll = Self.prep(Self.verificationKeywords)
        chatAll = Self.prep(Self.chatKeywords)
        junkUIAll = Self.prep(Self.junkUIHints)
    }

    // MARK: - 强特征（单命中即可）

    private static let takeoutStrong: [String] = [
        "美团", "美团外卖", "饿了么", "ele.me", "eleme", "keeta", "抖音外卖", "京东外卖",
        "淘宝闪购", "蜂鸟配送", "外卖订单", "再来一单", "联系骑手", "骑手正在",
        "预计送达", "取餐码", "准时宝", "meituan", "foodpanda", "uber eats"
    ]

    private static let takeoutKeywords: [String] = [
        "美团", "饿了么", "外卖", "美团外卖", "饿了么会员", "蜂鸟", "蜂鸟配送",
        "Meituan", "Ele.me", "ele.me", "Keeta", "Foodpanda", "Uber Eats",
        "抖音外卖", "京东外卖", "淘宝闪购", "口碑",
        "配送中", "预计送达", "骑手", "骑手正在", "正在配送", "已取餐",
        "取餐码", "取餐号", "取餐柜", "餐柜", "订单已送达", "已送达",
        "待配送", "待取餐", "商家已接单", "骑手已接单", "骑手距你",
        "分钟送达", "准时宝", "超时赔",
        "订单详情", "再来一单", "联系商家", "联系骑手", "配送费", "打包费",
        "餐盒费", "神券", "本单", "实付", "无需餐具",
        "月售", "起送", "配送约", "美食配送", "外卖订单", "收餐地址",
        "肯德基", "KFC", "麦当劳", "McDonald", "星巴克", "瑞幸", "奈雪", "喜茶",
        "必胜客", "汉堡王", "德克士", "华莱士", "塔斯汀", "库迪", "蜜雪冰城",
        "立即支付", "出餐中", "超值换购", "商品金额", "餐品", "点外卖"
    ]

    private static let logisticsKeywords: [String] = [
        "快递", "物流", "运单", "运单号", "快递单号", "物流单号", "追踪号",
        "顺丰", "顺丰速运", "中通", "圆通", "韵达", "申通", "百世", "极兔",
        "京东快递", "京东物流", "德邦", "EMS", "邮政", "中国邮政",
        "菜鸟", "菜鸟驿站", "驿站", "丰巢", "快递柜", "自提柜", "代收点",
        "闪送", "UU跑腿", "达达", "同城急送",
        "派送中", "派件中", "已签收", "待取件", "取件码", "取件通知",
        "运输中", "已揽收", "已发货", "快递员", "驿站代收",
        "请凭取件码", "保管码", "物流详情", "物流信息", "包裹",
        "菜鸟裹裹", "快递已到", "请及时取件", "货架号", "取件"
    ]

    private static let paymentKeywords: [String] = [
        "支付成功", "收款成功", "转账成功", "微信支付", "支付宝", "付款码", "收款码",
        "已付款", "交易成功", "到账", "付款给", "商家收款", "扫码支付",
        "付款成功", "退款成功", "云闪付", "银联", "账单详情", "消费记录",
        "转账", "收款", "零钱"
    ]

    private static let verificationKeywords: [String] = [
        "验证码", "动态码", "安全码", "登录验证", "校验码", "短信验证",
        "verification code", "OTP", "一次性密码", "请勿泄露", "切勿告知",
        "分钟内有效", "登录码", "身份验证", "二次验证", "两步验证", "动态密码"
    ]

    private static let chatKeywords: [String] = [
        "微信", "WeChat", "按住 说话", "按住说话",
        "对方正在输入", "语音通话", "视频通话",
        "企业微信", "钉钉", "飞书", "Telegram", "WhatsApp",
        "撤回了一条消息"
    ]

    private static let junkUIHints: [String] = [
        "截屏", "Screenshot", "屏幕截图"
    ]

    private let takeoutFast: [(raw: String, low: String)]
    private let takeoutAll: [(raw: String, low: String)]
    private let logisticsAll: [(raw: String, low: String)]
    private let paymentAll: [(raw: String, low: String)]
    private let verificationAll: [(raw: String, low: String)]
    private let chatAll: [(raw: String, low: String)]
    private let junkUIAll: [(raw: String, low: String)]

    private static func prep(_ list: [String]) -> [(raw: String, low: String)] {
        list.map { ($0, $0.lowercased()) }
    }

    // MARK: - Public

    /// 主入口：默认 fast OCR；置信模糊时再 accurate 精扫
    func classify(image: UIImage, isScreenshot: Bool, forceAccurate: Bool = false) async -> ClassificationResult {
        guard let cgImage = cgImage(from: image) else {
            return ClassificationResult(
                category: isScreenshot ? .genericScreenshot : nil,
                confidence: isScreenshot ? 0.4 : 0,
                reasons: isScreenshot ? ["系统标记为截图"] : [],
                hasQRCode: false,
                ocrText: ""
            )
        }

        // 1) 条码 + 快速 OCR 同一次 perform
        let first = await visionPass(cgImage: cgImage, accurate: forceAccurate)
        var result = score(
            ocrText: first.text,
            hasQRCode: first.hasQR,
            barcodeCount: first.barcodeCount,
            isScreenshot: isScreenshot
        )

        // 2) 需要精扫的情况：截图但类别弱 / 非截图有弱命中
        let needRefine: Bool = {
            if forceAccurate { return false }
            if first.hasQR { return false } // 二维码已够准
            guard let cat = result.category else {
                // 截图无命中：精扫一次，可能漏了外卖字
                return isScreenshot && !first.text.isEmpty
            }
            if cat == .genericScreenshot { return true }
            if result.confidence < 0.55 { return true }
            return false
        }()

        if needRefine {
            let second = await visionPass(cgImage: cgImage, accurate: true)
            let refined = score(
                ocrText: second.text,
                hasQRCode: second.hasQR || first.hasQR,
                barcodeCount: max(second.barcodeCount, first.barcodeCount),
                isScreenshot: isScreenshot
            )
            // 精扫结果更好则采用
            if (refined.category != nil && refined.confidence >= result.confidence)
                || (result.category == .genericScreenshot && refined.category != .genericScreenshot) {
                result = refined
            }
        }

        return result
    }

    // MARK: - Image helpers

    private func cgImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        guard let ci = CIImage(image: image) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(ci, from: ci.extent)
    }

    private struct VisionPass {
        let text: String
        let hasQR: Bool
        let barcodeCount: Int
    }

    /// 条码 + OCR 一次 handler.perform，显著减少开销
    private func visionPass(cgImage: CGImage, accurate: Bool) async -> VisionPass {
        await withCheckedContinuation { cont in
            // 在后台队列执行 Vision，避免占主线程
            DispatchQueue.global(qos: .userInitiated).async {
                let barcodeReq = VNDetectBarcodesRequest()
                barcodeReq.symbologies = [.qr, .aztec, .dataMatrix, .ean13, .ean8, .code128, .pdf417]

                let textReq = VNRecognizeTextRequest()
                textReq.recognitionLevel = accurate ? .accurate : .fast
                textReq.usesLanguageCorrection = false
                // 快扫只要前若干候选，加速
                textReq.minimumTextHeight = accurate ? 0.015 : 0.02
                if #available(iOS 16.0, *) {
                    textReq.recognitionLanguages = ["zh-Hans", "en-US"]
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([barcodeReq, textReq])
                } catch {
                    cont.resume(returning: VisionPass(text: "", hasQR: false, barcodeCount: 0))
                    return
                }

                let codes = (barcodeReq.results as? [VNBarcodeObservation]) ?? []
                let hasQR = codes.contains { $0.symbology == .qr }
                let observations = (textReq.results as? [VNRecognizedTextObservation]) ?? []
                // 只取高置信行，减少噪声
                let lines: [String] = observations.compactMap { obs in
                    guard let c = obs.topCandidates(1).first else { return nil }
                    if c.confidence < 0.25 { return nil }
                    return c.string
                }
                cont.resume(returning: VisionPass(
                    text: lines.joined(separator: "\n"),
                    hasQR: hasQR,
                    barcodeCount: codes.count
                ))
            }
        }
    }

    // MARK: - Scoring（加权）

    private func score(
        ocrText: String,
        hasQRCode: Bool,
        barcodeCount: Int,
        isScreenshot: Bool
    ) -> ClassificationResult {
        let lower = ocrText.lowercased()
        var scores: [JunkCategory: Double] = [:]
        var reasons: [JunkCategory: [String]] = [:]

        func add(_ cat: JunkCategory, _ points: Double, _ reason: String) {
            scores[cat, default: 0] += points
            if reasons[cat, default: []].count < 6, !reasons[cat, default: []].contains(reason) {
                reasons[cat, default: []].append(reason)
            }
        }

        // 强外卖品牌
        let strongHits = countHits(lower, takeoutFast)
        if strongHits > 0 {
            add(.takeout, min(0.95, 0.78 + Double(strongHits - 1) * 0.06), "外卖平台/强特征 ×\(strongHits)")
        }

        let takeoutHits = countHits(lower, takeoutAll)
        if takeoutHits > 0 {
            add(.takeout, min(0.9, 0.35 + Double(takeoutHits) * 0.12), "外卖关键词 ×\(takeoutHits)")
        }

        // 组合信号：配送 + 金额
        if (lower.contains("配送") || lower.contains("骑手") || lower.contains("送达"))
            && (ocrText.contains("¥") || ocrText.contains("￥") || lower.contains("实付") || lower.contains("合计")) {
            add(.takeout, 0.28, "配送+金额")
        }

        let logisticsHits = countHits(lower, logisticsAll)
        if logisticsHits > 0 {
            add(.logistics, min(0.95, 0.4 + Double(logisticsHits) * 0.12), "快递关键词 ×\(logisticsHits)")
        }
        if lower.contains("取件码") || lower.contains("快递柜") || lower.contains("驿站") {
            add(.logistics, 0.25, "取件场景")
        }

        let payHits = countHits(lower, paymentAll)
        if payHits > 0 {
            add(.payment, min(0.92, 0.4 + Double(payHits) * 0.12), "支付关键词 ×\(payHits)")
        }

        let verHits = countHits(lower, verificationAll)
        if verHits > 0 {
            add(.verification, min(0.92, 0.55 + Double(verHits) * 0.12), "验证码关键词")
        }

        let chatHits = countHits(lower, chatAll)
        if chatHits >= 1 && isScreenshot {
            add(.chatSnippet, min(0.85, 0.4 + Double(chatHits) * 0.12), "聊天界面")
        }

        if hasQRCode {
            add(.qrCode, 0.9, "检测到二维码")
        } else if barcodeCount > 0 {
            add(.qrCode, 0.7, "检测到条码")
        }

        // 截图兜底
        if isScreenshot && scores.isEmpty {
            let ui = countHits(lower, junkUIAll)
            add(.genericScreenshot, ui > 0 ? 0.5 : 0.4, "系统截图")
        } else if isScreenshot {
            let top = scores.values.max() ?? 0
            if top < 0.45 {
                add(.genericScreenshot, 0.42, "系统截图")
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }) else {
            return ClassificationResult(category: nil, confidence: 0, reasons: [], hasQRCode: hasQRCode, ocrText: ocrText)
        }

        var conf = min(0.99, best.value)
        // 多信号加成
        if (reasons[best.key]?.count ?? 0) >= 2 { conf = min(0.99, conf + 0.05) }

        // 非截图且弱信号：抑制误报（实拍风景等）
        if !isScreenshot && conf < 0.48 && best.key != .qrCode && best.key != .takeout && best.key != .logistics {
            return ClassificationResult(category: nil, confidence: conf * 0.4, reasons: [], hasQRCode: hasQRCode, ocrText: ocrText)
        }
        if !isScreenshot && conf < 0.38 {
            return ClassificationResult(category: nil, confidence: conf * 0.3, reasons: [], hasQRCode: hasQRCode, ocrText: ocrText)
        }

        return ClassificationResult(
            category: best.key,
            confidence: conf,
            reasons: reasons[best.key] ?? [],
            hasQRCode: hasQRCode,
            ocrText: ocrText
        )
    }

    private func countHits(_ lowerText: String, _ keywords: [(raw: String, low: String)]) -> Int {
        var count = 0
        for k in keywords {
            if lowerText.contains(k.low) { count += 1 }
        }
        return count
    }
}
