import SwiftUI

struct ContentView: View {
    @StateObject private var periph = PeripheralManager()
    @State private var broadcasting = false
    @State private var showEventLog = false

    var body: some View {
        VStack(spacing: 0) {
            BroadcastStatusBar(
                isAdvertising: periph.isAdvertising,
                broadcasting: $broadcasting,
                deviceName: $periph.localName,
                subscriberCount: periph.subscriberCount
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            ScrollView {
                VStack(spacing: 20) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) {
                            BroadcastSettingsCard(periph: periph)
                            SimulationControlsCard(periph: periph)
                        }
                        .frame(maxWidth: .infinity)

                        LiveMetricsCard(stats: periph.stats)
                            .frame(width: 320)
                    }
                    .padding(.horizontal, 20)

                    ActivityFeedCard(
                        eventLog: periph.eventLog,
                        isExpanded: $showEventLog
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(.windowBackgroundColor))
        .onChange(of: broadcasting) { _, on in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if on && !periph.isAdvertising {
                    periph.startBroadcast()
                } else if !on && periph.isAdvertising {
                    periph.stopBroadcast()
                }
            }
        }
        .onChange(of: periph.isAdvertising) { _, isOn in
            broadcasting = isOn
        }
    }
}

struct BroadcastStatusBar: View {
    let isAdvertising: Bool
    @Binding var broadcasting: Bool
    @Binding var deviceName: String
    let subscriberCount: Int

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isAdvertising ? Color.green : Color(.tertiaryLabelColor))
                        .frame(width: 10, height: 10)

                    if isAdvertising {
                        Circle()
                            .stroke(Color.green, lineWidth: 2)
                            .frame(width: 10, height: 10)
                            .scaleEffect(isAdvertising ? 2.5 : 1)
                            .opacity(isAdvertising ? 0 : 1)
                            .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: isAdvertising)
                    }
                }

                Text(isAdvertising ? "Broadcasting" : "Idle")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(isAdvertising ? .primary : .secondary)
                    .contentTransition(.numericText())
            }

            Divider()
                .frame(height: 24)

            HStack(spacing: 8) {
                Image(systemName: "wifi.router")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Device Name", text: $deviceName)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .default, weight: .medium))
                    .frame(width: 200)
            }

            Spacer()

            if subscriberCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("\(subscriberCount)")
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Toggle(isOn: $broadcasting) {
                Text(broadcasting ? "Stop" : "Start")
                    .font(.system(.callout, weight: .medium))
            }
            .toggleStyle(.button)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

