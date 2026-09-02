import Foundation

public struct CookieResolver: Sendable {
    private let fileManager: FileManaging
    private let home: URL

    public init(
        fileManager: FileManaging = FoundationFileManager(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.home = home
    }

    private var firefoxRoot: URL {
        home.appendingPathComponent("Library/Application Support/Firefox")
    }

    private var safariCookiesURL: URL {
        home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        )
    }

    // MARK: - Firefox

    public func firefoxProfiles() -> [FirefoxProfile] {
        let iniURL = firefoxRoot.appendingPathComponent("profiles.ini")
        guard fileManager.fileExists(atPath: iniURL.path),
              fileManager.dataReadable(at: iniURL),
              let text = fileManager.fileContents(at: iniURL)
        else {
            return []
        }
        return parseProfiles(fromINI: text)
    }

    private func parseProfiles(fromINI text: String) -> [FirefoxProfile] {
        let sections = iniSections(text)
        let defaultPaths = Set(
            sections
                .filter { $0.header.hasPrefix("Install") }
                .compactMap { $0.values["Default"] }
        )
        return sections.compactMap { section in
            profile(from: section, defaultPaths: defaultPaths)
        }
    }

    private func profile(from section: INISection, defaultPaths: Set<String>) -> FirefoxProfile? {
        guard section.header.hasPrefix("Profile"),
              let name = section.values["Name"], !name.isEmpty,
              let rawPath = section.values["Path"], !rawPath.isEmpty
        else {
            return nil
        }
        let isRelative = (section.values["IsRelative"] ?? "1") != "0"
        let absolute = isRelative
            ? firefoxRoot.appendingPathComponent(rawPath).path
            : rawPath
        let markedDefault = section.values["Default"] == "1" || defaultPaths.contains(rawPath)
        return FirefoxProfile(name: name, path: absolute, isDefault: markedDefault)
    }

    private struct INISection {
        var header: String
        var values: [String: String]
    }

    private func iniSections(_ text: String) -> [INISection] {
        var sections: [INISection] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append(INISection(
                    header: String(line.dropFirst().dropLast()),
                    values: [:]
                ))
                continue
            }
            guard !sections.isEmpty, let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            sections[sections.count - 1].values[key] = value
        }
        return sections
    }

    // MARK: - Safari

    public func safariAccess() -> SafariCookieAccess {
        guard fileManager.fileExists(atPath: safariCookiesURL.path) else { return .noContainer }
        return fileManager.dataReadable(at: safariCookiesURL) ? .granted : .denied
    }

    // MARK: - Resolve

    public func resolve(source: CookieSource, jobOverride: Bool) -> CookieResolution {
        switch source {
        case .none:
            noneResolution(jobOverride: jobOverride)
        case .safari:
            safariResolution()
        case let .firefox(profile):
            firefoxResolution(requestedName: profile)
        case .chrome, .brave, .edge:
            CookieResolution(
                argument: source.ytDlpSpec,
                verdict: .ready(browserKey: source.browserKey)
            )
        }
    }

    private func noneResolution(jobOverride: Bool) -> CookieResolution {
        guard jobOverride else {
            return CookieResolution(argument: nil, verdict: .unconfigured)
        }
        return substitutedResolution()
    }

    private func safariResolution() -> CookieResolution {
        safariAccess() == .granted
            ? CookieResolution(argument: "safari", verdict: .ready(browserKey: "safari"))
            : CookieResolution(argument: nil, verdict: .needsFullDiskAccess)
    }

    private func firefoxResolution(requestedName: String?) -> CookieResolution {
        let profiles = firefoxProfiles()
        if let requestedName, profiles.contains(where: { $0.name == requestedName }) {
            return CookieResolution(
                argument: "firefox:\(requestedName)", verdict: .ready(browserKey: "firefox")
            )
        }
        if profiles.isEmpty {
            return CookieResolution(argument: nil, verdict: .noProfiles)
        }
        if let defaultName = profiles.first(where: \.isDefault)?.name {
            return CookieResolution(
                argument: "firefox:\(defaultName)", verdict: .ready(browserKey: "firefox")
            )
        }
        return CookieResolution(argument: "firefox", verdict: .ready(browserKey: "firefox"))
    }

    private func substitutedResolution() -> CookieResolution {
        if safariAccess() == .granted {
            return CookieResolution(argument: "safari", verdict: .ready(browserKey: "safari"))
        }
        let candidates: [CookieSource] = [.chrome, .brave, .edge, .firefox(profile: nil)]
        if let source = candidates.first(where: { browserSupportDirectoryExists(for: $0) }) {
            return CookieResolution(
                argument: source.ytDlpSpec, verdict: .ready(browserKey: source.browserKey)
            )
        }
        return CookieResolution(argument: nil, verdict: .unconfigured)
    }

    private func browserSupportDirectoryExists(for source: CookieSource) -> Bool {
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let relativePath: String
        switch source {
        case .chrome: relativePath = "Google/Chrome"
        case .brave: relativePath = "BraveSoftware/Brave-Browser"
        case .edge: relativePath = "Microsoft Edge"
        case .firefox: relativePath = "Firefox"
        case .none, .safari: return false
        }
        let dir = appSupport.appendingPathComponent(relativePath)
        return fileManager.fileExists(atPath: dir.path)
            || !fileManager.contentsOfDirectory(at: dir).isEmpty
    }
}
