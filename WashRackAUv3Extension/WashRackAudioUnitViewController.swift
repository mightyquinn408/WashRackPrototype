import AppKit
import AudioToolbox
import CoreAudioKit
import SwiftUI

@MainActor
public final class WashRackAudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: AUAudioUnit?
    private var hostingController: NSHostingController<WashRackMainView>?
    private var observation: NSKeyValueObservation?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 360, height: 140)
        guard let audioUnit else {
            return
        }
        configureViewIfPossible(audioUnit: audioUnit)
    }

    nonisolated public func createAudioUnit(
        with componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try makeAudioUnit(componentDescription: componentDescription)
            }
        }

        return try DispatchQueue.main.sync {
            try self.makeAudioUnit(componentDescription: componentDescription)
        }
    }

    private func makeAudioUnit(
        componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        let audioUnit = try WashRackAudioUnit(
            componentDescription: componentDescription,
            options: []
        )

        self.audioUnit = audioUnit
        observation = audioUnit.observe(\.allParameterValues, options: [.new]) { _, _ in
            guard let parameterTree = audioUnit.parameterTree else {
                return
            }

            for parameter in parameterTree.allParameters {
                parameter.value = parameter.value
            }
        }

        DispatchQueue.main.async {
            self.configureViewIfPossible(audioUnit: audioUnit)
        }

        return audioUnit
    }

    private func configureViewIfPossible(audioUnit: AUAudioUnit) {
        if let hostingController {
            hostingController.removeFromParent()
            hostingController.view.removeFromSuperview()
        }

        guard let observableParameterTree = audioUnit.observableParameterTree else {
            return
        }

        let hostingController = NSHostingController(
            rootView: WashRackMainView(parameterTree: observableParameterTree)
        )

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.hostingController = hostingController
    }
}
