import Foundation

struct DebugFlags: Equatable {
    var forceOnboarding: Bool
    var concurrencyCapOverride: Int?
    var resetState: Bool

    init(
        forceOnboarding: Bool = false,
        concurrencyCapOverride: Int? = nil,
        resetState: Bool = false
    ) {
        self.forceOnboarding = forceOnboarding
        self.concurrencyCapOverride = concurrencyCapOverride
        self.resetState = resetState
    }

    static func parse(_ argv: [String]) -> DebugFlags {
        var flags = DebugFlags()
        var index = argv.startIndex
        while index < argv.endIndex {
            let arg = argv[index]
            switch arg {
            case "-MGForceOnboarding":
                flags.forceOnboarding = true
            case "-MGResetState":
                flags.resetState = true
            case "-MGConcurrencyCap":
                index = argv.index(after: index)
                if index < argv.endIndex, let value = Int(argv[index]) {
                    flags.concurrencyCapOverride = value
                }
            default:
                break
            }
            index = argv.index(after: index)
        }
        return flags
    }
}
