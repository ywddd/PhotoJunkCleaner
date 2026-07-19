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

/// 基于 Vision OCR + 条码检测的规则分类（本地完成，无网络）
final class ImageClassifierService {
    static let shared = ImageClassifierService()
    private init() {}

    // MARK: - Keywords（外卖 / 快递 / 支付 / 验证码 / 聊天）

    private let takeoutKeywords: [String] = [
        // 平台
        "美团", "饿了么", "外卖", "美团外卖", "饿了么会员", "蜂鸟", "蜂鸟配送",
        "Meituan", "Ele.me", "ele.me", "Keeta", "Foodpanda", "Uber Eats",
        "抖音外卖", "京东外卖", "淘宝闪购", "口碑", "到家美食会",
        // 配送状态
        "配送中", "预计送达", "骑手", "骑手正在", "正在配送", "已取餐",
        "取餐码", "取餐号", "取餐柜", "餐柜", "订单已送达", "已送达",
        "待配送", "待取餐", "商家已接单", "骑手已接单", "骑手距你",
        "距离你", "预计", "分钟送达", "准时宝", "超时赔",
        // 订单 UI
        "订单详情", "再来一单", "联系商家", "联系骑手", "配送费", "打包费",
        "餐盒费", "红包", "满减", "神券", "商家", "本单", "实付", "合计",
        "到店自取", "自取", "餐具", "无需餐具", "备注", "口味",
        "热门榜", "好评如潮", "月售", "起送", "配送约",
        // 常见文案
        "美食配送", "外卖订单", "订单编号", "下单时间", "收餐地址",
        "肯德基", "KFC", "麦当劳", "McDonald", "星巴克", "瑞幸", "奈雪", "喜茶",
        "必胜客", "汉堡王", "德克士", "华莱士", "塔斯汀", "库迪", "蜜雪冰城",
        "立即支付", "待配送", "已接单", "出餐中", "超值换购", "商品金额"
    ]

    private let logisticsKeywords: [String] = [
        // 快递公司
        "快递", "物流", "运单", "运单号", "快递单号", "物流单号", "追踪号",
        "顺丰", "顺丰速运", "中通", "圆通", "韵达", "申通", "百世", "极兔",
        "京东快递", "京东物流", "德邦", "德邦快递", "EMS", "邮政", "中国邮政",
        "菜鸟", "菜鸟驿站", "驿站", "丰巢", "快递柜", "自提柜", "代收点",
        "闪送", "UU跑腿", "达达", "同城急送", "货拉拉",
        "SF Express", "YTO", "ZTO", "STO", "Yunda", "JD Logistics",
        // 状态
        "派送中", "派件中", "已签收", "待取件", "待取件码", "取件码",
        "取件通知", "已到达", "运输中", "已揽收", "已发货", "出库",
        "派送员", "快递员", "快递员电话", "驿站代收", "柜机",
        "请凭取件码", "保管码", "超时将", "滞留", "退回",
        // 通用
        "物流详情", "物流信息", "包裹", "收件人", "寄件人", "签收",
        "菜鸟裹裹", "裹裹", "快递已到", "请及时取件", "货架号"
    ]

    private let paymentKeywords: [String] = [
        "支付成功", "收款", "转账", "微信支付", "支付宝", "付款码", "收款码",
        "已付款", "交易成功", "账单", "零钱", "余额", "到账", "转账成功",
        "支付方式", "实付", "退款成功", "红包金额", "收钱", "付款给",
        "商家收款", "扫码支付", "付款成功", "扣款", "入账", "提现",
        "云闪付", "银联", "信用卡", "借记卡", "账单详情", "消费记录"
    ]

    private let verificationKeywords: [String] = [
        "验证码", "动态码", "安全码", "登录验证", "校验码", "短信验证",
        "verification code", "OTP", "一次性密码", "安全验证",
        "请勿泄露", "切勿告知", "有效期", "分钟内有效", "登录码",
        "身份验证", "二次验证", "两步验证", "动态密码"
    ]

    private let chatKeywords: [String] = [
        "微信", "WeChat", "会话", "按住 说话", "按住说话", "发送",
        "消息已发出", "对方正在输入", "语音通话", "视频通话",
        "企业微信", "QQ", "钉钉", "飞书", "Telegram", "WhatsApp",
        "撤回了一条消息", "引用", "转发", "表情", "贴纸"
    ]

    private let junkUIHints: [String] = [
        "截屏", "Screenshot", "屏幕截图", "电池", "运营商", "Carrier"
    ]

    // MARK: - Public

