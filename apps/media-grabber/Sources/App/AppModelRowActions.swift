import Foundation
import GrabberKit

#if canImport(AppKit)
    import AppKit
#endif

extension AppModel {
    func handleRowAction(_ id: UUID, action: RowAction) async {
        switch action {
        case .pause: await engine.pause(id)
        case .resume: await engine.resume(id)
        case .cancel: await engine.cancel(id)
        case .remove: await engine.remove(id)
        case .forceStart: await engine.forceStart(id)
        case .reveal: await reveal(jobID: id)
        case .openInBrowser: openInBrowser(jobID: id)
        case .retry: await engine.retry(id)
        case .showLog: await showLog(jobID: id)
        case .retryWithCookies: await retryWithCookies(id)
        }
    }

    private func retryWithCookies(_ id: UUID) async {
        if prefs.cookiesFromBrowser.isNone {
            setPendingCookieRetry(id)
            page = .preferences(.cookies)
        } else {
            await engine.retryWithCookies(id)
        }
    }

    func showLog(jobID: UUID) async {
        let url = engineJobLogDir.appendingPathComponent("\(jobID.uuidString).log")
        if FileManager.default.fileExists(atPath: url.path) {
            openURLSink.open(url)
        } else {
            await log.log(.showLogTargetMissing(jobID: jobID))
            _ = await confirm(AppModelDialogs.showLogMissingNotice())
        }
    }

    func reveal(jobID: UUID) async {
        guard let row = rowStore.rows.first(where: { $0.id == jobID }) else { return }
        let existing = row.snapshot.outputFiles.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if existing.isEmpty {
            await log.log(.revealTargetMissing(jobID: jobID))
            _ = await confirm(AppModelDialogs.revealMissingConfirmation())
        } else {
            revealSink.reveal(existing)
        }
    }

    private func openInBrowser(jobID: UUID) {
        guard let row = rowStore.rows.first(where: { $0.id == jobID }),
              let url = URL(string: row.snapshot.url)
        else { return }
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }
}
