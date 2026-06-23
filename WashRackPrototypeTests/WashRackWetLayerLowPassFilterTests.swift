import AVFoundation
import Testing
@testable import WashRackPrototype

struct WashRackWetLayerLowPassFilterTests {

    @Test
    func higherResonanceProducesHigherQ() {
        let lowQ = WashRackWetLayerLowPassFilter.resonanceQ(fromDecibels: -20)
        let defaultQ = WashRackWetLayerLowPassFilter.resonanceQ(fromDecibels: 0)
        let highQ = WashRackWetLayerLowPassFilter.resonanceQ(fromDecibels: 20)

        #expect(lowQ < defaultQ)
        #expect(defaultQ < highQ)
    }

    @Test
    func lowerCutoffAttenuatesHighFrequencyContentMoreThanHigherCutoff() {
        let sampleRate = 44_100.0
        let lowCutoffCoefficients = WashRackWetLayerLowPassFilter.coefficients(
            sampleRate: sampleRate,
            cutoff: 250,
            resonance: 0
        )
        let highCutoffCoefficients = WashRackWetLayerLowPassFilter.coefficients(
            sampleRate: sampleRate,
            cutoff: 12_000,
            resonance: 0
        )

        var lowCutoffFilter = WashRackWetLayerLowPassFilter()
        var highCutoffFilter = WashRackWetLayerLowPassFilter()
        let alternatingSignal: [AUValue] = (0 ..< 128).map { $0.isMultiple(of: 2) ? 1 : -1 }

        var lowCutoffEnergy: AUValue = 0
        var highCutoffEnergy: AUValue = 0

        for sample in alternatingSignal {
            lowCutoffEnergy += abs(
                lowCutoffFilter.process(
                    sample: sample,
                    channelIndex: 0,
                    coefficients: lowCutoffCoefficients
                )
            )
            highCutoffEnergy += abs(
                highCutoffFilter.process(
                    sample: sample,
                    channelIndex: 0,
                    coefficients: highCutoffCoefficients
                )
            )
        }

        #expect(lowCutoffEnergy < highCutoffEnergy)
    }
}
