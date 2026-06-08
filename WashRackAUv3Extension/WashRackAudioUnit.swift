import AVFoundation

public final class WashRackAudioUnit: AUAudioUnit, @unchecked Sendable {
    private let washRackParameterTree: AUParameterTree
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!

    @objc public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) throws {
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        washRackParameterTree = WashRackParameterTreeFactory.makeParameterTree()
        inputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2

        try super.init(componentDescription: componentDescription, options: options)

        parameterTree = washRackParameterTree
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 512
    }

    public override var inputBusses: AUAudioUnitBusArray {
        inputBusArray
    }

    public override var outputBusses: AUAudioUnitBusArray {
        outputBusArray
    }

    public override var canProcessInPlace: Bool {
        true
    }

    public override var channelCapabilities: [NSNumber] {
        [1, 1, 2, 2]
    }

    public override func allocateRenderResources() throws {
        let inputFormat = inputBus.format
        let outputFormat = outputBus.format

        guard inputFormat.channelCount == outputFormat.channelCount,
              inputFormat.sampleRate == outputFormat.sampleRate else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_FormatNotSupported)
            )
        }

        try super.allocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, _, pullInputBlock in
            guard let self, self.renderResourcesAllocated else {
                return kAudioUnitErr_Uninitialized
            }

            guard outputBusNumber == 0 else {
                return kAudioUnitErr_InvalidElement
            }

            guard let pullInputBlock else {
                return kAudioUnitErr_NoConnection
            }

            return pullInputBlock(actionFlags, timestamp, frameCount, 0, outputData)
        }
    }
}
