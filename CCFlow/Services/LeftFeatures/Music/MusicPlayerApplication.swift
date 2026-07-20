import Foundation

/// CC FLOW 可以从系统 Now Playing 识别并重新唤起的音乐播放器。
enum MusicPlayerApplication: String, CaseIterable, Equatable {
    case appleMusic
    case spotify
    case neteaseMusic
    case qqMusic

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .neteaseMusic: "网易云音乐"
        case .qqMusic: "QQ 音乐"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .appleMusic:
            ["com.apple.Music", "com.apple.iTunes"]
        case .spotify:
            ["com.spotify.client"]
        case .neteaseMusic:
            ["com.netease.163music", "com.netease.163music.mac", "163Music", "com.netease.cloudmusic"]
        case .qqMusic:
            ["com.tencent.QQMusic", "com.tencent.QQMusicMac", "QQMusicMac", "com.tencent.qqmusicmac"]
        }
    }

    static func from(source: String) -> MusicPlayerApplication? {
        let normalized = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        if normalized.contains("spotify") {
            return .spotify
        }
        if normalized.contains("网易云")
            || normalized.contains("netease")
            || normalized.contains("163music") {
            return .neteaseMusic
        }
        if normalized.contains("qq音乐")
            || normalized.contains("qq 音乐")
            || normalized.contains("qq music")
            || normalized.contains("qqmusic") {
            return .qqMusic
        }
        if normalized == "music"
            || normalized == "apple music"
            || normalized == "itunes"
            || normalized.contains("com.apple.music")
            || normalized.contains("com.apple.itunes") {
            return .appleMusic
        }
        return nil
    }
}

/// 持久化最近一次识别到的播放器，并负责决定空状态的唤起目标。
struct MusicPlayerApplicationStore {
    private static let rememberedApplicationKey = "music.lastUsedPlayerApplication"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var rememberedApplication: MusicPlayerApplication? {
        guard let rawValue = defaults.string(forKey: Self.rememberedApplicationKey) else {
            return nil
        }
        return MusicPlayerApplication(rawValue: rawValue)
    }

    func record(source: String) {
        guard let application = MusicPlayerApplication.from(source: source) else { return }
        defaults.set(application.rawValue, forKey: Self.rememberedApplicationKey)
    }

    func preferredApplication(
        isInstalled: (MusicPlayerApplication) -> Bool
    ) -> MusicPlayerApplication? {
        if let rememberedApplication, isInstalled(rememberedApplication) {
            return rememberedApplication
        }
        return isInstalled(.appleMusic) ? .appleMusic : nil
    }
}
