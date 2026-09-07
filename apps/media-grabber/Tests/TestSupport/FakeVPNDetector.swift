import Foundation
import GrabberKit

public struct FakeVPNDetector: VPNDetecting {
    public var isVPNActive: Bool

    public init(isVPNActive: Bool = false) {
        self.isVPNActive = isVPNActive
    }
}
