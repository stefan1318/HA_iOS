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
    @Published var voiceReplies = true
    private let speaker = AVSpeechSynthesizer()
    @Published var error: String?
    @Published var route: StevoraAssistantRoute?
    @Published var status = "Checking account and Assist pipelines…"

    private var conversationID: String?
    private var selectedPipelineID: String?
    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?

    func inspect(address: String, token: String) async {
        guard !busy else { return }
        route = nil
        status = "Verifying Home Hub account…"
        do {
            let selected = try await StevoraAssistantGateway(address: address, token: token).inspect()
            if selected.pipelineID != selectedPipelineID {
                conversationID = nil
                messages = []
                selectedPipelineID = selected.pipelineID
            }
            route = selected
            status = "\(selected.pipelineName) • \(selected.roleLabel)"
            error = nil
        } catch {
            route = nil  // Fail closed. Never use an arbitrary/default agent.
            selectedPipelineID = nil
            conversationID = nil
            status = "Assist unavailable for this account"
            self.error = error.localizedDescription
        }
    }

    func send(address: String, token: String) async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !busy, route != nil else { return }
        busy = true
        error = nil
        draft = ""
        messages.append(StevoraMessage(role: "user", content: message))
        defer { busy = false }
        do {
            let (answer, newID, verified) = try await StevoraAssistantGateway(
                address: address, token: token
            ).converse(text: message, conversationID: conversationID,
                       expectedPipelineID: selectedPipelineID ?? "")
            // The session is reverified server-side on every command.
            if let previous = selectedPipelineID, previous != verified.pipelineID {
                conversationID = nil
                messages = []
                selectedPipelineID = verified.pipelineID
                route = verified
                status = "\(verified.pipelineName) • \(verified.roleLabel)"
                error = "Account or pipeline changed. Start a new conversation."
                return
            }
            conversationID = newID
            route = verified
            status = "\(verified.pipelineName) • \(verified.roleLabel)"
            messages.append(StevoraMessage(role: "assistant", content: answer))
            if voiceReplies { speak(answer) }
        } catch {
            route = nil
            selectedPipelineID = nil
            conversationID = nil
            status = "Assist connection unavailable"
            self.error = error.localizedDescription
        }
    }

    private func speak(_ text: String) {
        let plain = text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "###", with: "")
        let utterance = AVSpeechUtterance(string: plain)
        utterance.voice = AVSpeechSynthesisVoice(language: "bg-BG")
        utterance.rate = 0.48
        speaker.stopSpeaking(at: .immediate)
        speaker.speak(utterance)
    }

    func startListening() async {
        guard route != nil else { error = "Verify account and Assist pipeline first"; return }
        speaker.stopSpeaking(at: .immediate)
        guard !listening else { stopListening(); return }
        let authorized = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard authorized else { error = "Разреши разпознаването на реч в Settings → STEVORA."; return }
        let locales = ["bg-BG", "en-US", "en-GB"]
        recognizer = locales.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first(where: { $0.isAvailable })
        guard recognizer != nil else {
            error = "Няма налично разпознаване на реч. Провери Siri, диктовката и интернет връзката."
            return
        }
        let microphone = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
        guard microphone else { error = "Разреши достъп до микрофона в Settings → STEVORA."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false
            speechRequest = request
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            listening = true
            recognition = recognizer?.recognitionTask(with: request) { [weak self] result, recognitionError in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.draft = result.bestTranscription.formattedString
                        if result.isFinal { self.stopListening() }
                    } else if let recognitionError {
                        self.error = recognitionError.localizedDescription
                        self.stopListening()
                    }
                }
            }
        } catch {
            stopListening()
            self.error = error.localizedDescription
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
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
    @StateObject private var assistant = StevoraAssistModel()
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                Image(systemName: "waveform")
                    .font(.title2.bold()).foregroundStyle(Brand.background)
                    .frame(width: 49, height: 49)
                    .background(Brand.cyan, in: Circle())
                    .scaleEffect(assistant.listening ? 1.12 : 1)
                    .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                               value: assistant.listening)
                VStack(alignment: .leading, spacing: 5) {
                    Text("STEVORA AI").font(.title2.bold()).foregroundStyle(Brand.light)
                    Text(assistant.status).font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
                Button {
                    Task { await assistant.inspect(address: model.address, token: model.token) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.headline)
                }
                .accessibilityLabel("Refresh STEVORA Assist")
            }
            .padding(18)
            .modifier(StevoraGlassCard())

            if let route = assistant.route {
                HStack {
                    Image(systemName: route.isAdmin ? "checkmark.shield.fill" : "person.crop.circle")
                    Text(route.roleLabel)
                    Spacer()
                    Text(route.accountName).lineLimit(1)
                }
                .font(.caption.bold()).foregroundStyle(Brand.mint)
                .padding(.horizontal, 12)
            }
            if let error = assistant.error {
                Text(error).font(.footnote).foregroundStyle(.orange).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(StevoraGlassCard())
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        if assistant.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Image("StevoraLogo").resizable().scaledToFit()
                                    .frame(width: 74, height: 74)
                                Text(model.localized("Твоят дом. Твоят интелект.",
                                                     "Your home. Your intelligence."))
                                    .font(.title3.bold())
                                Text(model.localized("Асистентът се избира от сървъра според правата на акаунта.",
                                                     "Your assistant is selected by your verified Home Hub role."))
                                    .foregroundStyle(Brand.muted).font(.subheadline)
                            }
                            .padding(22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(StevoraGlassCard())
                        }
                        ForEach(assistant.messages) { message in
                            HStack {
                                if message.role == "user" { Spacer(minLength: 42) }
                                Text((try? AttributedString(markdown: message.content)) ?? AttributedString(message.content))
                                    .font(.body)
                                    .foregroundStyle(Brand.light)
                                    .padding(16)
                                    .background(message.role == "user" ? Brand.cyan.opacity(0.27)
                                                : Brand.raised.opacity(0.92),
                                                in: RoundedRectangle(cornerRadius: 20))
                                if message.role != "user" { Spacer(minLength: 42) }
                            }
                            .id(message.id)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                    removal: .opacity))
                        }
                    }
                    .padding(.vertical, 9)
                    .animation(.spring(response: 0.38, dampingFraction: 0.84),
                               value: assistant.messages.count)
                }
                .safeAreaPadding(.bottom, 12)
                .onChange(of: assistant.messages.count) { _ in
                    if let last = assistant.messages.last {
                        withAnimation(.easeOut(duration: 0.26)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minHeight: 200)

            HStack(alignment: .bottom, spacing: 11) {
                TextField(model.localized("Попитай STEVORA...", "Ask STEVORA..."),
                          text: $assistant.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .font(.body)
                    .foregroundStyle(Brand.light)
                    .padding(11)
                Button {
                    if assistant.listening {
                        assistant.stopListening()
                    } else {
                        Task { await assistant.startListening() }
                    }
                } label: {
                    Image(systemName: assistant.listening ? "stop.circle.fill" : "mic.fill")
                        .font(.title2).frame(width: 42, height: 44)
                        .foregroundStyle(assistant.listening ? .orange : Brand.cyan)
                }
                .disabled(assistant.route == nil || assistant.busy)
                .accessibilityLabel(assistant.listening ? "Stop recording" : "Start recording")
                Button {
                    if assistant.listening { assistant.stopListening() }
                    composerFocused = false
                    Task { await assistant.send(address: model.address, token: model.token) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30)).frame(width: 42, height: 44)
                        .foregroundStyle(Brand.cyan)
                }
                .disabled(assistant.busy || assistant.route == nil ||
                          assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(9)
            .modifier(StevoraGlassCard())
            Toggle(model.localized("Гласови отговори", "Spoken replies"), isOn: $assistant.voiceReplies)
                .font(.caption).tint(Brand.cyan)
            if assistant.busy { ProgressView().tint(Brand.cyan).frame(maxWidth: .infinity) }
        }
        .task {
            await assistant.inspect(address: model.address, token: model.token)
        }
        .onChange(of: model.token) { _ in
            Task { await assistant.inspect(address: model.address, token: model.token) }
        }
        .onDisappear { assistant.stopListening() }
    }
}
