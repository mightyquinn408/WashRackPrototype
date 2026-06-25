import AudioToolbox
import Foundation
import SwiftUI

struct ParameterSlider: View {
    @Bindable var parameter: ObservableAUParameter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(parameter.displayName)
                Spacer()
                Text(valueLabel)
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Slider(
                value: $parameter.value,
                in: parameter.min ... parameter.max,
                onEditingChanged: parameter.onEditingChanged,
                minimumValueLabel: Text(minimumValueLabel),
                maximumValueLabel: Text(maximumValueLabel)
            ) {
                Text(parameter.displayName)
            }
            .animation(.linear(duration: 1.0 / 30.0), value: parameter.value)
            .accessibility(identifier: parameter.displayName)
        }
    }

    private var valueLabel: String {
        switch parameter.unit {
        case .decibels:
            String(format: "%.1f dB", parameter.value)
        case .percent:
            String(format: "%.0f %%", parameter.value)
        case .hertz:
            String(format: "%.0f Hz", parameter.value)
        default:
            String(format: "%.2f", parameter.value)
        }
    }

    private var minimumValueLabel: String {
        label(for: parameter.min)
    }

    private var maximumValueLabel: String {
        label(for: parameter.max)
    }

    private func label(for value: AUValue) -> String {
        switch parameter.unit {
        case .decibels:
            String(format: "%.0f dB", value)
        case .percent:
            String(format: "%.0f %%", value)
        case .hertz:
            String(format: "%.0f Hz", value)
        default:
            String(format: "%.2f", value)
        }
    }
}

struct ParameterToggle: View {
    @Bindable var parameter: ObservableAUParameter

    var body: some View {
        Toggle(isOn: toggleBinding) {
            HStack {
                Text(parameter.displayName)
                Spacer()
                Text(parameter.value >= 0.5 ? "On" : "Off")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .accessibility(identifier: parameter.displayName)
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { parameter.value >= 0.5 },
            set: { newValue in
                parameter.onEditingChanged(true)
                parameter.value = newValue ? 1 : 0
                parameter.onEditingChanged(false)
            }
        )
    }
}
