import AVFoundation

enum WashRackParameterTreeFactory {
    nonisolated static func makeParameterTree() -> AUParameterTree {
        let parameters = WashRackParameterSpec.all.map(makeParameter)
        return AUParameterTree.createTree(withChildren: parameters)
    }

    nonisolated private static func makeParameter(from spec: WashRackParameterSpec) -> AUParameter {
        let parameter = AUParameterTree.createParameter(
            withIdentifier: spec.identifier,
            name: spec.name,
            address: spec.address.rawValue,
            min: spec.minValue,
            max: spec.maxValue,
            unit: spec.unit,
            unitName: nil,
            flags: spec.flags,
            valueStrings: nil,
            dependentParameters: nil
        )
        parameter.value = spec.defaultValue
        return parameter
    }
}
