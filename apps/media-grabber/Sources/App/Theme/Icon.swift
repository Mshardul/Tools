import GrabberKit
import SwiftUI

enum IconKind: String {
    case pause, resume, cancel, forceStart, retry, retryWithCookies
    case reveal, openInBrowser, remove, showLog
    case sortNeutral, sortAsc, sortDesc, filter, columnsMenu
    case warning
}

struct Icon: View {
    let kind: IconKind
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size, weight: .medium))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch kind {
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .cancel: "xmark"
        case .forceStart: "arrow.up.to.line"
        case .retry: "arrow.clockwise"
        case .retryWithCookies: "key.fill"
        case .reveal: "folder"
        case .openInBrowser: "globe"
        case .remove: "trash"
        case .showLog: "doc.text"
        case .sortNeutral: "arrow.up.arrow.down"
        case .sortAsc: "chevron.up"
        case .sortDesc: "chevron.down"
        case .filter: "line.3.horizontal.decrease.circle"
        case .columnsMenu: "tablecells"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}

extension RowAction {
    var iconKind: IconKind {
        switch self {
        case .pause: .pause
        case .resume: .resume
        case .cancel: .cancel
        case .forceStart: .forceStart
        case .retry: .retry
        case .retryWithCookies: .retryWithCookies
        case .reveal: .reveal
        case .openInBrowser: .openInBrowser
        case .remove: .remove
        case .showLog: .showLog
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .pause: "Pause"
        case .resume: "Resume"
        case .cancel: "Cancel"
        case .forceStart: "Force start"
        case .retry: "Retry"
        case .retryWithCookies: "Retry with cookies"
        case .reveal: "Reveal in Finder"
        case .openInBrowser: "Open in browser"
        case .remove: "Remove"
        case .showLog: "Show log"
        }
    }
}
