import SwiftUI

struct WashRackMainView: View {
    let parameterTree: ObservableAUParameterGroup

    var body: some View {
        ParameterSlider(parameter: parameterTree.outputGain)
    }
}
