import AudioToolbox

@MainActor
@dynamicMemberLookup
class ObservableAUParameterNode {
    class func create(_ parameterNode: AUParameterNode) -> ObservableAUParameterNode {
        switch parameterNode {
        case let parameter as AUParameter:
            return ObservableAUParameter(parameter)
        case let group as AUParameterGroup:
            return ObservableAUParameterGroup(group)
        default:
            fatalError("Unexpected AUParameterNode subclass")
        }
    }

    subscript<T>(dynamicMember identifier: String) -> T {
        guard let groupSelf = self as? ObservableAUParameterGroup else {
            fatalError("Dynamic-member lookup requires an ObservableAUParameterGroup")
        }

        guard let node = groupSelf.children[identifier] else {
            fatalError("Missing parameter node named \(identifier)")
        }

        guard let subNode = node as? T else {
            fatalError("Parameter node named \(identifier) cannot be converted to the requested type")
        }

        return subNode
    }

    private func asParameter() -> ObservableAUParameter {
        guard let parameter = self as? ObservableAUParameter else {
            fatalError("Node is not a parameter")
        }

        return parameter
    }

    subscript(dynamicMember keyPath: ReferenceWritableKeyPath<ObservableAUParameter, Float>) -> Float {
        get { self.asParameter()[keyPath: keyPath] }
        set { self.asParameter()[keyPath: keyPath] = newValue }
    }
}

@MainActor
final class ObservableAUParameterGroup: ObservableAUParameterNode {
    private(set) var children: [String: ObservableAUParameterNode]

    init(_ parameterGroup: AUParameterGroup) {
        children = parameterGroup.children.reduce(into: [String: ObservableAUParameterNode]()) { dict, node in
            dict[node.identifier] = ObservableAUParameterNode.create(node)
        }
    }
}

@Observable
@MainActor
final class ObservableAUParameter: ObservableAUParameterNode {
    private weak var parameter: AUParameter?
    private var observerToken: AUParameterObserverToken!
    private var editingState: EditingState = .inactive

    let min: AUValue
    let max: AUValue
    let displayName: String
    let unit: AudioUnitParameterUnit
    var value: AUValue {
        didSet {
            guard editingState != .hostUpdate else {
                return
            }

            parameter?.setValue(
                value,
                originator: observerToken,
                atHostTime: 0,
                eventType: resolveEventType()
            )
        }
    }

    init(_ parameter: AUParameter) {
        self.parameter = parameter
        value = parameter.value
        min = parameter.minValue
        max = parameter.maxValue
        displayName = parameter.displayName
        unit = parameter.unit
        super.init()

        observerToken = parameter.token { [weak self] address, auValue in
            guard let self else {
                return
            }

            DispatchQueue.main.async {
                guard address == self.parameter?.address, self.editingState == .inactive else {
                    return
                }

                self.editingState = .hostUpdate
                self.value = auValue
                self.editingState = .inactive
            }
        }
    }

    func onEditingChanged(_ editing: Bool) {
        if editing {
            editingState = .began
        } else {
            editingState = .ended
            value = value
        }
    }

    private func resolveEventType() -> AUParameterAutomationEventType {
        switch editingState {
        case .began:
            editingState = .active
            return .touch
        case .ended:
            editingState = .inactive
            return .release
        default:
            return .value
        }
    }

    private enum EditingState {
        case inactive
        case began
        case active
        case ended
        case hostUpdate
    }
}

extension AUAudioUnit {
    @MainActor var observableParameterTree: ObservableAUParameterGroup? {
        guard let parameterTree else {
            return nil
        }

        return ObservableAUParameterGroup(parameterTree)
    }
}
