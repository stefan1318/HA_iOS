import SwiftUI
import Speech
import AVFoundation

struct StevoraMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

@MainActor
final class StevoraAssistModel: ObservableObject {
    @Published var messages: [StevoraMessage] = []
    @Published var draft = ""
    @Published var busy = false
    @Published var listening = false
    @Published var error: String?
    private var conversationID: String?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "bg-BG"))
    private let audioEngine = AVAudioEngine()
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?

    func send(address: String, token: String) async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !busy else { return }
        draft = ""
        messages.append(StevoraMessage(role: "user", content: message))
        busy = true
        defer { busy = false }
        do {
            let client = try HAClient(address: address, token: token)
            let (answer, nextID) = try await client.conversation(text: message, conversationID: conversationID)
            conversationID = nextID
            messages.append(StevoraMessage(role: "assistant", content: answer))
        } catch { self.error = error.localizedDescription }
    }

    func startListening() async {
        guard !listening else { stopListening(); return }
        let speechPermission = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechPermission else { error = "Speech recognition permission required"; return }
        let microphone = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
        guard microphone else { error = "Microphone permission required"; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            speechRequest = request
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            listening = true
            recognition = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
                guard let result else { return }
                Task { @MainActor in self?.draft = result.bestTranscription.formattedString }
            }
        } catch {
            stopListening()
            self.error = error.localizedDescription
        }
    }

    func stopListening() {
        if audioEngine.isRunning { audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0) }
        speechRequest?.endAudio()
        recognition?.cancel()
        recognition = nil
        speechRequest = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

struct StevoraAssistView: View {
    @EnvironmentObject private var model: StevoraModel
    @StateObject private var assist = StevoraAssistModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle.fill").font(.title)
                Text("STEVORA Assist").font(.title2.bold())
                Spacer()
            }.foregroundStyle(.cyan)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(assist.messages) { item in
                            HStack {
                                if item.role == "user" { Spacer(minLength: 36) }
                                Text(item.content)
                                    .padding(14)
                                    .background(item.role == "user" ? Color.cyan.opacity(0.24) : Color.white.opacity(0.09),
                                                in: RoundedRectangle(cornerRadius: 16))
                                if item.role != "user" { Spacer(minLength: 36) }
                            }.id(item.id)
                        }
                    }
                }.onChange(of: assist.messages.count) { _ in
                    if let id = assist.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            if let error = assist.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                TextField(model.localized("Попитай STEVORA...", "Ask STEVORA..."), text: $assist.draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button {
                    Task { await assist.startListening() }
                } label: {
                    Image(systemName: assist.listening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                }.accessibilityLabel(assist.listening ? "Stop recording" : "Start recording")
                Button {
                    Task { await assist.send(address: model.address, token: model.token) }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(assist.busy || assist.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .onDisappear { assist.stopListening() }
    }
}
