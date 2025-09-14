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

                        LiveMetricsCard(periph: periph)
                            .frame(width: 320)
                    }
                    .padding(.horizontal, 20)

                    PerformanceGraphCard(periph: periph)
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
        .frame(minWidth: 720, minHeight: 600)
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
        .padding(16)
        .frame(width: 320, alignment: .leading)
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

struct LiveMetricsCard: View {
    @ObservedObject var periph: PeripheralManager
    @State private var totalPower: Double = 0
    @State private var totalCadence: Double = 0
    @State private var totalSpeed: Double = 0
    @State private var sampleCount: Int = 0
    @State private var distance: Double = 0
    @State private var elapsedTime: TimeInterval = 0
    @State private var startTime = Date()
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Live Metrics", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 16) {
                MetricRow(
                    icon: "speedometer",
                    title: "Speed",
                    value: String(format: "%.1f", periph.stats.speedKmh),
                    unit: "km/h",
                    color: .green
                )

                MetricRow(
                    icon: "bolt.fill",
                    title: "Power",
                    value: "\(periph.stats.powerW)",
                    unit: "W",
                    color: powerColor(for: periph.stats.powerW)
                )

                MetricRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Cadence",
                    value: "\(periph.stats.cadenceRpm)",
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
                        Text(periph.stats.gear)
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Grade", systemImage: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", periph.stats.gradePercent))
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
                PowerZoneBar(currentPower: periph.stats.powerW)

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
            // Reset totals when view appears
            totalPower = 0
            totalCadence = 0
            totalSpeed = 0
            sampleCount = 0
            distance = 0

            // Start timer to update averages
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    updateAverages()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
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
        totalPower += Double(periph.stats.powerW)
        totalCadence += Double(periph.stats.cadenceRpm)
        totalSpeed += periph.stats.speedKmh
        sampleCount += 1

        // Update distance based on current speed (km/h converted to km/s)
        distance += (periph.stats.speedKmh / 3600.0)
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

struct CompactMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 80, alignment: .leading)
    }
}

struct PerformanceGraphCard: View {
    @ObservedObject var periph: PeripheralManager
    @State private var powerHistory: [Double] = Array(repeating: 0, count: 600)  // 10 minutes at 1 sample/sec
    @State private var cadenceHistory: [Double] = Array(repeating: 0, count: 600)
    @State private var speedHistory: [Double] = Array(repeating: 0, count: 600)
    @State private var selectedMetric = 0 // 0: Power, 1: Cadence, 2: Speed
    @State private var timer: Timer?
    @State private var updateTrigger = false

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

                        // Downsample for performance - show every 5th point
                        let step = max(1, data.count / 120)  // Show ~120 points max

                        for index in stride(from: 0, to: data.count, by: step) {
                            let value = data[index]
                            let x = width * CGFloat(index) / CGFloat(max(1, data.count - 1))
                            let y = height - (height * CGFloat(value) / maxValue)

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
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

                        // Downsample for performance
                        let step = max(1, data.count / 120)

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
        .onAppear {
            // Start timer to update graph
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    updateHistory()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    func updateHistory() {
        // Remove oldest value and add new one
        powerHistory.removeFirst()
        powerHistory.append(Double(periph.stats.powerW))

        cadenceHistory.removeFirst()
        cadenceHistory.append(Double(periph.stats.cadenceRpm))

        speedHistory.removeFirst()
        speedHistory.append(periph.stats.speedKmh)

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
        case 0: return max(500, powerHistory.max() ?? 500)
        case 1: return max(150, cadenceHistory.max() ?? 150)
        case 2: return max(60, speedHistory.max() ?? 60)
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
        case 0: return "\(periph.stats.powerW) W"
        case 1: return "\(periph.stats.cadenceRpm) rpm"
        case 2: return String(format: "%.1f km/h", periph.stats.speedKmh)
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
