import Foundation

public enum SaveFailureNotice {
    public static func sentence(file: String, error: Error) -> String {
        let subject = subject(for: file)
        switch cause(of: error as NSError) {
        case .diskFull:
            return "\(subject) couldn't be saved because the disk is full. Free some space, then try again."
        case .notPermitted:
            return "\(subject) couldn't be saved because the save folder isn't writable. "
                + "Make the folder writable, then try again."
        case .unavailable:
            return "\(subject) couldn't be saved. Check that the save folder is available, then try again."
        }
    }

    private static func subject(for file: String) -> String {
        switch file {
        case "queue.json": "The download list"
        case "history.json": "Download history"
        case "columns.json": "The column layout"
        default: "App data"
        }
    }

    private enum Cause {
        case diskFull
        case notPermitted
        case unavailable
    }

    private static func cause(of error: NSError) -> Cause {
        if let direct = directCause(error) {
            return direct
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return cause(of: underlying)
        }
        return .unavailable
    }

    private static func directCause(_ error: NSError) -> Cause? {
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), (NSPOSIXErrorDomain, Int(ENOSPC)):
            .diskFull
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)),
             (NSPOSIXErrorDomain, Int(EPERM)):
            .notPermitted
        default:
            nil
        }
    }
}
