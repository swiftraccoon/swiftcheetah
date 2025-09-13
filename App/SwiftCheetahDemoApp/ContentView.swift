import SwiftUI

struct ContentView: View {
    @StateObject private var periph = PeripheralManager()
    @State private var broadcasting = false

    var body: some View {
        Form {
            // Top bar
            HStack(spacing: 10) {
                TextField("Device name", text: $periph.localName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Toggle("Broadcasting", isOn: $broadcasting)
                    .toggleStyle(.switch)
                Circle()
                    .fill(periph.isAdvertising ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(periph.isAdvertising ? "Advertising" : "Idle")
                    .foregroundStyle(periph.isAdvertising ? .green : .secondary)
                Text("Subscribers: \(periph.subscriberCount)").foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .top, spacing: 16) {
                // Left column: Broadcast settings
                VStack(alignment: .leading, spacing: 8) {
                    Text("Services").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Toggle("FTMS", isOn: $periph.advertiseFTMS)
                            Toggle("CPS", isOn: $periph.advertiseCPS)
                            Toggle("RSC", isOn: $periph.advertiseRSC)
                        }
                    }

                    Text("FTMS Fields").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Toggle("Power", isOn: $periph.ftmsIncludePower)
                            Toggle("Cadence", isOn: $periph.ftmsIncludeCadence)
                        }
                    }

                    Text("CPS Fields").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Toggle("Power", isOn: $periph.cpsIncludePower)
                            Toggle("Cadence", isOn: $periph.cpsIncludeCadence)
                            Toggle("Speed", isOn: $periph.cpsIncludeSpeed)
                        }
                    }

                    DisclosureGroup("Events") {
                        ScrollView {
                            LazyVStack(alignment: .leading) {
                                ForEach(Array(periph.eventLog.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.caption).monospaced()
                                }
                            }
                        }
                        .frame(minHeight: 140)
                    }
                }
                .frame(maxWidth: 380, alignment: .leading)

                // Right column: Simulation controls
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("", selection: $periph.cadenceMode) {
                            Text("AUTO").tag(PeripheralManager.CadenceMode.auto)
                            Text("MANUAL").tag(PeripheralManager.CadenceMode.manual)
                        }
                        .pickerStyle(.segmented)
                        Text("Cadence Mode").foregroundStyle(.secondary)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        GridRow {
                            Text("Power")
                            Slider(value: Binding(get: { Double(periph.watts) }, set: { periph.watts = Int($0) }), in: 0...1000, step: 5)
                                .frame(width: 320)
                            Stepper(value: $periph.watts, in: 0...1000, step: periph.increment) { EmptyView() }
                            Text("\(periph.watts) W").frame(width: 80, alignment: .trailing).monospacedDigit()
                        }
                        GridRow {
                            Text("Cadence")
                            Slider(value: Binding(get: { Double(periph.cadenceRpm) }, set: { periph.cadenceRpm = Int($0) }), in: 0...200, step: 1)
                                .frame(width: 320)
                                .disabled(periph.cadenceMode == .auto)
                            Stepper(value: $periph.cadenceRpm, in: 0...200, step: 1) { EmptyView() }
                                .disabled(periph.cadenceMode == .auto)
                            Text("\(periph.cadenceRpm) rpm").frame(width: 80, alignment: .trailing).monospacedDigit()
                        }
                        GridRow {
                            Text("Randomness")
                            Slider(value: Binding(get: { Double(periph.randomness) }, set: { periph.randomness = Int($0) }), in: 0...100, step: 1)
                                .frame(width: 320)
                            Text("\(periph.randomness)").frame(width: 80, alignment: .trailing)
                        }
                        GridRow {
                            Text("Increment")
                            Slider(value: Binding(get: { Double(periph.increment) }, set: { periph.increment = Int($0) }), in: 1...100, step: 1)
                                .frame(width: 320)
                            EmptyView()
                            Text("\(periph.increment)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Stats").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow { Text("Mode"); Text(periph.cadenceMode == .auto ? "AUTO" : "MANUAL") }
                        GridRow { Text("Speed"); Text(String(format: "%.1f km/h", periph.stats.speedKmh)).monospacedDigit() }
                        GridRow { Text("Power"); Text("\(periph.stats.powerW) W").monospacedDigit() }
                        GridRow { Text("Cadence"); Text("\(periph.stats.cadenceRpm) rpm").monospacedDigit() }
                        GridRow { Text("Target"); Text("\(periph.stats.targetCadence) rpm").monospacedDigit() }
                        GridRow { Text("Gear"); Text(periph.stats.gear) }
                        GridRow { Text("Fatigue"); Text(String(format: "%.2f", periph.stats.fatigue)).monospacedDigit() }
                        GridRow { Text("Noise"); Text(String(format: "%.2f", periph.stats.noise)).monospacedDigit() }
                        GridRow { Text("Grade"); Text(String(format: "%.1f %%", periph.stats.gradePercent)) }
                    }
                }
                .frame(maxWidth: 260, alignment: .leading)
            }
        }
        .padding(10)
        .frame(minWidth: 800, minHeight: 520)
        .onChange(of: broadcasting) { _, on in
            if on && !periph.isAdvertising { periph.startBroadcast() }
            else if !on && periph.isAdvertising { periph.stopBroadcast() }
        }
        .onChange(of: periph.isAdvertising) { _, isOn in
            broadcasting = isOn
        }
    }
}

private func formattedSpeed(_ speedMps: Double?) -> String {
    guard let s = speedMps else { return "--" }
    let kph = s * 3.6
    return String(format: "%.1f km/h", kph)
}

private func formattedCadence(_ rpm: Double?) -> String {
    guard let c = rpm else { return "--" }
    return String(format: "%.0f rpm", c)
}

private func formattedPower(_ watts: Int?) -> String {
    guard let w = watts else { return "--" }
    return "\(w) W"
}

private struct MetricView: View {
    var title: String
    var value: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
        .frame(width: 120, alignment: .leading)
    }
}
#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
