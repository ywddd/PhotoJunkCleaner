import Foundation
import UIKit

/// OpenAI 兼容视觉接口（GPT / Grok / 中转站等）
/// 请求：POST {baseURL}/chat/completions ，Bearer Key，可选 HTTP/HTTPS 代理
final class VisionAPIService {
    static let shared = VisionAPIService()
    private init() {}

    private let gate = CloudCallGate(maxConcurrent: 2)

    enum APIError: LocalizedError {
        case disabled
        case missingConfig
        case badURL
        case http(Int, String)
        case decode
        case cancelled

        var errorDescription: String? {
            switch self {
            case .disabled: return "云端视觉未开启"
            case .missingConfig: return "请填写 Base URL 与 API Key"
            case .badURL: return "Base URL 无效"
            case .http(let c, let b): return "HTTP \(c)：\(b.prefix(160))"
            case .decode: return "无法解析模型返回"
            case .cancelled: return "已取消"
            }
        }
    }

    /// 用视觉模型给图片分类；失败返回 nil（由调用方回退本地结果）
    func classify(
        image: UIImage,
        isScreenshot: Bool,
        ocrHint: String,
        settings: CloudVisionConfig
    ) async -> ClassificationResult? {
        guard settings.enabled else { return nil }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        do {
            return try await gate.withPermit {
                try await self.requestClassify(
                    image: image,
                    isScreenshot: isScreenshot,
                    ocrHint: ocrHint,
                    settings: settings
                )
            }
        } catch {
            print("VisionAPI error: \(error.localizedDescription)")
            return nil
        }
    }