struct BroadcastSettingsCard: View {
    @ObservedObject var periph: PeripheralManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Broadcast Settings", systemImage: "antenna.radiowaves.left.and.right")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Services")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ServiceToggle(
                        title: "FTMS",
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        isOn: $periph.advertiseFTMS
                    )
                    ServiceToggle(
                        title: "CPS",
                        icon: "bicycle",
                        isOn: $periph.advertiseCPS
                    )
                    ServiceToggle(
                        title: "RSC",
                        icon: "figure.run",
                        isOn: $periph.advertiseRSC
                    )
                }
            }

            if periph.advertiseFTMS {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("FTMS Fields")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        FieldToggle(title: "Power", isOn: $periph.ftmsIncludePower)
                        FieldToggle(title: "Cadence", isOn: $periph.ftmsIncludeCadence)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if periph.advertiseCPS {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("CPS Fields")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        FieldToggle(title: "Power", isOn: $periph.cpsIncludePower)
                        FieldToggle(title: "Cadence", isOn: $periph.cpsIncludeCadence)
                        FieldToggle(title: "Speed", isOn: $periph.cpsIncludeSpeed)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

struct SimulationControlsCard: View {
    @ObservedObject var periph: PeripheralManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Simulation Controls", systemImage: "slider.horizontal.3")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.primary)

            Picker("Mode", selection: $periph.cadenceMode) {
                Label("Auto", systemImage: "wand.and.stars")
                    .tag(PeripheralManager.CadenceMode.auto)
                Label("Manual", systemImage: "hand.draw")
                    .tag(PeripheralManager.CadenceMode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 16) {
                MetricSlider(
                    title: "Power",
                    value: Binding(
                        get: { Double(periph.watts) },
                        set: { periph.watts = Int($0) }
                    ),
                    range: 0...1000,
                    step: Double(periph.increment),
                    unit: "W",
                    icon: "bolt.fill",
                    color: powerZoneColor(for: periph.watts)
                )

                MetricSlider(
                    title: "Cadence",
                    value: Binding(
                        get: { Double(periph.cadenceRpm) },
                        set: { periph.cadenceRpm = Int($0) }
                    ),
                    range: 0...200,
                    step: 1,
                    unit: "rpm",
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue,
                    disabled: periph.cadenceMode == .auto
                )

                MetricSlider(
                    title: "Variance",
                    value: Binding(
                        get: { Double(periph.randomness) },
                        set: { periph.randomness = Int($0) }
                    ),
                    range: 0...100,
                    step: 1,
                    unit: "%",
                    icon: "waveform.path.ecg",
                    color: .orange,
                    showStepper: false
                )

                MetricSlider(
                    title: "Increment",
                    value: Binding(
                        get: { Double(periph.increment) },
                        set: { periph.increment = Int($0) }
                    ),
                    range: 1...100,
                    step: 1,
                    unit: "W",
                    icon: "plus.forwardslash.minus",
                    color: .purple,
                    showStepper: false
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    func powerZoneColor(for watts: Int) -> Color {
        switch watts {
        case 0..<150: return .blue
        case 150..<200: return .green
        case 200..<250: return .yellow
        case 250..<300: return .orange
        default: return .red
        }
    }
}

struct LiveMetricsCard: View {
    let stats: PeripheralManager.LiveStats

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Live Metrics", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 16) {
                MetricRow(
                    icon: "speedometer",
                    title: "Speed",
                    value: String(format: "%.1f", stats.speedKmh),
                    unit: "km/h",
                    color: .green
                )

                MetricRow(
                    icon: "bolt.fill",
                    title: "Power",
                    value: "\(stats.powerW)",
                    unit: "W",
                    color: powerColor(for: stats.powerW)
                )

                MetricRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Cadence",
                    value: "\(stats.cadenceRpm)",
                    unit: "rpm",
                    color: .blue
                )

                Divider()

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Gear", systemImage: "gearshape.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(stats.gear)
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Grade", systemImage: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", stats.gradePercent))
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    func powerColor(for watts: Int) -> Color {
        switch watts {
        case 0..<150: return .blue
        case 150..<200: return .green
        case 200..<250: return .yellow
        case 250..<300: return .orange
        default: return .red
        }
    }
}

struct ActivityFeedCard: View {
    let eventLog: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity", systemImage: "list.bullet.rectangle")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(eventLog.enumerated()), id: \.offset) { _, line in
                            HStack(spacing: 8) {
                                Image(systemName: eventIcon(for: line))
                                    .font(.system(size: 10))
                                    .foregroundStyle(eventColor(for: line))
                                    .frame(width: 16)

                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    func eventIcon(for line: String) -> String {
        if line.contains("connected") { return "link" }
        if line.contains("disconnected") { return "link.badge.minus" }
        if line.contains("Control") { return "command" }
        if line.contains("Power") { return "bolt" }
        return "circle.fill"
    }

    func eventColor(for line: String) -> Color {
        if line.contains("connected") { return .green }
        if line.contains("disconnected") { return .red }
        if line.contains("Control") { return .blue }
        if line.contains("Power") { return .orange }
        return .secondary
    }
}

struct ServiceToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.2)) { isOn.toggle() } }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .symbolVariant(isOn ? .fill : .none)
                    .foregroundStyle(isOn ? .white : .secondary)

                Text(title)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(isOn ? .white : .secondary)
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? Color.accentColor : Color(.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

struct FieldToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(.callout))
        }
        .toggleStyle(.checkbox)
    }
}

struct MetricSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let icon: String
    let color: Color
    var disabled: Bool = false
    var showStepper: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(disabled ? .secondary : .primary)

                Spacer()

                Text("\(Int(value)) \(unit)")
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .foregroundStyle(disabled ? .secondary : color)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 12) {
                Slider(value: $value, in: range, step: step)
                    .tint(color)
                    .disabled(disabled)

                if showStepper {
                    HStack(spacing: 2) {
                        Button(action: { value = max(range.lowerBound, value - step) }) {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(disabled || value <= range.lowerBound)

                        Button(action: { value = min(range.upperBound, value + step) }) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(disabled || value >= range.upperBound)
                    }
                }
            }
        }
        .opacity(disabled ? 0.6 : 1.0)
    }
}

struct MetricRow: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Text(unit)
                        .font(.system(.callout))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ProgressBar(value: progressValue(for: value, unit: unit), color: color)
                .frame(width: 60, height: 6)
        }
    }

    func progressValue(for value: String, unit: String) -> Double {
        guard let numericValue = Double(value.replacingOccurrences(of: ",", with: ".")) else { return 0 }

        switch unit {
        case "km/h": return min(numericValue / 60.0, 1.0)
        case "W": return min(numericValue / 500.0, 1.0)
        case "rpm": return min(numericValue / 200.0, 1.0)
        default: return 0
        }
    }
}

struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(.separatorColor))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: geometry.size.width * value)
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif