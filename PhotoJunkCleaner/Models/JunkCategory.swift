import Foundation
import SwiftUI

/// 无用图片分类
enum JunkCategory: String, CaseIterable, Identifiable, Codable {
    case takeout
    case logistics      // 快递 / 物流
    case qrCode
    case payment
    case verification
    case chatSnippet
    case genericScreenshot
    case otherJunk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .takeout: return "外卖截图"
        case .logistics: return "快递物流"
        case .qrCode: return "二维码截图"
        case .payment: return "支付/账单"
        case .verification: return "验证码/通知"
        case .chatSnippet: return "聊天截图"
        case .genericScreenshot: return "普通截图"
        case .otherJunk: return "其他疑似无用"
        }
    }

    var systemImage: String {
        switch self {
        case .takeout: return "takeoutbag.and.cup.and.straw"
        case .logistics: return "shippingbox"
        case .qrCode: return "qrcode"
        case .payment: return "creditcard"
        case .verification: return "number"
        case .chatSnippet: return "bubble.left.and.bubble.right"
        case .genericScreenshot: return "camera.viewfinder"
        case .otherJunk: return "trash"
        }
    }

    var tint: Color {
        switch self {
        case .takeout: return .orange
        case .logistics: return .brown
        case .qrCode: return .purple
        case .payment: return .green
        case .verification: return .blue
        case .chatSnippet: return .cyan
        case .genericScreenshot: return .gray
        case .otherJunk: return .secondary
        }
    }

    /// 默认是否勾选参与清理（普通截图默认不勾）
    var defaultSelected: Bool {
        switch self {
        case .genericScreenshot: return false
        default: return true
        }
    }
}
