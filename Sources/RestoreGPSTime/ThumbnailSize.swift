import Foundation

enum ThumbnailSize: String, CaseIterable {
    case off, small, medium, large
    var title:String {rawValue.capitalized}
    var points:CGFloat {
        switch self {case .off:return 0;case .small:return 48;case .medium:return 96;case .large:return 160}
    }
    var rowHeight:CGFloat {self == .off ? 24:points+12}
}
