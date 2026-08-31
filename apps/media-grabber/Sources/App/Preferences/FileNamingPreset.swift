import Foundation

enum FileNamingPreset: CaseIterable, Hashable {
    case title
    case titleAndChannel
    case dateAndTitle
    case custom

    var rowLabel: String {
        switch self {
        case .title: "Title"
        case .titleAndChannel: "Title \u{2013} channel"
        case .dateAndTitle: "Date \u{2013} title"
        case .custom: "Custom\u{2026}"
        }
    }

    var template: String? {
        switch self {
        case .title: "%(title)s.%(ext)s"
        case .titleAndChannel: "%(title)s - %(uploader)s.%(ext)s"
        case .dateAndTitle: "%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s"
        case .custom: nil
        }
    }

    var exampleSubtitle: String? {
        switch self {
        case .title: "Never Gonna Give You Up.mp4"
        case .titleAndChannel: "Never Gonna Give You Up - Rick Astley.mp4"
        case .dateAndTitle: "2009-10-25 - Never Gonna Give You Up.mp4"
        case .custom: nil
        }
    }

    static func matching(_ stored: String) -> FileNamingPreset {
        allCases.first { $0.template == stored } ?? .custom
    }
}
