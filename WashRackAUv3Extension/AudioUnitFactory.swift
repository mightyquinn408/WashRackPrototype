import CoreAudioKit
import Foundation

public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    public func beginRequest(with context: NSExtensionContext) {
    }

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        try WashRackAudioUnit(componentDescription: componentDescription, options: [])
    }
}
