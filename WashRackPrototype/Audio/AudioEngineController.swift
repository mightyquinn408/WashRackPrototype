import AudioKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioEngineController: ObservableObject {
    let engine = AudioEngine()
    let player = AudioPlayer()

    private let delay: Delay
    private let lowPassFilter: LowPassFilter
    private lazy var outputTap = AmplitudeTap(lowPassFilter, callbackQueue: .main) { [weak self] amplitude in
        self?.outputLevel = amplitude
    }

    @Published private(set) var isEngineRunning = false
    @Published private(set) var isFileLoaded = false
    @Published private(set) var isPlaying = false
    @Published private(set) var selectedFileName = "No file loaded"
    @Published private(set) var statusMessage = "Load an audio file to audition the effect chain."
    @Published private(set) var outputLevel: Float = 0

    @Published var delayTime: Float = 0.35 {
        didSet { delay.time = delayTime }
    }

    @Published var delayFeedback: Float = 35 {
        didSet { delay.feedback = delayFeedback }
    }

    @Published var delayMix: Float = 40 {
        didSet { delay.dryWetMix = delayMix }
    }

    @Published var filterCutoff: Float = 6_000 {
        didSet { lowPassFilter.cutoffFrequency = filterCutoff }
    }

    @Published var filterResonance: Float = 0 {
        didSet { lowPassFilter.resonance = filterResonance }
    }

    @Published var isDelayBypassed = false {
        didSet { updateEffectBypassStates() }
    }

    @Published var isFilterBypassed = false {
        didSet { updateEffectBypassStates() }
    }

    private let importedAudioDirectory: URL = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WashRackPrototypeImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    init() {
        player.isLooping = true

        delay = Delay(player)
        lowPassFilter = LowPassFilter(delay)
        engine.output = lowPassFilter

        applyDefaultParameters()
        updateEffectBypassStates()
    }

    func startEngine() {
        guard !isEngineRunning else { return }

        do {
            try engine.start()
            outputTap.start()
            isEngineRunning = true
            statusMessage = isFileLoaded
                ? "Engine running. Press Play to hear the current file."
                : "Engine running. Load an audio file to begin."
        } catch {
            statusMessage = "Could not start the audio engine: \(error.localizedDescription)"
        }
    }

    func stopEngine() {
        guard isEngineRunning else { return }

        player.stop()
        outputTap.stop()
        engine.stop()

        isPlaying = false
        isEngineRunning = false
        outputLevel = 0
        statusMessage = "Engine stopped."
    }

    func togglePlayback() {
        guard isFileLoaded else {
            statusMessage = "Load an audio file before pressing Play."
            return
        }

        if !isEngineRunning {
            startEngine()
        }

        if isPlaying {
            player.stop()
            isPlaying = false
            statusMessage = "Playback stopped."
        } else {
            player.play()
            isPlaying = true
            statusMessage = "Playback started."
        }
    }

    func loadFile(from url: URL) {
        let shouldResumePlayback = isPlaying

        player.stop()
        isPlaying = false

        do {
            let importedFileURL = try prepareImportedFile(from: url)
            try player.load(url: importedFileURL, buffered: true)
            player.isLooping = true

            selectedFileName = url.lastPathComponent
            isFileLoaded = true
            statusMessage = "Loaded \(selectedFileName)."

            if shouldResumePlayback {
                togglePlayback()
            }
        } catch {
            selectedFileName = "No file loaded"
            isFileLoaded = false
            statusMessage = "Could not load file: \(error.localizedDescription)"
        }
    }

    func handleFileImportFailure(_ error: Error) {
        statusMessage = "Could not import file: \(error.localizedDescription)"
    }

    private func applyDefaultParameters() {
        delay.time = delayTime
        delay.feedback = delayFeedback
        delay.dryWetMix = delayMix
        lowPassFilter.cutoffFrequency = filterCutoff
        lowPassFilter.resonance = filterResonance
    }

    private func prepareImportedFile(from url: URL) throws -> URL {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = importedAudioDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(url.pathExtension)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: url, to: destinationURL)
        return destinationURL
    }

    private func updateEffectBypassStates() {
        if isDelayBypassed {
            delay.stop()
        } else {
            delay.start()
        }

        if isFilterBypassed {
            lowPassFilter.stop()
        } else {
            lowPassFilter.start()
        }
    }
}
