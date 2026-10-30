import SwiftUI
import UIKit

enum PaperColor: String, Codable, CaseIterable, Identifiable {
    case white, cream, gray, blue, dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .white: "白色"
        case .cream: "米白"
        case .gray: "浅灰"
        case .blue: "浅蓝"
        case .dark: "深色"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .white: .white
        case .cream: UIColor(red: 0.98, green: 0.96, blue: 0.89, alpha: 1)
        case .gray: UIColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1)
        case .blue: UIColor(red: 0.90, green: 0.95, blue: 0.98, alpha: 1)
        case .dark: UIColor(red: 0.14, green: 0.16, blue: 0.19, alpha: 1)
        }
    }

    var foreground: Color { self == .dark ? .white : .black }
}

enum InkColor: String, Codable, CaseIterable, Identifiable {
    case black, blue, red, green, white

    var id: String { rawValue }

    var name: String {
        switch self {
        case .black: "黑色"
        case .blue: "蓝色"
        case .red: "红色"
        case .green: "绿色"
        case .white: "白色"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .black: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        case .blue: UIColor(red: 0.10, green: 0.26, blue: 0.65, alpha: 1)
        case .red: UIColor(red: 0.76, green: 0.17, blue: 0.18, alpha: 1)
        case .green: UIColor(red: 0.10, green: 0.43, blue: 0.31, alpha: 1)
        case .white: .white
        }
    }
}

enum PenWidth: String, Codable, CaseIterable, Identifiable {
    case fine, medium, broad

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fine: "细"
        case .medium: "中"
        case .broad: "粗"
        }
    }

    var points: CGFloat {
        switch self {
        case .fine: 1.5
        case .medium: 2.5
        case .broad: 4
        }
    }
}

struct Notebook: Codable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var pages: [UUID]
    var currentPageID: UUID
    var paperColor: PaperColor
    var inkColor: InkColor
    var penWidth: PenWidth
    var pageWidth: Double
    var pageHeight: Double

    var pageSize: CGSize {
        CGSize(width: pageWidth > 0 ? pageWidth : 768,
               height: pageHeight > 0 ? pageHeight : 1024)
    }

    static func create(title: String) -> Notebook {
        let firstPage = UUID()
        return Notebook(
            id: UUID(), title: title, createdAt: .now, updatedAt: .now,
            pages: [firstPage], currentPageID: firstPage,
            paperColor: .cream, inkColor: .black, penWidth: .medium,
            pageWidth: 0, pageHeight: 0
        )
    }
}
