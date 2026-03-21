import SwiftUI

// MARK: - Broadcast Mode

enum BroadcastMode: String, CaseIterable {
    case ble = "BLE"
    case dircon = "DIRCON"
}

// MARK: - Protocol abstracting PeripheralManager / DIRCONServer

/// Subset of stats fields the UI cards need.
protocol BroadcastServerStats {
    var speedKmh: Double { get }
    var powerW: Int { get }
    var cadenceRpm: Int { get }
    var gear: String { get }
    var gradePercent: Double { get }
}

/// Shared interface for both BLE and DIRCON broadcast servers.
@MainActor
protocol BroadcastServer: ObservableObject {
    associatedtype Stats: BroadcastServerStats

    // Read-only status
    var isAdvertising: Bool { get }
    var subscriberCount: Int { get }
    var eventLog: [String] { get }
    var stats: Stats { get }

    // Simulation inputs
    var watts: Int { get set }
    var cadenceRpm: Int { get set }
    var gradePercent: Double { get set }
    var randomness: Int { get set }
    var increment: Int { get set }

    // Service toggles
    var advertiseFTMS: Bool { get set }
    var advertiseCPS: Bool { get set }
    var advertiseRSC: Bool { get set }

    // Field toggles
    var ftmsIncludePower: Bool { get set }
    var ftmsIncludeCadence: Bool { get set }
    var cpsIncludePower: Bool { get set }
    var cpsIncludeCadence: Bool { get set }
    var cpsIncludeSpeed: Bool { get set }

    // Device name
    var localName: String { get set }

    // Cadence mode abstraction (avoids needing the nested enum type)
    var cadenceModeIsAuto: Bool { get set }

    // Lifecycle
    func startBroadcast()
    func stopBroadcast()
}

// MARK: - PeripheralManager conformance

extension PeripheralManager.LiveStats: BroadcastServerStats {}

extension PeripheralManager: BroadcastServer {
    var cadenceModeIsAuto: Bool {
        get { cadenceMode == .auto }
        set { cadenceMode = newValue ? .auto : .manual }
    }
    func startBroadcast() { startBroadcast(localName: nil, options: nil) }
}

// MARK: - DIRCONServer conformance

extension DIRCONServer.LiveStats: BroadcastServerStats {}

extension DIRCONServer: BroadcastServer {
    var cadenceModeIsAuto: Bool {
        get { cadenceMode == .auto }
        set { cadenceMode = newValue ? .auto : .manual }
    }
    func startBroadcast() { startBroadcast(localName: nil) }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var periph = PeripheralManager()
    @StateObject private var dircon = DIRCONServer()
    @State private var broadcasting = false
    @State private var broadcastMode: BroadcastMode = .dircon
    @State private var showEventLog = false

    var body: some View {
        VStack(spacing: 0) {
            // Status bar — reads from the active server
            BroadcastStatusBar(
                isAdvertising: activeIsAdvertising,
                broadcasting: $broadcasting,
                deviceName: activeDeviceNameBinding,
                subscriberCount: activeSubscriberCount,
                broadcastMode: $broadcastMode
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            ScrollView {
                VStack(spacing: 20) {
                    if broadcastMode == .ble {
                        serverCards(server: periph)
                    } else {
                        serverCards(server: dircon)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 720, minHeight: 600)
        .background(Color(.windowBackgroundColor))
        .onChange(of: broadcasting) { _, on in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if broadcastMode == .ble {
                    if on && !periph.isAdvertising { periph.startBroadcast() }
                    else if !on && periph.isAdvertising { periph.stopBroadcast() }
                } else {
                    if on && !dircon.isAdvertising { dircon.startBroadcast() }
                    else if !on && dircon.isAdvertising { dircon.stopBroadcast() }
                }
            }
        }
        .onChange(of: periph.isAdvertising) { _, isOn in
            if broadcastMode == .ble { broadcasting = isOn }
        }
        .onChange(of: dircon.isAdvertising) { _, isOn in
            if broadcastMode == .dircon { broadcasting = isOn }
        }
        .onChange(of: broadcastMode) { oldMode, newMode in
            // Stop previous server if broadcasting, then sync state
            if broadcasting {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if oldMode == .ble { periph.stopBroadcast() }
                    else { dircon.stopBroadcast() }
                    broadcasting = false
                }
            }
        }
    }

    // MARK: - Active server helpers

    private var activeIsAdvertising: Bool {
        broadcastMode == .ble ? periph.isAdvertising : dircon.isAdvertising
    }

    private var activeSubscriberCount: Int {
        broadcastMode == .ble ? periph.subscriberCount : dircon.subscriberCount
    }

    private var activeDeviceNameBinding: Binding<String> {
        broadcastMode == .ble
            ? $periph.localName
            : $dircon.localName
    }

    // MARK: - Generic card layout

    @ViewBuilder
    private func serverCards<S: BroadcastServer>(server: S) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                BroadcastSettingsCard(server: server)
                SimulationControlsCard(server: server)
            }
            .frame(maxWidth: .infinity)

            LiveMetricsCard(server: server)
                .frame(width: 320)
        }
        .padding(.horizontal, 20)

