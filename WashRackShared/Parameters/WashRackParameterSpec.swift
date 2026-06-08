import AVFoundation

struct WashRackParameterSpec: Sendable {
    let address: WashRackParameterAddress
    let identifier: String
    let name: String
    let range: ClosedRange<AUValue>
    let unit: AudioUnitParameterUnit
    let defaultValue: AUValue
    let flags: AudioUnitParameterOptions

    nonisolated var minValue: AUValue { range.lowerBound }
    nonisolated var maxValue: AUValue { range.upperBound }

    nonisolated static let continuousFlags: AudioUnitParameterOptions = [
        .flag_IsReadable,
        .flag_IsWritable,
        .flag_CanRamp
    ]

    nonisolated static let booleanFlags: AudioUnitParameterOptions = [
        .flag_IsReadable,
        .flag_IsWritable
    ]

    nonisolated static let all = WashRackParameterAddress.allCases.map { spec(for: $0) }

    nonisolated static func spec(for address: WashRackParameterAddress) -> WashRackParameterSpec {
        switch address {
        case .inputGain:
            return WashRackParameterSpec(
                address: .inputGain,
                identifier: "inputGain",
                name: "Input Gain",
                range: -24 ... 24,
                unit: .decibels,
                defaultValue: 0,
                flags: continuousFlags
            )
        case .outputGain:
            return WashRackParameterSpec(
                address: .outputGain,
                identifier: "outputGain",
                name: "Output Gain",
                range: -24 ... 24,
                unit: .decibels,
                defaultValue: 0,
                flags: continuousFlags
            )
        case .delayTime:
            return WashRackParameterSpec(
                address: .delayTime,
                identifier: "delayTime",
                name: "Delay Time",
                range: 0.01 ... 2.0,
                unit: .seconds,
                defaultValue: 0.35,
                flags: continuousFlags
            )
        case .feedback:
            return WashRackParameterSpec(
                address: .feedback,
                identifier: "feedback",
                name: "Feedback",
                range: 0 ... 95,
                unit: .percent,
                defaultValue: 35,
                flags: continuousFlags
            )
        case .dryWetMix:
            return WashRackParameterSpec(
                address: .dryWetMix,
                identifier: "dryWetMix",
                name: "Dry/Wet Mix",
                range: 0 ... 100,
                unit: .percent,
                defaultValue: 40,
                flags: continuousFlags
            )
        case .lowPassCutoff:
            return WashRackParameterSpec(
                address: .lowPassCutoff,
                identifier: "lowPassCutoff",
                name: "Low-Pass Cutoff",
                range: 100 ... 18_000,
                unit: .hertz,
                defaultValue: 6_000,
                flags: continuousFlags
            )
        case .lowPassResonance:
            return WashRackParameterSpec(
                address: .lowPassResonance,
                identifier: "lowPassResonance",
                name: "Low-Pass Resonance",
                range: -20 ... 20,
                unit: .decibels,
                defaultValue: 0,
                flags: continuousFlags
            )
        case .effectEnabled:
            return WashRackParameterSpec(
                address: .effectEnabled,
                identifier: "effectEnabled",
                name: "Effect Enabled",
                range: 0 ... 1,
                unit: .boolean,
                defaultValue: 1,
                flags: booleanFlags
            )
        }
    }

    nonisolated static func spec(for identifier: String) -> WashRackParameterSpec? {
        all.first { $0.identifier == identifier }
    }
}
