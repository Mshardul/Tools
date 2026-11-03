import Foundation

public enum SignInCopy {
    public static func sentence(for errorClass: ErrorClass, advice: SignInAdvice) -> String? {
        switch (errorClass, advice) {
        case (_, .none):
            nil
        case (.ageRestricted, .suggest):
            "This video is age-restricted. Signing in with your browser may let you download it."
        case (.ageRestricted, .checkBrowser):
            "This video is age-restricted. Make sure your browser is signed in to an account that can watch it."
        case (.private, .suggest):
            "This video is private. If you have access, signing in with your browser may let you download it."
        case (.private, .checkBrowser):
            "This video is private. Make sure your browser is signed in to an account that has access."
        default:
            nil
        }
    }
}