        PerformanceGraphCard(server: server)
            .padding(.horizontal, 20)

        ActivityFeedCard(
            eventLog: server.eventLog,
            isExpanded: $showEventLog
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - BroadcastStatusBar

struct BroadcastStatusBar: View {
    let isAdvertising: Bool
    @Binding var broadcasting: Bool
    @Binding var deviceName: String
    let subscriberCount: Int
    @Binding var broadcastMode: BroadcastMode

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

            // Mode picker
            Picker("Mode", selection: $broadcastMode) {
                ForEach(BroadcastMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
            .disabled(broadcasting)

            Divider()
                .frame(height: 24)

            HStack(spacing: 8) {
                Image(systemName: broadcastMode == .ble ? "antenna.radiowaves.left.and.right" : "wifi.router")
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

// MARK: - BroadcastSettingsCard

struct BroadcastSettingsCard<S: BroadcastServer>: View {
    @ObservedObject var server: S

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
                        isOn: $server.advertiseFTMS
                    )
                    ServiceToggle(
                        title: "CPS",
                        icon: "bicycle",
                        isOn: $server.advertiseCPS
                    )
                    ServiceToggle(
                        title: "RSC",
                        icon: "figure.run",
                        isOn: $server.advertiseRSC
                    )
                }
            }

            if server.advertiseFTMS {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("FTMS Fields")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        FieldToggle(title: "Power", isOn: $server.ftmsIncludePower)
                        FieldToggle(title: "Cadence", isOn: $server.ftmsIncludeCadence)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if server.advertiseCPS {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("CPS Fields")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        FieldToggle(title: "Power", isOn: $server.cpsIncludePower)
                        FieldToggle(title: "Cadence", isOn: $server.cpsIncludeCadence)
                        FieldToggle(title: "Speed", isOn: $server.cpsIncludeSpeed)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

// MARK: - SimulationControlsCard

struct SimulationControlsCard<S: BroadcastServer>: View {
    @ObservedObject var server: S

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Simulation Controls", systemImage: "slider.horizontal.3")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.primary)

            Picker("Mode", selection: Binding(
                get: { server.cadenceModeIsAuto },
                set: { server.cadenceModeIsAuto = $0 }
            )) {
                Label("Auto", systemImage: "wand.and.stars")
                    .tag(true)
                Label("Manual", systemImage: "hand.draw")
                    .tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 16) {
                MetricSlider(
                    title: "Power",
                    value: Binding(
                        get: { Double(server.watts) },
                        set: { server.watts = Int($0) }
                    ),
                    range: 0...1000,
                    step: Double(server.increment),
                    unit: "W",
                    icon: "bolt.fill",
                    color: powerZoneColor(for: server.watts)
                )

                MetricSlider(
                    title: "Cadence",
                    value: Binding(
                        get: { Double(server.cadenceRpm) },
                        set: { server.cadenceRpm = Int($0) }
                    ),
                    range: 0...200,
                    step: 1,
                    unit: "rpm",
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue,
                    disabled: server.cadenceModeIsAuto
                )

                MetricSlider(
                    title: "Variance",
                    value: Binding(
                        get: { Double(server.randomness) },
                        set: { server.randomness = Int($0) }
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
                        get: { Double(server.increment) },
                        set: { server.increment = Int($0) }
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
        .padding(16)
        .frame(width: 320, alignment: .leading)
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

// MARK: - LiveMetricsCard

struct LiveMetricsCard<S: BroadcastServer>: View {
    @ObservedObject var server: S
    @State private var totalPower: Double = 0
    @State private var totalCadence: Double = 0
    @State private var totalSpeed: Double = 0
    @State private var sampleCount: Int = 0
    @State private var distance: Double = 0
    @State private var elapsedTime: TimeInterval = 0
    @State private var startTime = Date()
    private let ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Live Metrics", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 16) {
                MetricRow(
                    icon: "speedometer",
                    title: "Speed",
                    value: String(format: "%.1f", server.stats.speedKmh),
                    unit: "km/h",
                    color: .green
                )

                MetricRow(
                    icon: "bolt.fill",
                    title: "Power",
                    value: "\(server.stats.powerW)",
                    unit: "W",
                    color: powerColor(for: server.stats.powerW)
                )

                MetricRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Cadence",
                    value: "\(server.stats.cadenceRpm)",
                    unit: "rpm",
                    color: .blue
                )

                Divider()

                // Averages Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Averages")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        CompactMetric(
                            icon: "avg.circle",
                            value: String(format: "%.0f W", sampleCount > 0 ? totalPower / Double(sampleCount) : 0),
                            label: "Avg Power"
                        )
                        CompactMetric(
                            icon: "avg.circle",
                            value: String(format: "%.0f rpm", sampleCount > 0 ? totalCadence / Double(sampleCount) : 0),
                            label: "Avg Cadence"
                        )
                    }

                    HStack(spacing: 20) {
                        CompactMetric(
                            icon: "avg.circle",
                            value: String(format: "%.1f km/h", sampleCount > 0 ? totalSpeed / Double(sampleCount) : 0),
                            label: "Avg Speed"
                        )
                        CompactMetric(
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            value: String(format: "%.2f km", distance),
                            label: "Distance"
                        )
                    }
                }

                Divider()

                // Additional Info
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Gear", systemImage: "gearshape.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(server.stats.gear)
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Grade", systemImage: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", server.stats.gradePercent))
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Time", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatTime(elapsedTime))
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                    }
                }

                // Power Zone Distribution
                PowerZoneBar(currentPower: server.stats.powerW)

                // Extra spacing to match Simulation Controls height
                Spacer()
                    .frame(height: 20)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .onAppear {
            startTime = Date()
            totalPower = 0
            totalCadence = 0
            totalSpeed = 0
            sampleCount = 0
            distance = 0
        }
        .onReceive(ticker) { _ in
            updateAverages()
        }
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

    func updateAverages() {
        elapsedTime = Date().timeIntervalSince(startTime)

        // Accumulate totals for true average calculation
        totalPower += Double(server.stats.powerW)
        totalCadence += Double(server.stats.cadenceRpm)
        totalSpeed += server.stats.speedKmh
        sampleCount += 1

        // Update distance based on current speed (km/h converted to km/s)
        distance += (server.stats.speedKmh / 3600.0)
    }

    func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - CompactMetric

struct CompactMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(minWidth: 80, alignment: .leading)
    }
}

// MARK: - PerformanceGraphCard

struct PerformanceGraphCard<S: BroadcastServer>: View {
    @ObservedObject var server: S
    @State private var powerHistory: [Double] = Array(repeating: 0, count: 600)  // 10 minutes at 1 sample/sec
    @State private var cadenceHistory: [Double] = Array(repeating: 0, count: 600)
    @State private var speedHistory: [Double] = Array(repeating: 0, count: 600)
    @State private var selectedMetric = 0 // 0: Power, 1: Cadence, 2: Speed
    @State private var updateTrigger = false
    private let ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Performance", systemImage: "chart.xyaxis.line")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Picker("Metric", selection: $selectedMetric) {
                    Text("Power").tag(0)
                    Text("Cadence").tag(1)
                    Text("Speed").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Y-axis labels
                VStack(alignment: .trailing, spacing: 0) {
                    Text(yAxisMaxLabel())
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(yAxisMidLabel())
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("0")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 30, height: 120)

                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack {
                            // Grid lines
                            Path { path in
                                let height = geometry.size.height
                                let width = geometry.size.width

                                // Horizontal grid lines
                                for i in 0...4 {
                                    let y = height * CGFloat(i) / 4
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: width, y: y))
                                }

