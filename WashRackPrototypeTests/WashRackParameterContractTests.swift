import AVFoundation
import Testing
@testable import WashRackPrototype

struct WashRackParameterContractTests {

    @Test
    func stableAddressesMatchExpectedContract() {
        #expect(WashRackParameterAddress.inputGain.rawValue == 0)
        #expect(WashRackParameterAddress.outputGain.rawValue == 1)
        #expect(WashRackParameterAddress.delayTime.rawValue == 2)
        #expect(WashRackParameterAddress.feedback.rawValue == 3)
        #expect(WashRackParameterAddress.dryWetMix.rawValue == 4)
        #expect(WashRackParameterAddress.lowPassCutoff.rawValue == 5)
        #expect(WashRackParameterAddress.lowPassResonance.rawValue == 6)
        #expect(WashRackParameterAddress.effectEnabled.rawValue == 7)
    }

    @Test
    func specsCoverEveryAddressExactlyOnce() {
        let specs = WashRackParameterSpec.all
        let addresses = specs.map { $0.address.rawValue }
        let identifiers = specs.map(\.identifier)

        #expect(specs.count == WashRackParameterAddress.allCases.count)
        #expect(Set(addresses).count == specs.count)
        #expect(Set(identifiers).count == specs.count)
    }

    @Test
    func specsExposeStableMetadata() {
        assertSpec(
            .inputGain,
            identifier: "inputGain",
            name: "Input Gain",
            range: -24 ... 24,
            unit: .decibels,
            defaultValue: 0
        )
        assertSpec(
            .outputGain,
            identifier: "outputGain",
            name: "Output Gain",
            range: -24 ... 24,
            unit: .decibels,
            defaultValue: 0
        )
        assertSpec(
            .delayTime,
            identifier: "delayTime",
            name: "Delay Time",
            range: 0.01 ... 2.0,
            unit: .seconds,
            defaultValue: 0.35
        )
        assertSpec(
            .feedback,
            identifier: "feedback",
            name: "Feedback",
            range: 0 ... 95,
            unit: .percent,
            defaultValue: 35
        )
        assertSpec(
            .dryWetMix,
            identifier: "dryWetMix",
            name: "Dry/Wet Mix",
            range: 0 ... 100,
            unit: .percent,
            defaultValue: 40
        )
        assertSpec(
            .lowPassCutoff,
            identifier: "lowPassCutoff",
            name: "Low-Pass Cutoff",
            range: 100 ... 18_000,
            unit: .hertz,
            defaultValue: 6_000
        )
        assertSpec(
            .lowPassResonance,
            identifier: "lowPassResonance",
            name: "Low-Pass Resonance",
            range: -20 ... 20,
            unit: .decibels,
            defaultValue: 0
        )
        assertSpec(
            .effectEnabled,
            identifier: "effectEnabled",
            name: "Effect Enabled",
            range: 0 ... 1,
            unit: .boolean,
            defaultValue: 1
        )
    }

    @Test
    func treeFactoryBuildsParametersFromSharedSpecs() throws {
        let tree = WashRackParameterTreeFactory.makeParameterTree()

        #expect(tree.allParameters.count == WashRackParameterSpec.all.count)

        for spec in WashRackParameterSpec.all {
            let parameter = try #require(tree.parameter(withAddress: spec.address.rawValue))

            #expect(parameter.identifier == spec.identifier)
            #expect(parameter.displayName == spec.name)
            #expect(parameter.minValue == spec.minValue)
            #expect(parameter.maxValue == spec.maxValue)
            #expect(parameter.unit == spec.unit)
            #expect(parameter.value == spec.defaultValue)
            #expect(parameter.flags == spec.flags)
        }
    }

    private func assertSpec(
        _ address: WashRackParameterAddress,
        identifier: String,
        name: String,
        range: ClosedRange<AUValue>,
        unit: AudioUnitParameterUnit,
        defaultValue: AUValue
    ) {
        let spec = WashRackParameterSpec.spec(for: address)

        #expect(spec.address == address)
        #expect(spec.identifier == identifier)
        #expect(spec.name == name)
        #expect(spec.range.lowerBound == range.lowerBound)
        #expect(spec.range.upperBound == range.upperBound)
        #expect(spec.unit == unit)
        #expect(spec.defaultValue == defaultValue)
        #expect(spec.flags == expectedFlags(for: address))

        let identifierLookup = WashRackParameterSpec.spec(for: identifier)
        #expect(identifierLookup?.address == spec.address)
        #expect(identifierLookup?.identifier == spec.identifier)
    }

    private func expectedFlags(for address: WashRackParameterAddress) -> AudioUnitParameterOptions {
        switch address {
        case .effectEnabled:
            WashRackParameterSpec.booleanFlags
        case .inputGain, .outputGain, .delayTime, .feedback, .dryWetMix, .lowPassCutoff, .lowPassResonance:
            WashRackParameterSpec.continuousFlags
        }
    }
}
