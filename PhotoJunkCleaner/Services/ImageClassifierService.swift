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

/// 本地 Vision 规则分类（v1.6）
/// - 快速：条码优先 + fast OCR，无二次精扫
/// - 精准：弱结果可 accurate 精扫
final class ImageClassifierService {
    static let shared = ImageClassifierService()

    var preciseMode: Bool = false
    /// 是否跑内置 MobileNet（由设置控制）
    var useLocalML: Bool = true

    private init() {
        strongTakeout = Self.prep(Self.strongTakeoutKW)
        weakTakeout = Self.prep(Self.weakTakeoutKW)
        strongLogistics = Self.prep(Self.strongLogisticsKW)
        weakLogistics = Self.prep(Self.weakLogisticsKW)
        strongPayment = Self.prep(Self.strongPaymentKW)
        weakPayment = Self.prep(Self.weakPaymentKW)
        strongVerify = Self.prep(Self.strongVerifyKW)
        weakNotify = Self.prep(Self.weakNotifyKW)
        strongChat = Self.prep(Self.strongChatKW)
        weakChat = Self.prep(Self.weakChatKW)
        otherJunk = Self.prep(Self.otherJunkKW)
    }

    // MARK: - 关键词

    private static let strongTakeoutKW: [String] = [
        "美团", "美团外卖", "饿了么", "ele.me", "eleme", "keeta",
        "抖音外卖", "京东外卖", "淘宝闪购", "蜂鸟配送", "蜂鸟",
        "meituan", "foodpanda", "uber eats",
        "再来一单", "联系骑手", "骑手正在", "预计送达", "取餐码",
        "准时宝", "外卖订单", "无需餐具", "配送费", "餐盒费",
        "肯德基", "kfc", "麦当劳", "mcdonald", "星巴克", "瑞幸",
        "必胜客", "汉堡王", "华莱士", "塔斯汀", "蜜雪冰城", "库迪",
        "奈雪", "喜茶", "外卖已送达", "商家已接单", "骑手已接单"
    ]

    private static let weakTakeoutKW: [String] = [
        "外卖", "骑手", "配送中", "正在配送", "已取餐", "待取餐",
        "取餐柜", "出餐", "打包费", "神券", "满减", "起送",
        "月售", "收餐地址", "超值换购", "点外卖", "餐品", "送餐",
        "预订单", "立即配送"
    ]

    private static let strongLogisticsKW: [String] = [
        "顺丰", "中通", "圆通", "韵达", "申通", "极兔", "德邦", "百世",
        "菜鸟驿站", "菜鸟裹裹", "丰巢", "快递柜", "取件码",
        "京东快递", "京东物流", "运单号", "快递单号", "物流单号",
        "派件中", "派送中", "已签收", "请凭取件码", "驿站",
        "ems", "中国邮政", "邮政快递"
    ]

    private static let weakLogisticsKW: [String] = [
        "快递", "物流", "运单", "包裹", "揽收", "代收点", "自提柜",
        "快递员", "取件", "运输中", "待取件", "已发货", "出库"
    ]

    private static let strongPaymentKW: [String] = [
        "支付成功", "转账成功", "微信支付", "支付宝", "付款码", "收款码",
        "交易成功", "云闪付", "付款成功", "退款成功", "收款成功",
        "已付款", "付款给", "收钱码", "扫码支付", "商家收款",
        "账单详情", "消费成功", "转账给", "零钱通"
    ]

    private static let weakPaymentKW: [String] = [
        "转账", "收款", "账单", "到账", "付款", "扣款", "退款",
        "余额", "零钱", "实付", "入账", "提现"
    ]

    /// 验证码
    private static let strongVerifyKW: [String] = [
        "验证码", "动态码", "校验码", "短信验证", "请勿泄露",
        "切勿告知", "登录验证", "otp", "verification code",
        "一次性密码", "安全码", "登录码", "动态密码",
        "两步验证", "二次验证", "身份验证", "分钟内有效"
    ]

    /// 通知 / 系统提示（与验证码同属 verification 展示类）
    private static let weakNotifyKW: [String] = [
        "通知", "推送", "系统通知", "消息通知", "服务通知",
        "未读消息", "条新消息", "新通知", "通知中心",
        "锁屏通知", "横幅", "提醒事项", "日历提醒",
        "验证提醒", "安全提醒", "登录提醒", "异常登录",
        "设备登录", "新设备", "短信", "验证短信"
    ]

