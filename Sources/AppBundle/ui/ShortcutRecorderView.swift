import MASShortcut
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: MASShortcut?
    var onChange: (MASShortcut?) -> Void

    func makeNSView(context: Context) -> RecordingAwareShortcutView {
        let recorder = RecordingAwareShortcutView(frame: .zero)
        recorder.shortcutValidator = nil
        recorder.onRecordingChanged = { isRecording in
            Task { @MainActor in
                setHotkeysSuspended(isRecording)
            }
        }
        recorder.shortcutValueChange = { sender in
            let newValue = sender.shortcutValue
            shortcut = newValue
            onChange(newValue)
        }
        return recorder
    }

    func updateNSView(_ nsView: RecordingAwareShortcutView, context: Context) {
        guard !nsView.isRecording else { return }
        let shouldUpdate: Bool
        if let shortcut, let existing = nsView.shortcutValue {
            shouldUpdate = !existing.isEqual(shortcut)
        } else {
            shouldUpdate = (shortcut != nil) || (nsView.shortcutValue != nil)
        }
        if shouldUpdate {
            nsView.shortcutValue = shortcut
        }
    }

    static func dismantleNSView(_ nsView: RecordingAwareShortcutView, coordinator: ()) {
        nsView.onRecordingChanged = { _ in }
        Task { @MainActor in
            setHotkeysSuspended(false)
        }
    }
}

final class RecordingAwareShortcutView: MASShortcutView {
    var onRecordingChanged: (Bool) -> Void = { _ in }

    override var isRecording: Bool {
        didSet {
            guard oldValue != isRecording else { return }
            onRecordingChanged(isRecording)
        }
    }
}
