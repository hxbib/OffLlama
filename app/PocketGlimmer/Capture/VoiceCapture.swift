import AVFoundation
import Observation
import SwiftUI
import PocketCore

/// Hold-to-talk recorder. Writes 16 kHz mono 16-bit PCM WAV to a temporary file: that is the format Muse Voice
/// Transcribe's file endpoint accepts (`audioEncoding: "WAV"`, 16 or 24 kHz mono; AAC/m4a is rejected), so nothing is
/// transcoded and the bytes sent are exactly the bytes recorded (~32 KB per second). The file is deleted as soon as it
/// has been read, unless the user opted in to keeping recordings (UserDefaults "keep_voice_recordings").
@MainActor @Observable
final class VoiceRecorder {
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var url: URL?

    var keepRecordings: Bool { UserDefaults.standard.bool(forKey: "keep_voice_recordings") }

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("glimmer-voice-\(UUID().uuidString).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let r = try AVAudioRecorder(url: u, settings: settings)
            guard r.record(forDuration: 60) else { return }      // hard cap: one minute per turn
            recorder = r; url = u; isRecording = true; startedAt = Date()
        } catch {
            isRecording = false
        }
    }

    /// Stops and returns the WAV bytes. The temporary file is removed before this returns (unless opted in).
    func stop() -> Data? {
        guard isRecording, let r = recorder, let u = url else { return nil }
        r.stop()
        isRecording = false; recorder = nil; url = nil; startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let data = try? Data(contentsOf: u)
        if keepRecordings {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings")
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: u, to: docs.appendingPathComponent(u.lastPathComponent))
        } else {
            try? FileManager.default.removeItem(at: u)
        }
        return data
    }
}

/// Record-and-upload button for the composer (waveform, not Apple Dictation): press and hold to talk, release to send. The transcript goes through
/// `AppModel.send` (and so `Assistant.handle`) exactly like typed text: same Reflex decisions, same sensitivity gate,
/// same badges. Online-only; offline it records nothing and says so.
struct MicButton: View {
    @Environment(AppModel.self) private var model
    @State private var recorder = VoiceRecorder()
    @State private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var iconSize = 30

    var body: some View {
        Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "waveform.circle")
            .font(.system(size: iconSize))
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(recorder.isRecording ? Color.red : (model.isOnline ? Theme.accent : Color.secondary))
            .symbolEffect(.pulse, isActive: recorder.isRecording && !reduceMotion)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        Task { await begin() }
                    }
                    .onEnded { _ in
                        pressing = false
                        Task { await finish() }
                    }
            )
            .disabled(model.busy)
            .accessibilityLabel(recorder.isRecording ? "Recording for upload. Release to send." : "Hold to record and upload")
            .accessibilityHint("Sends the recording to Muse Voice Transcribe. Needs internet and a Meta key. For Apple Dictation, use the microphone on the keyboard.")
            .accessibilityAddTraits(.isButton)
    }

    private func note(_ text: String) { model.post(.init(role: .system, text: text)) }

    private func begin() async {
        guard !model.busy else { return }
        guard !UserDefaults.standard.bool(forKey: "voice_stays_on_device") else { note("Voice upload is off in Settings. Type your request to keep it on this iPhone."); return }
        guard model.isOnline else { note(MultimodalGate.offlineMessage); return }
        guard Keychain.get("meta_key") != nil else { note("Voice needs a Meta Model API key (Settings). Nothing was recorded."); return }
        guard await recorder.requestPermission() else { note("Microphone access is off (Settings > Privacy > Microphone)."); return }
        guard pressing, !model.busy else { return }          // released while the permission prompt was up
        recorder.start()
    }

    private func finish() async {
        guard let wav = recorder.stop() else { return }
        guard wav.count > 44 + 16_000 else { note("Hold the mic while you speak."); return }   // < 0.5 s
        guard !model.busy else { note("Another request is in progress. The recording was not sent."); return }
        guard !UserDefaults.standard.bool(forKey: "voice_stays_on_device") else { note("Voice upload is off. The recording was not sent."); return }
        guard let assistant = model.assistant else { return }
        let gate = MultimodalGate(assistant: assistant, metaAPIKey: Keychain.get("meta_key"))
        gate.voiceStaysOnDevice = UserDefaults.standard.bool(forKey: "voice_stays_on_device")
        model.busy = true
        do {
            guard let res = try await gate.transcribe(audio: wav) else { model.busy = false; note(MultimodalGate.offlineMessage); return }
            model.busy = false
            let (t, sent) = res
            guard !t.text.isEmpty else { note("Didn't catch that. Only the audio was sent; nothing reached the assistant."); return }
            let secs = String(format: "%.1f", Double(t.durationMs) / 1000), kb = String(format: "%.0f", Double(sent.bytesSent) / 1024)
            note("Muse Voice Transcribe · \(secs) s audio · \(kb) KB sent · recording \(recorder.keepRecordings ? "kept on this iPhone" : "deleted")")
            await model.send(t.text)            // identical path to typed text
        } catch {
            model.busy = false
            note("Voice failed: \(error.localizedDescription). Nothing else was sent.")
        }
    }
}
