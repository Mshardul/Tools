import Foundation

public extension DownloadEngine {
    func preview(_ url: String) async -> Result<MediaMetadata, MetadataError> {
        shieldStatus = await dependencies.potProvider.status
        if queueHalt == .networkDown {
            return .failure(.network)
        }
        let host = RateHost(urlString: url)
        if rateLimiter.blocked(host: host, now: dependencies.clock.now) {
            return .failure(.hostBlocked)
        }
        let context = await makeContext(url: url, attempt: 0, forceCookies: false)
        return await dependencies.probe.probe(url, context: context)
    }

    func previewPlaylist(_ url: String) async -> Result<PlaylistDump, MetadataError> {
        shieldStatus = await dependencies.potProvider.status
        if queueHalt == .networkDown {
            return .failure(.network)
        }
        let host = RateHost(urlString: url)
        if rateLimiter.blocked(host: host, now: dependencies.clock.now) {
            return .failure(.hostBlocked)
        }
        let context = await makeContext(url: url, attempt: 0, forceCookies: false)
        return await dependencies.probe.probePlaylist(url, context: context)
    }

    func ensureShield() async {
        await dependencies.potProvider.ensure()
        shieldStatus = await dependencies.potProvider.status
        emitSnapshot()
    }

    func restartShield() async {
        await dependencies.potProvider.restart()
        shieldStatus = await dependencies.potProvider.status
        emitSnapshot()
    }
}

extension DownloadEngine {
    func makeContext(url: String, attempt: Int, forceCookies: Bool) async -> ExtractorContext {
        let status = await dependencies.potProvider.status
        let dirs = await dependencies.potProvider.pluginDirs
        let base = await dependencies.potProvider.baseURL
        let isYouTube = RateHost(urlString: url).canonical == "youtube"
        let shieldUp = if case .running = status {
            true
        } else {
            false
        }
        let home = dependencies.cookieResolverHome
            ?? FileManager.default.homeDirectoryForCurrentUser
        let cookie = CookieResolver(fileManager: dependencies.fileManager, home: home)
            .resolve(source: preferences.cookiesFromBrowser, jobOverride: forceCookies)
            .argument
        return ExtractorContext(
            pluginDirs: dirs,
            potBaseURL: (isYouTube && shieldUp) ? base : nil,
            playerClient: isYouTube ? PlayerClientRotation.client(forAttempt: attempt) : nil,
            cookieArgument: cookie
        )
    }
}