    func classify(image: UIImage, isScreenshot: Bool) async -> ClassificationResult {
        let cgImage: CGImage? = await MainActor.run {
            if let cg = image.cgImage { return cg }
            guard let ci = CIImage(image: image) else { return nil }
            return CIContext(options: nil).createCGImage(ci, from: ci.extent)
        }
        guard let cgImage else {
            return ClassificationResult(
                category: isScreenshot ? .genericScreenshot : nil,
                confidence: isScreenshot ? 0.4 : 0,
                reasons: isScreenshot ? ["系统标记为截图"] : [],
                hasQRCode: false,
                ocrText: ""
            )
        }

        async let barcodes = detectBarcodes(cgImage: cgImage)
        async let text = recognizeText(cgImage: cgImage)
        let (codes, ocr) = await (barcodes, text)
        let hasQR = codes.contains { $0.symbology == .qr }

        return score(
            ocrText: ocr,
            hasQRCode: hasQR,
            barcodeCount: codes.count,
            isScreenshot: isScreenshot
        )
    }

    // MARK: - Vision

    private func detectBarcodes(cgImage: CGImage) async -> [VNBarcodeObservation] {
        await withCheckedContinuation { cont in
            let request = VNDetectBarcodesRequest { request, _ in
                let results = (request.results as? [VNBarcodeObservation]) ?? []
                cont.resume(returning: results)
            }
            request.symbologies = [.qr, .aztec, .dataMatrix, .ean13, .ean8, .code128, .pdf417]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(returning: [])
            }
        }
    }

    private func recognizeText(cgImage: CGImage) async -> String {
        await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            if #available(iOS 16.0, *) {
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(returning: "")
            }
        }
    }

    // MARK: - Scoring

    private func score(
        ocrText: String,
        hasQRCode: Bool,
        barcodeCount: Int,
        isScreenshot: Bool
    ) -> ClassificationResult {
        let text = ocrText
        var reasons: [String] = []
        var best: (JunkCategory, Double)?

        func bump(_ category: JunkCategory, _ conf: Double, _ reason: String) {
            if !reasons.contains(reason) {
                reasons.append(reason)
            }
            if let cur = best {
                if conf > cur.1 { best = (category, conf) }
            } else {
                best = (category, conf)
            }
        }

        // 条码 / 二维码
        if hasQRCode {
            bump(.qrCode, 0.95, "检测到二维码")
        } else if barcodeCount > 0 {
            bump(.qrCode, 0.75, "检测到条码")
        }

        let takeoutHits = countHits(text, takeoutKeywords)
        if takeoutHits >= 2 {
            bump(.takeout, min(0.98, 0.62 + Double(takeoutHits) * 0.08), "外卖关键词 ×\(takeoutHits)")
        } else if takeoutHits == 1 {
            // 单关键词也识别（美团/饿了么等强特征）
            bump(.takeout, 0.72, "外卖关键词 ×1")
        }

        let logisticsHits = countHits(text, logisticsKeywords)
        if logisticsHits >= 2 {
            bump(.logistics, min(0.95, 0.55 + Double(logisticsHits) * 0.08), "快递关键词 ×\(logisticsHits)")
        } else if logisticsHits == 1 {
            bump(.logistics, 0.52, "快递关键词 ×1")
        }

        let payHits = countHits(text, paymentKeywords)
        if payHits >= 2 {
            bump(.payment, min(0.92, 0.55 + Double(payHits) * 0.1), "支付关键词 ×\(payHits)")
        } else if payHits == 1 && isScreenshot {
            bump(.payment, 0.5, "支付关键词 ×1")
        }

        let verHits = countHits(text, verificationKeywords)
        if verHits >= 1 {
            bump(.verification, min(0.9, 0.6 + Double(verHits) * 0.1), "验证码关键词")
        }

        let chatHits = countHits(text, chatKeywords)
        if chatHits >= 2 && isScreenshot {
            bump(.chatSnippet, min(0.85, 0.5 + Double(chatHits) * 0.1), "聊天界面特征")
        }

        // 二维码页：保留为 qrCode，附加其它命中原因
        if hasQRCode {
            if takeoutHits > 0 { reasons.append("含外卖相关文字") }
            if logisticsHits > 0 { reasons.append("含快递相关文字") }
            return ClassificationResult(
                category: .qrCode,
                confidence: best?.1 ?? 0.95,
                reasons: reasons.isEmpty ? ["检测到二维码"] : reasons,
                hasQRCode: true,
                ocrText: text
            )
        }

        if let best {
            return ClassificationResult(
                category: best.0,
                confidence: best.1,
                reasons: reasons,
                hasQRCode: false,
                ocrText: text
            )
        }

        if isScreenshot {
            let uiHits = countHits(text, junkUIHints)
            return ClassificationResult(
                category: .genericScreenshot,
                confidence: uiHits > 0 ? 0.55 : 0.45,
                reasons: ["系统标记为截图"] + (uiHits > 0 ? ["界面文字特征"] : []),
                hasQRCode: false,
                ocrText: text
            )
        }

        return ClassificationResult(
            category: nil,
            confidence: 0,
            reasons: [],
            hasQRCode: false,
            ocrText: text
        )
    }

    private func countHits(_ text: String, _ keywords: [String]) -> Int {
        let lower = text.lowercased()
        var count = 0
        for k in keywords {
            if lower.contains(k.lowercased()) {
                count += 1
            }
        }
        return count
    }
}