                                // Vertical grid lines
                                for i in 0...5 {
                                    let x = width * CGFloat(i) / 5
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: height))
                                }
                            }
                            .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 0.5)

                    // Data line
                    Path { path in
                        let data = selectedData()
                        let maxValue = maxValueForMetric()
                        let height = geometry.size.height
                        let width = geometry.size.width

                        // Force update trigger to be used
                        _ = updateTrigger

                        guard !data.isEmpty, maxValue > 0 else { return }

                        // Plot all points to preserve historical accuracy
                        let step = 1
                        var isFirst = true

                        for index in stride(from: 0, to: data.count, by: step) {
                            let value = data[index]
                            let x = width * CGFloat(index) / CGFloat(max(1, data.count - 1))
                            let y = height - (height * CGFloat(value) / maxValue)

                            if isFirst {
                                path.move(to: CGPoint(x: x, y: y))
                                isFirst = false
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(lineColor(), lineWidth: 2)

                    // Fill gradient
                    Path { path in
                        let data = selectedData()
                        let maxValue = maxValueForMetric()
                        let height = geometry.size.height
                        let width = geometry.size.width

                        // Force update trigger to be used
                        _ = updateTrigger

                        guard !data.isEmpty, maxValue > 0 else { return }

                        path.move(to: CGPoint(x: 0, y: height))

                        // Plot all points to preserve historical accuracy
                        let step = 1

                        for index in stride(from: 0, to: data.count, by: step) {
                            let value = data[index]
                            let x = width * CGFloat(index) / CGFloat(max(1, data.count - 1))
                            let y = height - (height * CGFloat(value) / maxValue)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }

                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [lineColor().opacity(0.3), lineColor().opacity(0)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                }
                .frame(height: 120)

                // X-axis labels
                HStack {
                    Text("-10m")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("-5m")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Now")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 4)
                }
            }

            HStack {
                Text(metricLabel())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(currentValueText())
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .foregroundStyle(lineColor())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .onReceive(ticker) { _ in
            updateHistory()
        }
    }

    func updateHistory() {
        // Remove oldest value and add new one
        powerHistory.removeFirst()
        powerHistory.append(Double(server.stats.powerW))

        cadenceHistory.removeFirst()
        cadenceHistory.append(Double(server.stats.cadenceRpm))

        speedHistory.removeFirst()
        speedHistory.append(server.stats.speedKmh)

        // Toggle to force UI update
        updateTrigger.toggle()
    }

    func selectedData() -> [Double] {
        switch selectedMetric {
        case 0: return powerHistory
        case 1: return cadenceHistory
        case 2: return speedHistory
        default: return powerHistory
        }
    }

    func maxValueForMetric() -> Double {
        switch selectedMetric {
        case 0: return 500  // Fixed scale for power (watts)
        case 1: return 150  // Fixed scale for cadence (rpm)
        case 2: return 60   // Fixed scale for speed (km/h)
        default: return 100
        }
    }

    func lineColor() -> Color {
        switch selectedMetric {
        case 0: return .orange
        case 1: return .blue
        case 2: return .green
        default: return .orange
        }
    }

    func currentValueText() -> String {
        switch selectedMetric {
        case 0: return "\(server.stats.powerW) W"
        case 1: return "\(server.stats.cadenceRpm) rpm"
        case 2: return String(format: "%.1f km/h", server.stats.speedKmh)
        default: return ""
        }
    }

    func yAxisMaxLabel() -> String {
        let max = maxValueForMetric()
        switch selectedMetric {
        case 0: return "\(Int(max))W"
        case 1: return "\(Int(max))"
        case 2: return "\(Int(max))"
        default: return ""
        }
    }

    func yAxisMidLabel() -> String {
        let max = maxValueForMetric()
        switch selectedMetric {
        case 0: return "\(Int(max/2))W"
        case 1: return "\(Int(max/2))"
        case 2: return "\(Int(max/2))"
        default: return ""
        }
    }

    func metricLabel() -> String {
        switch selectedMetric {
        case 0: return "Power (Watts)"
        case 1: return "Cadence (RPM)"
        case 2: return "Speed (km/h)"
        default: return ""
        }
    }
}

// MARK: - PowerZoneBar

struct PowerZoneBar: View {
    let currentPower: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Power Zones")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(0..<5) { zone in
                        Rectangle()
                            .fill(zoneColor(zone).opacity(currentPower > zoneThreshold(zone) ? 1 : 0.2))
                            .frame(width: geometry.size.width / 5)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 0: return .blue
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        default: return .red
        }
    }

    func zoneThreshold(_ zone: Int) -> Int {
        switch zone {
        case 0: return 0
        case 1: return 150
        case 2: return 200
        case 3: return 250
        default: return 300
        }
    }
}

// MARK: - ActivityFeedCard

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

                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                }, label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                })
                .buttonStyle(.plain)
            }

            if isExpanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(eventLog.enumerated()), id: \.offset) { index, line in
                                HStack(spacing: 8) {
                                    Image(systemName: eventIcon(for: line))
                                        .font(.system(size: 10))
                                        .foregroundStyle(eventColor(for: line))
                                        .frame(width: 16)

                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }
                                .id(index)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: eventLog.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(eventLog.count - 1, anchor: .bottom)
                        }
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

// MARK: - ServiceToggle

struct ServiceToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2)) {
                isOn.toggle()
            }
        }, label: {
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
        })
        .buttonStyle(.plain)
    }
}

// MARK: - FieldToggle

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

// MARK: - MetricSlider

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
                        Button(action: { value = max(range.lowerBound, value - step) }, label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .medium))
                        })
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(disabled || value <= range.lowerBound)

                        Button(action: { value = min(range.upperBound, value + step) }, label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                        })
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

// MARK: - MetricRow

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

// MARK: - ProgressBar

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
