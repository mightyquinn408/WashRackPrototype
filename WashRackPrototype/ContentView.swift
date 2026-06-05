import AudioKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var audioEngineController = AudioEngineController()
    @State private var isShowingFileImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("WashRack Prototype")
                .font(.largeTitle.weight(.bold))

            Text("Signal flow: AudioPlayer -> Delay -> LowPassFilter -> Output")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Load Audio File") {
                    isShowingFileImporter = true
                }

                Button(audioEngineController.isPlaying ? "Stop" : "Play") {
                    audioEngineController.togglePlayback()
                }
                .disabled(!audioEngineController.isFileLoaded)

                Text(audioEngineController.selectedFileName)
                    .foregroundStyle(audioEngineController.isFileLoaded ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Output Meter")
                    .font(.headline)
                LevelMeter(level: audioEngineController.outputLevel)
                Text(audioEngineController.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            GroupBox("Delay") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Bypass Delay", isOn: $audioEngineController.isDelayBypassed)
                    ParameterSlider(
                        title: "Time",
                        value: $audioEngineController.delayTime,
                        range: 0.01 ... 2.0,
                        format: "%.2f s"
                    )
                    ParameterSlider(
                        title: "Feedback",
                        value: $audioEngineController.delayFeedback,
                        range: 0 ... 95,
                        format: "%.0f %%"
                    )
                    ParameterSlider(
                        title: "Mix",
                        value: $audioEngineController.delayMix,
                        range: 0 ... 100,
                        format: "%.0f %%"
                    )
                }
            }

            GroupBox("Filter") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Bypass Filter", isOn: $audioEngineController.isFilterBypassed)
                    ParameterSlider(
                        title: "Cutoff",
                        value: $audioEngineController.filterCutoff,
                        range: 100 ... 18_000,
                        format: "%.0f Hz"
                    )
                    ParameterSlider(
                        title: "Resonance",
                        value: $audioEngineController.filterResonance,
                        range: -20 ... 20,
                        format: "%.1f dB"
                    )
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 520, alignment: .topLeading)
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                audioEngineController.loadFile(from: url)
            case .failure(let error):
                audioEngineController.handleFileImportFailure(error)
            }
        }
        .onAppear {
            audioEngineController.startEngine()
        }
        .onDisappear {
            audioEngineController.stopEngine()
        }
    }
}

#Preview {
    ContentView()
}

private struct ParameterSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range)
        }
    }
}

private struct LevelMeter: View {
    let level: Float

    private var clampedLevel: CGFloat {
        CGFloat(min(max(level * 2.5, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))

                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * clampedLevel)
            }
        }
        .frame(height: 18)
    }
}
