import Foundation
import UIKit
import CoreML
import Vision

/// 内置轻量 Core ML（MobileNetV2）场景辅助
/// 模型约 24MB，本地运行；加载失败时自动回退系统 VNClassify
final class LocalMLService {
    static let shared = LocalMLService()

    private(set) var isReady: Bool = false
    private var vnModel: VNCoreMLModel?
    private let lock = NSLock()

    private init() {
        loadModel()
    }

    private func loadModel() {
        // 优先编译后的 .mlmodelc；开发期也可放 .mlmodel
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodel")
        ]
        for case let url? in candidates {
            do {
                let cfg = MLModelConfiguration()
                cfg.computeUnits = .all // CPU/GPU/ANE 自动
                let model = try MLModel(contentsOf: url, configuration: cfg)
                vnModel = try VNCoreMLModel(for: model)
                isReady = true
                print("LocalML: loaded \(url.lastPathComponent)")
                return
            } catch {
                print("LocalML: fail \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // 兼容：从 main bundle 扫描
        if let urls = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) {
            for url in urls where url.lastPathComponent.lowercased().contains("mobilenet") {
                do {
                    let model = try MLModel(contentsOf: url)
                    vnModel = try VNCoreMLModel(for: model)
                    isReady = true
                    print("LocalML: loaded scan \(url.lastPathComponent)")
                    return
                } catch {
                    print("LocalML scan fail: \(error)")
                }
            }
        }
        isReady = false
        print("LocalML: MobileNetV2 not in bundle, will use system Vision only")
    }

    /// ImageNet 标签 → 场景分（与 SceneHints 对齐）
    func classifyScene(cgImage: CGImage) async -> ImageClassifierService.SceneHints {
        let model: VNCoreMLModel? = {
            lock.lock(); defer { lock.unlock() }
            return vnModel
        }()
        guard let model else { return .empty }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNCoreMLRequest(model: model)
                request.imageCropAndScaleOption = .centerCrop
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(returning: .empty)
                    return
                }

                // MobileNet 结果：VNClassificationObservation 或 feature value
                var observations: [VNClassificationObservation] = []
                if let r = request.results as? [VNClassificationObservation] {
                    observations = r
                }

                var hints = ImageClassifierService.SceneHints()
                var tops: [String] = []
                for o in observations.prefix(15) {
                    let id = o.identifier.lowercased()
                    let c = Double(o.confidence)
                    if c < 0.05 { continue }
                    if tops.count < 4 {
                        tops.append("\(o.identifier) \(Int(c * 100))%")
                    }
                    Self.accumulate(id: id, confidence: c, into: &hints)
                }
                hints.topReasons = tops.isEmpty ? ["MobileNet"] : tops
                cont.resume(returning: hints)
            }
        }
    }

    private static func accumulate(id: String, confidence c: Double, into hints: inout ImageClassifierService.SceneHints) {
        // 食物
        if id.contains("food") || id.contains("dish") || id.contains("menu")
            || id.contains("pizza") || id.contains("burger") || id.contains("hotdog")
            || id.contains("hot dog") || id.contains("bagel") || id.contains("pretzel")
            || id.contains("carbonara") || id.contains("guacamole") || id.contains("consomme")
            || id.contains("hot pot") || id.contains("potpie") || id.contains("burrito")
            || id.contains("ramen") || id.contains("sushi") || id.contains("ice cream")
            || id.contains("trifle") || id.contains("cheeseburger") || id.contains("french loaf")
            || id.contains("plate") || id.contains("restaurant") {
            hints.foodScore = max(hints.foodScore, c)
        }
        // 包装 / 箱
        if id.contains("carton") || id.contains("crate") || id.contains("chest")
            || id.contains("mailbag") || id.contains("envelope") || id.contains("packet")
            || id.contains("box") || id.contains("package") || id.contains("parcel")
            || id.contains("band aid") || id.contains("plastic bag") {
            hints.packageScore = max(hints.packageScore, c)
        }
        // 文档 / 书
        if id.contains("book") || id.contains("envelope") || id.contains("menu")
            || id.contains("notebook") || id.contains("binder") || id.contains("paper")
            || id.contains("comic") || id.contains("crossword") || id.contains("web site")
            || id.contains("website") || id.contains("book jacket") {
            hints.documentScore = max(hints.documentScore, c)
        }
        // 屏幕 / 设备 UI
        if id.contains("screen") || id.contains("monitor") || id.contains("laptop")
            || id.contains("notebook") || id.contains("iPod") || id.contains("cellular")
            || id.contains("remote control") || id.contains("television")
            || id.contains("desktop computer") || id.contains("hand-held computer")
            || id.contains("web site") || id.contains("website") {
            hints.screenUIScore = max(hints.screenUIScore, c)
        }
        // 人物
        if id.contains("person") || id.contains("groom") || id.contains("bride")
            || id.contains("scuba diver") || id.contains("ballplayer") {
            hints.personScore = max(hints.personScore, c)
        }
        // 自然 / 动物
        if id.contains("valley") || id.contains("lakeside") || id.contains("seashore")
            || id.contains("alp") || id.contains("volcano") || id.contains("coral")
            || id.contains("dog") || id.contains("cat") || id.contains("corgi")
            || id.contains("retriever") || id.contains("terrier") || id.contains("tabby")
            || id.contains("flower") || id.contains("daisy") || id.contains("tree")
            || id.contains("mountain") || id.contains("beach") {
            hints.natureScore = max(hints.natureScore, c)
        }
    }
}