    private static let strongChatKW: [String] = [
        "按住说话", "按住 说话", "对方正在输入", "撤回了一条消息",
        "语音通话", "视频通话", "企业微信", "消息已发出",
        "引用", "转发了", "会话", "发消息"
    ]

    private static let weakChatKW: [String] = [
        "微信", "wechat", "weixin", "qq", "钉钉", "飞书",
        "telegram", "whatsapp", "聊天", "对话框",
        "发送", "表情", "语音", "图片消息"
    ]

    /// 其它常见「临时废图」：电商订单确认、游戏战绩、广告落地等
    private static let otherJunkKW: [String] = [
        "订单详情", "待付款", "待发货", "待收货", "确认收货",
        "拼多多", "淘宝", "天猫", "京东", "抖音商城",
        "立即购买", "加入购物车", "优惠券", "领券",
        "游戏战绩", "本局结算", "击杀", "胜利", "失败结算",
        "广告", "点击下载", "立即下载", "打开app", "应用商店",
        "邀请码", "助力", "砍一刀", "免费领",
        "行程卡", "健康码", "核酸", // 历史遗留截图
        "临时", "一次性", "截图保存"
    ]

    private let strongTakeout: [String]
    private let weakTakeout: [String]
    private let strongLogistics: [String]
    private let weakLogistics: [String]
    private let strongPayment: [String]
    private let weakPayment: [String]
    private let strongVerify: [String]
    private let weakNotify: [String]
    private let strongChat: [String]
    private let weakChat: [String]
    private let otherJunk: [String]

    private static func prep(_ list: [String]) -> [String] {
        list.map { $0.lowercased() }
    }

    // MARK: - Public

    func classify(image: UIImage, isScreenshot: Bool, forceAccurate: Bool = false) async -> ClassificationResult {
        guard let cgImage = cgImage(from: image) else {
            return empty(isScreenshot: isScreenshot)
        }

        // 条码优先：有码直接归二维码
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

        // 系统图像分类（零包体）+ 快速 OCR 并行
        async let sceneTask = sceneHints(cgImage: cgImage)
        async let ocrTask = ocrPass(cgImage: cgImage, accurate: forceAccurate)
        let (scene, pass) = await (sceneTask, ocrTask)

        // 明显「正常自然照片」且几乎无文字 → 直接跳过（大幅提速 + 降误报）
        if !isScreenshot && scene.looksLikeNormalPhoto && pass.count < 8 {
            return ClassificationResult(
                category: nil,
                confidence: 0,
                reasons: scene.topReasons,
                hasQRCode: false,
                ocrText: pass
            )
        }

        var result = score(ocrText: pass, isScreenshot: isScreenshot, hasQR: false, scene: scene)

        // 精准模式：仅弱结果二次 accurate
        if preciseMode && !forceAccurate {
            let shouldRefine =
                (result.category == nil && isScreenshot && pass.count >= 4)
                || (result.category == .genericScreenshot)
                || (result.category == .otherJunk && result.confidence < 0.55)
                || (result.confidence > 0 && result.confidence < 0.5)
            if shouldRefine {
                let pass2 = await ocrPass(cgImage: cgImage, accurate: true)
                let r2 = score(ocrText: pass2, isScreenshot: isScreenshot, hasQR: false, scene: scene)
                if better(r2, than: result) { result = r2 }
            }
        }

        return result
    }

