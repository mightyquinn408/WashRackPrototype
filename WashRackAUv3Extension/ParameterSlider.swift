import SwiftUI

struct ParameterSlider: View {
    @Bindable var parameter: ObservableAUParameter

    private var specifier: String {
        "%.2f"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WashRack")
                .font(.headline)

            Slider(
                value: $parameter.value,
                in: parameter.min ... parameter.max,
                onEditingChanged: parameter.onEditingChanged,
                minimumValueLabel: Text("\(parameter.min, specifier: specifier) dB"),
                maximumValueLabel: Text("\(parameter.max, specifier: specifier) dB")
            ) {
                Text(parameter.displayName)
            }
            .accessibility(identifier: parameter.displayName)

            HStack {
                Text(parameter.displayName)
                Spacer()
                Text("\(parameter.value, specifier: specifier) dB")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 120)
    }
}
