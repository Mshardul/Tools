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
        let context = await makeContext(url: url, attempt: 0)
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
        let context = await makeContext(url: url, attempt: 0)
        return await dependencies.probe.probePlaylist(url, context: context)
    }

    func ensureShield() async {
        await dependencies.potProvider.ensure()
        shieldStatus = await dependencies.potProvider.status
        emitSnapshot()
    }

    func restartShield() async -> Bool {
        await dependencies.potProvider.restart()
        shieldStatus = await dependencies.potProvider.status
        emitSnapshot()
        if case .running = shieldStatus {
            return true
        }
        return false
    }
}

extension DownloadEngine {
    func makeContext(
        url: String,
        attempt _: Int,
        burnedClients: Set<String> = [],
        passcode: String? = nil
    ) async -> ExtractorContext {
        let status = await dependencies.potProvider.status
        let dirs = await dependencies.potProvider.pluginDirs
        let base = await dependencies.potProvider.baseURL
        let host = RateHost(urlString: url).canonical
        let isYouTube = host == "youtube"
        let shieldUp = if case .running = status {
            true
        } else {
            false
        }
        let client: String?
        if isYouTube {
            let order = await dependencies.playerClientOrder.order()
            client = PlayerClientRotation.client(order: order, burned: burnedClients)
        } else {
            client = nil
        }
        let home = dependencies.cookieResolverHome
            ?? FileManager.default.homeDirectoryForCurrentUser
        let sendsCookies = SignInScopePolicy.sendsCookies(
            scope: preferences.signInScope,
            sites: preferences.signInSites,
            host: host
        )
        let cookie: String? = if preferences.cookiesFromBrowser.isNone || !sendsCookies {
            nil
        } else {
            CookieResolver(fileManager: dependencies.fileManager, home: home)
                .resolve(source: preferences.cookiesFromBrowser)
                .argument
        }
        return ExtractorContext(
            pluginDirs: dirs + BundledYtDlpPlugins.directories,
            potBaseURL: (isYouTube && shieldUp) ? base : nil,
            playerClient: client,
            cookieArgument: cookie,
            videoPassword: passcode ?? passcodes[url]
        )
    }
}
