import SwiftUI

struct WashRackMainView: View {
    let parameterTree: ObservableAUParameterGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("WashRack")
                    .font(.headline)

                ParameterToggle(parameter: parameterTree.effectEnabled)
                ParameterSlider(parameter: parameterTree.dryWetMix)
                ParameterSlider(parameter: parameterTree.outputGain)
            }
            .padding(20)
        }
        .frame(minWidth: 360, minHeight: 220)
    }
}
