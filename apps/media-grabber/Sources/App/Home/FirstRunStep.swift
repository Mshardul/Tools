import Foundation

enum FirstRunPresentation: Equatable {
    case numberedStrip
}

struct FirstRunStep: Equatable {
    let index: Int
    let title: String
    let subtitle: String

    static let presentation = FirstRunPresentation.numberedStrip
    static let strip: [FirstRunStep] = [
        FirstRunStep(index: 1, title: "Paste a link", subtitle: "Any video page URL."),
        FirstRunStep(index: 2, title: "Pick a format", subtitle: "Video quality or audio only."),
        FirstRunStep(index: 3, title: "Press Grab", subtitle: "It saves to your folder.")
    ]
}
