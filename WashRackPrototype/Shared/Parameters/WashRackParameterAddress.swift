import AVFoundation

enum WashRackParameterAddress: AUParameterAddress, CaseIterable, Sendable {
    case inputGain = 0
    case outputGain = 1
    case delayTime = 2
    case feedback = 3
    case dryWetMix = 4
    case lowPassCutoff = 5
    case lowPassResonance = 6
    case effectEnabled = 7
}