    private func empty(isScreenshot: Bool) -> ClassificationResult {
        ClassificationResult(
            category: isScreenshot ? .genericScreenshot : nil,
            confidence: isScreenshot ? 0.55 : 0,
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
        case .takeout, .logistics, .qrCode, .payment, .verification: return 4
        case .chatSnippet: return 3
        case .otherJunk: return 2
        case .genericScreenshot: return 1
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
                req.symbologies = [.qr, .ean13, .ean8, .code128, .pdf417, .aztec, .dataMatrix]
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
                textReq.minimumTextHeight = accurate ? 0.012 : 0.022
                if #available(iOS 16.0, *) {
                    textReq.recognitionLanguages = accurate
                        ? ["zh-Hans", "zh-Hant", "en-US"]
                        : ["zh-Hans", "en-US"]
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
                lines.reserveCapacity(min(observations.count, 48))
                for obs in observations.prefix(80) {
                    guard let c = obs.topCandidates(1).first, c.confidence >= 0.25 else { continue }
                    lines.append(c.string)
                }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }


    // MARK: - System image classification (zero extra model size)

    struct SceneHints {
        var foodScore: Double = 0
        var packageScore: Double = 0
        var documentScore: Double = 0
        var screenUIScore: Double = 0
        var natureScore: Double = 0
        var personScore: Double = 0
        var topReasons: [String] = []

        static let empty = SceneHints()

        /// 更像正常相册照片（人物/风景/宠物），而非截图废图
        var looksLikeNormalPhoto: Bool {
            let natural = max(natureScore, personScore)
            return natural >= 0.45 && documentScore < 0.35 && screenUIScore < 0.35
        }
    }

    private func sceneHints(cgImage: CGImage) async -> SceneHints {
        // 系统 Vision 分类 + 可选内置 MobileNet
        async let system = systemSceneHints(cgImage: cgImage)
        if useLocalML && LocalMLService.shared.isReady {
            async let mobile = LocalMLService.shared.classifyScene(cgImage: cgImage)
            let (a, b) = await (system, mobile)
            return mergeScenes(a, b)
        } else {
            return await system
        }
    }

    private func mergeScenes(_ a: SceneHints, _ b: SceneHints) -> SceneHints {
        var m = SceneHints()
        m.foodScore = max(a.foodScore, b.foodScore)
        m.packageScore = max(a.packageScore, b.packageScore)
        m.documentScore = max(a.documentScore, b.documentScore)
        m.screenUIScore = max(a.screenUIScore, b.screenUIScore)
        m.natureScore = max(a.natureScore, b.natureScore)
        m.personScore = max(a.personScore, b.personScore)
        var reasons: [String] = []
        if LocalMLService.shared.isReady {
            reasons.append(contentsOf: b.topReasons.prefix(2).map { "ML:\($0)" })
        }
        reasons.append(contentsOf: a.topReasons.prefix(2))
        m.topReasons = Array(reasons.prefix(4))
        return m
    }

    private func systemSceneHints(cgImage: CGImage) async -> SceneHints {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(returning: .empty)
                    return
                }
                let obs = (request.results as? [VNClassificationObservation]) ?? []
                var hints = SceneHints()
                var tops: [String] = []
                for o in obs.prefix(12) {
                    let id = o.identifier.lowercased()
                    let c = Double(o.confidence)
                    if c < 0.12 { continue }
                    if tops.count < 3 {
                        tops.append("\(o.identifier) \(Int(c * 100))%")
                    }
                    if id.contains("food") || id.contains("meal") || id.contains("dish")
                        || id.contains("pizza") || id.contains("burger") || id.contains("noodle")
                        || id.contains("sushi") || id.contains("dessert") || id.contains("fruit")
                        || id.contains("vegetable") || id.contains("menu") {
                        hints.foodScore = max(hints.foodScore, c)
                    }
                    if id.contains("carton") || id.contains("box") || id.contains("package")
                        || id.contains("envelope") || id.contains("parcel") || id.contains("crate") {
                        hints.packageScore = max(hints.packageScore, c)
                    }
                    if id.contains("document") || id.contains("book") || id.contains("paper")
                        || id.contains("letter") || id.contains("newspaper") || id.contains("magazine") {
                        hints.documentScore = max(hints.documentScore, c)
                    }
                    if id.contains("screen") || id.contains("monitor") || id.contains("laptop")
                        || id.contains("website") || id.contains("web site") || id.contains("television")
                        || id.contains("remote control") || id.contains("ipod") {
                        hints.screenUIScore = max(hints.screenUIScore, c)
                    }
                    if id.contains("person") || id.contains("people") || id.contains("face")
                        || id.contains("selfie") || id.contains("bride") || id.contains("groom") {
                        hints.personScore = max(hints.personScore, c)
                    }
                    if id.contains("landscape") || id.contains("mountain") || id.contains("beach")
                        || id.contains("ocean") || id.contains("forest") || id.contains("sky")
                        || id.contains("valley") || id.contains("lake") || id.contains("dog")
                        || id.contains("cat") || id.contains("pet") || id.contains("flower")
                        || id.contains("tree") || id.contains("sunset") {
                        hints.natureScore = max(hints.natureScore, c)
                    }
                }
                hints.topReasons = tops
                cont.resume(returning: hints)
            }
        }
    }


    // MARK: - Scoring

    private func score(ocrText: String, isScreenshot: Bool, hasQR: Bool, scene: SceneHints = .empty) -> ClassificationResult {
        let lower = ocrText.lowercased()
        if lower.isEmpty {
            return empty(isScreenshot: isScreenshot)
        }

        var scores: [JunkCategory: Double] = [:]
        var reasons: [JunkCategory: [String]] = [:]

        func add(_ cat: JunkCategory, _ pts: Double, _ reason: String) {
            scores[cat, default: 0] += pts
            var r = reasons[cat] ?? []
            if r.count < 6, !r.contains(reason) {
                r.append(reason)
                reasons[cat] = r
            }
        }

        // —— 外卖 ——
        let st = hits(lower, strongTakeout)
        if st > 0 {
            add(.takeout, min(0.98, 0.82 + Double(st - 1) * 0.05), "外卖强特征×\(st)")
        }
        let wt = hits(lower, weakTakeout)
        if wt >= 2 {
            add(.takeout, min(0.9, 0.48 + Double(wt) * 0.1), "外卖弱特征×\(wt)")
        } else if wt == 1 && st == 0 {
            if isScreenshot && (ocrText.contains("¥") || ocrText.contains("￥") || lower.contains("元")) {
                add(.takeout, 0.58, "外卖弱特征+金额")
            }
        }
        if (lower.contains("骑手") || lower.contains("配送")) &&
            (lower.contains("送达") || lower.contains("取餐") || ocrText.contains("¥") || ocrText.contains("￥")) {
            add(.takeout, 0.32, "配送场景")
        }

        // —— 快递 ——
        let sl = hits(lower, strongLogistics)
        if sl > 0 {
            add(.logistics, min(0.96, 0.8 + Double(sl - 1) * 0.05), "快递强特征×\(sl)")
        }
        let wl = hits(lower, weakLogistics)
        if wl >= 2 {
            add(.logistics, min(0.88, 0.42 + Double(wl) * 0.1), "快递弱特征×\(wl)")
        }

        // —— 支付 ——
        let sp = hits(lower, strongPayment)
        if sp > 0 {
            add(.payment, min(0.95, 0.8 + Double(sp - 1) * 0.05), "支付强特征×\(sp)")
        }
        let wp = hits(lower, weakPayment)
        if wp >= 2 {
            add(.payment, isScreenshot ? 0.58 : 0.48, "支付弱特征×\(wp)")
        }
        if (lower.contains("支付") || lower.contains("转账")) &&
            (ocrText.contains("¥") || ocrText.contains("￥") || lower.contains("成功")) {
            add(.payment, 0.28, "支付+金额/成功")
        }

        // —— 验证码 + 通知（同一展示类 verification）——
        let sv = hits(lower, strongVerify)
        if sv > 0 {
            add(.verification, min(0.95, 0.8 + Double(sv - 1) * 0.05), "验证码特征×\(sv)")
        }
        let sn = hits(lower, weakNotify)
        if sn >= 2 && isScreenshot {
            add(.verification, min(0.8, 0.45 + Double(sn) * 0.08), "通知特征×\(sn)")
        } else if sn >= 1 && sv >= 1 {
            add(.verification, 0.7, "验证码+通知")
        }
        // 短信样式：4–8 位数字 + 验证语境
        if sv > 0 || lower.contains("验证") {
            if lower.range(of: #"\b\d{4,8}\b"#, options: .regularExpression) != nil {
                add(.verification, 0.25, "含验证码数字")
            }
        }

        // —— 聊天 ——
        let sc = hits(lower, strongChat)
        if sc > 0 {
            // 强特征：截图优先，非截图也允许但略降
            add(.chatSnippet, min(0.9, (isScreenshot ? 0.72 : 0.55) + Double(sc - 1) * 0.08), "聊天强特征×\(sc)")
        }
        let wc = hits(lower, weakChat)
        if wc >= 2 && (isScreenshot || sc > 0) {
            add(.chatSnippet, min(0.78, 0.4 + Double(wc) * 0.08), "聊天弱特征×\(wc)")
        }
        // 微信 + 通话/消息 组合
        if (lower.contains("微信") || lower.contains("wechat")) &&
            (lower.contains("通话") || lower.contains("消息") || lower.contains("发送")) {
            add(.chatSnippet, isScreenshot ? 0.55 : 0.42, "微信会话特征")
        }

        // —— 其他疑似无用（落地实现）——
        let oj = hits(lower, otherJunk)
        if oj >= 2 {
            add(.otherJunk, min(0.82, 0.4 + Double(oj) * 0.08), "临时废图特征×\(oj)")
        } else if oj == 1 && isScreenshot && lower.count >= 20 {
            add(.otherJunk, 0.45, "截图含临时废图词")
        }
        // 电商订单但未命中外卖/快递
        if scores[.takeout] == nil && scores[.logistics] == nil {
            if lower.contains("订单") && (lower.contains("待") || lower.contains("详情") || lower.contains("编号")) {
                add(.otherJunk, isScreenshot ? 0.5 : 0.4, "订单类截图")
            }
        }


        // —— 视觉场景加权（系统 Vision + 可选 MobileNet）——
        // 注意：场景分要够高，否则进不了 ScanEngine 阈值
        if scene.foodScore > 0.2 {
            // 截图/有文字时更敢给外卖分；纯实拍食物仍可能是留念，给中等分
            let base = isScreenshot ? 0.52 : 0.38
            add(.takeout, min(0.72, base + scene.foodScore * 0.25), "图像含食物特征")
        }
        if scene.packageScore > 0.22 {
            let base = isScreenshot ? 0.5 : 0.36
            add(.logistics, min(0.7, base + scene.packageScore * 0.22), "图像含包装/纸箱特征")
        }
        if scene.documentScore > 0.25 || scene.screenUIScore > 0.25 {
            if scores[.takeout] != nil || scores[.logistics] != nil || scores[.payment] != nil {
                if let top = scores.max(by: { $0.value < $1.value })?.key {
                    add(top, 0.08, "图像偏文档/界面")
                }
            } else if isScreenshot {
                add(.otherJunk, min(0.58, 0.4 + max(scene.documentScore, scene.screenUIScore) * 0.25), "截图偏文档/界面")
            }
        }
        if scene.screenUIScore > 0.28 && isScreenshot && scores[.genericScreenshot] == nil && scores.isEmpty == false {
            // 已有其它类时略加
        }
        // 强自然照片抑制
        if scene.looksLikeNormalPhoto && !isScreenshot {
            for k in Array(scores.keys) {
                if k == .takeout || k == .logistics || k == .payment || k == .verification || k == .qrCode {
                    if (scores[k] ?? 0) < 0.55 { scores[k] = (scores[k] ?? 0) * 0.45 }
                } else {
                    scores[k] = (scores[k] ?? 0) * 0.2
                }
            }
        }

        // —— 普通截图兜底：系统截图默认应进结果，方便人工核对 ——
        if isScreenshot {
            if scores.isEmpty {
                add(.genericScreenshot, 0.55, "系统截图")
            } else {
                let top = scores.values.max() ?? 0
                if top < 0.45 {
                    add(.genericScreenshot, 0.5, "系统截图")
                }
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }) else {
            return ClassificationResult(category: nil, confidence: 0, reasons: [], hasQRCode: hasQR, ocrText: ocrText)
        }

        var conf = min(0.99, best.value)
        if (reasons[best.key]?.count ?? 0) >= 2 { conf = min(0.99, conf + 0.04) }

        // 非截图抑制误报
        if !isScreenshot {
            switch best.key {
            case .takeout, .logistics, .qrCode, .payment, .verification:
                if conf < 0.40 {
                    return ClassificationResult(category: nil, confidence: conf * 0.4, reasons: [], hasQRCode: hasQR, ocrText: ocrText)
                }
            case .chatSnippet:
                if conf < 0.55 {
                    return ClassificationResult(category: nil, confidence: conf * 0.35, reasons: [], hasQRCode: hasQR, ocrText: ocrText)
                }
            case .otherJunk:
                if conf < 0.55 {
                    return ClassificationResult(category: nil, confidence: conf * 0.3, reasons: [], hasQRCode: hasQR, ocrText: ocrText)
                }
            case .genericScreenshot:
                return ClassificationResult(category: nil, confidence: 0, reasons: [], hasQRCode: hasQR, ocrText: ocrText)
            }
        }

        return ClassificationResult(
            category: best.key,
            confidence: conf,
            reasons: reasons[best.key] ?? [],
            hasQRCode: hasQR,
            ocrText: ocrText
        )
    }

    private func hits(_ lower: String, _ keys: [String]) -> Int {
        var n = 0
        for k in keys where lower.contains(k) { n += 1 }
        return n
    }
}