    /// 设置页「测试连接」
    func testConnection(settings: CloudVisionConfig) async -> String {
        guard settings.enabled || true else { return "未开启" }
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !base.isEmpty else { return "请填写 Base URL 与 API Key" }

        // 用 1x1 像素 + 极简 prompt 做连通性测试（部分站也可用 models 列表）
        let img = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        do {
            let r = try await requestClassify(
                image: img,
                isScreenshot: true,
                ocrHint: "",
                settings: settings
            )
            return "连接成功 · 返回 \(r.category?.displayName ?? "none") (\(Int(r.confidence * 100))%)"
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Request

    private func requestClassify(
        image: UIImage,
        isScreenshot: Bool,
        ocrHint: String,
        settings: CloudVisionConfig
    ) async throws -> ClassificationResult {
        if Task.isCancelled { throw APIError.cancelled }

        let endpoint = chatCompletionsURL(base: settings.baseURL)
        guard let url = URL(string: endpoint) else { throw APIError.badURL }

        let jpeg = compress(image, maxSide: 768, quality: 0.55)
        let b64 = jpeg.base64EncodedString()

        let system = """
        你是手机相册废图分类助手。只根据图片判断是否属于可清理的临时截图/废图。
        必须只输出一行 JSON，不要 Markdown，不要其它文字：
        {"category":"takeout|logistics|qrCode|payment|verification|chatSnippet|genericScreenshot|otherJunk|none","confidence":0.0,"reason":"简短中文"}
        类别含义：
        takeout=外卖订单/配送; logistics=快递物流取件; qrCode=二维码/条码页; payment=支付账单转账;
        verification=验证码或系统通知; chatSnippet=聊天会话截图; genericScreenshot=其它系统截图;
        otherJunk=电商订单/广告落地/临时活动页等; none=正常照片应保留。
        confidence 为 0~1。
        """

        var userText = "请分类这张图。"
        if isScreenshot { userText += "系统标记：截图。" }
        let hint = ocrHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty {
            let clipped = String(hint.prefix(280))
            userText += " 本地OCR片段：\(clipped)"
        }

        let body: [String: Any] = [
            "model": settings.model,
            "temperature": 0,
            "max_tokens": 120,
            "messages": [
                ["role": "system", "content": system],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": userText],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(b64)",
                                "detail": "low"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        req.httpBody = data

        let session = makeSession(proxy: settings.proxyURL)
        let (respData, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code < 200 || code >= 300 {
            let text = String(data: respData, encoding: .utf8) ?? ""
            throw APIError.http(code, text)
        }

        return try parseResponse(respData)
    }

    private func chatCompletionsURL(base: String) -> String {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        if b.hasSuffix("/chat/completions") { return b }
        if b.hasSuffix("/v1") { return b + "/chat/completions" }
        // 允许用户填到根域名或带 /v1
        if b.contains("/v1/") { return b.hasSuffix("completions") ? b : b + (b.hasSuffix("/") ? "chat/completions" : "/chat/completions") }
        return b + "/chat/completions"
    }

    private func makeSession(proxy: String) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 35
        cfg.waitsForConnectivity = true

        let p = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty, let proxyURL = URL(string: p), let host = proxyURL.host {
            let port = proxyURL.port ?? (proxyURL.scheme?.lowercased() == "https" ? 443 : 80)
            // 使用字符串键，兼容 iOS URLSession 代理配置
            cfg.connectionProxyDictionary = [
                "HTTPEnable": 1,
                "HTTPProxy": host,
                "HTTPPort": port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        }
        return URLSession(configuration: cfg)
    }

    private func compress(_ image: UIImage, maxSide: CGFloat, quality: CGFloat) -> Data {
        let w = image.size.width
        let h = image.size.height
        let scale = min(1, maxSide / max(w, h, 1))
        let size = CGSize(width: max(1, w * scale), height: max(1, h * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality) ?? Data()
    }

    private func parseResponse(_ data: Data) throws -> ClassificationResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decode
        }
        // OpenAI style
        let content: String = {
            if let choices = root["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any] {
                if let s = msg["content"] as? String { return s }
                // 少数实现 content 为数组
                if let arr = msg["content"] as? [[String: Any]] {
                    return arr.compactMap { $0["text"] as? String }.joined()
                }
            }
            if let s = root["content"] as? String { return s }
            return ""
        }()

        let jsonText = extractJSONObject(content)
        guard let jdata = jsonText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jdata) as? [String: Any] else {
            throw APIError.decode
        }

        let catRaw = (obj["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "none"
        let conf = min(0.99, max(0, (obj["confidence"] as? Double)
                                 ?? (obj["confidence"] as? Int).map(Double.init)
                                 ?? 0.6))
        let reason = (obj["reason"] as? String) ?? "云端视觉"

        let category: JunkCategory? = {
            switch catRaw {
            case "takeout", "外卖", "waimai": return .takeout
            case "logistics", "快递", "物流": return .logistics
            case "qrcode", "qr_code", "qr", "二维码": return .qrCode
            case "payment", "支付", "账单": return .payment
            case "verification", "verify", "验证码", "通知": return .verification
            case "chatsnippet", "chat", "聊天": return .chatSnippet
            case "genericscreenshot", "generic_screenshot", "screenshot", "普通截图": return .genericScreenshot
            case "otherjunk", "other_junk", "other", "其他": return .otherJunk
            case "none", "keep", "normal", "null", "": return nil
            default: return nil
            }
        }()

        return ClassificationResult(
            category: category,
            confidence: conf,
            reasons: ["云端: \(reason)"],
            hasQRCode: category == .qrCode,
            ocrText: ""
        )
    }

    private func extractJSONObject(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
            s = s.replacingOccurrences(of: "```", with: "")
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            return String(s[start...end])
        }
        return s
    }
}

// MARK: - Config snapshot (thread-safe copy)

struct CloudVisionConfig: Sendable {
    var enabled: Bool
    var baseURL: String
    var apiKey: String
    var proxyURL: String
    var model: String
    /// 仅在本地不确定时调用
    var onlyUncertain: Bool
    /// 单次扫描最多云端调用次数（省费用）
    var maxCallsPerScan: Int
    var uncertainThreshold: Double
}

// MARK: - Concurrency gate

actor CloudCallGate {
    private let maxConcurrent: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func withPermit<T>(_ body: () async throws -> T) async throws -> T {
        await acquire()
        defer { Task { await self.release() } }
        return try await body()
    }

    private func acquire() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
        inFlight += 1
    }

    private func release() {
        inFlight = max(0, inFlight - 1)
        if !waiters.isEmpty {
            let w = waiters.removeFirst()
            w.resume()
        }
    }
}
