import ISSoundAdditions

struct WorkspaceSidebarAudioSnapshot: Equatable {
    let volumePercent: Int?
    let isMuted: Bool

    var label: String {
        if isMuted {
            return "Mute"
        }
        return volumePercent.map { "\($0)%" } ?? "Audio"
    }

    var symbolName: String {
        if isMuted {
            return "speaker.slash.fill"
        }
        guard let volumePercent else {
            return "speaker.slash"
        }
        switch volumePercent {
            case ..<34:
                return "speaker.wave.1.fill"
            case ..<67:
                return "speaker.wave.2.fill"
            default:
                return "speaker.wave.3.fill"
        }
    }

    var accessibilityDescription: String {
        if isMuted {
            return "Sound muted"
        }
        return volumePercent.map { "Sound output volume \($0) percent" } ?? "Sound output unavailable"
    }

    static func current() -> Self {
        let isMuted = Sound.output.isMuted
        let volumePercent = (try? Sound.output.readVolume())
            .map { Int(($0 * 100).rounded()) }
        return .init(volumePercent: volumePercent, isMuted: isMuted)
    }
}
