import AppKit

@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let panel = MetricsPanelView(frame: NSRect(x: 0, y: 0, width: 330, height: 246))
    private let sampler = SystemMetricsSampler()
    private var timer: Timer?

    override init() {
        super.init()
        configureStatusItem()
        configureMenu()
        sampler.primeCPU()
        update()

        let timer = Timer(
            timeInterval: 3,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "System stats")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        button.toolTip = "FeatherStats"
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        let panelItem = NSMenuItem()
        panelItem.view = panel
        panelItem.isEnabled = true
        menu.addItem(panelItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = true
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "Quit FeatherStats", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { update() }

    @objc private func refreshNow() { update() }

    @objc private func timerFired() { update() }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    private func update() {
        let snapshot = sampler.sample()
        panel.render(snapshot)
        guard let button = statusItem.button else { return }

        let cpu = snapshot.cpuUsage.map { "\(Int($0.rounded()))%" } ?? "…"
        let memory = Self.shortBytes(snapshot.memoryUsed)
        button.title = " \(cpu)  \(memory)"
        button.setAccessibilityLabel("CPU \(cpu), memory \(memory) used")
    }

    private static func shortBytes(_ bytes: UInt64) -> String {
        String(format: "%.1fG", Double(bytes) / 1_073_741_824)
    }
}

@MainActor
private final class MetricsPanelView: NSView {
    private let cpu = MetricRow(icon: "cpu", title: "CPU")
    private let memory = MetricRow(icon: "memorychip", title: "Unified memory")
    private let temperature = MetricRow(icon: "thermometer.medium", title: "Temperature")
    private let disk = MetricRow(icon: "internaldrive", title: "Disk")
    private let battery = MetricRow(icon: "battery.75percent", title: "Battery")
    private lazy var rows = [cpu, memory, temperature, disk, battery]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let title = NSTextField(labelWithString: "FeatherStats")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor

        let note = NSTextField(labelWithString: "Live · every 3 seconds")
        note.font = .systemFont(ofSize: 11, weight: .regular)
        note.textColor = .secondaryLabelColor

        let headerText = NSStackView(views: [title, note])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 1

        let mark = NSImageView(image: NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil) ?? NSImage())
        mark.contentTintColor = .systemMint
        mark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)

        let header = NSStackView(views: [headerText, NSView(), mark])
        header.orientation = .horizontal
        header.alignment = .centerY

        let stack = NSStackView(views: [header] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 17),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -17),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ] + rows.flatMap { row in [
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            row.heightAnchor.constraint(equalToConstant: 38)
        ] })
    }

    required init?(coder: NSCoder) { nil }

    func render(_ snapshot: MetricSnapshot) {
        let cpuValue = snapshot.cpuUsage ?? 0
        cpu.update(
            value: snapshot.cpuUsage.map { "\(Int($0.rounded()))%" } ?? "…",
            detail: "Across \(snapshot.coreCount) logical cores",
            fraction: cpuValue / 100,
            severity: severity(cpuValue / 100)
        )

        let memoryFraction = snapshot.memoryTotal > 0
            ? Double(snapshot.memoryUsed) / Double(snapshot.memoryTotal) : 0
        memory.update(
            value: "\(formatBytes(snapshot.memoryUsed)) / \(formatBytes(snapshot.memoryTotal))",
            detail: "RAM and graphics share this pool",
            fraction: memoryFraction,
            severity: severity(memoryFraction)
        )

        if let degrees = snapshot.temperature {
            temperature.update(
                value: String(format: "%.0f °C", degrees),
                detail: "Hottest chip sensor",
                fraction: max(0, min(1, (degrees - 30) / 75)),
                severity: degrees >= 95 ? .critical : (degrees >= 80 ? .warning : .normal)
            )
        } else {
            temperature.update(
                value: snapshot.thermalState.label,
                detail: "Sensor value unavailable",
                fraction: thermalFraction(snapshot.thermalState),
                severity: thermalSeverity(snapshot.thermalState)
            )
        }

        let diskFraction = snapshot.diskTotal > 0
            ? Double(snapshot.diskUsed) / Double(snapshot.diskTotal) : 0
        disk.update(
            value: "\(formatBytes(snapshot.diskUsed)) / \(formatBytes(snapshot.diskTotal))",
            detail: "Macintosh HD",
            fraction: diskFraction,
            severity: severity(diskFraction)
        )

        if let batteryPercent = snapshot.batteryPercent {
            battery.isHidden = false
            battery.update(
                value: "\(batteryPercent)%",
                detail: snapshot.batteryIsCharging ? "Charging" : "On battery",
                fraction: Double(batteryPercent) / 100,
                severity: batteryPercent < 15 ? .critical : (batteryPercent < 30 ? .warning : .normal)
            )
        } else {
            battery.isHidden = true
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        return gib >= 100 ? String(format: "%.0fG", gib) : String(format: "%.1fG", gib)
    }

    private func severity(_ fraction: Double) -> MetricRow.Severity {
        fraction >= 0.9 ? .critical : (fraction >= 0.75 ? .warning : .normal)
    }

    private func thermalFraction(_ state: ProcessInfo.ThermalState) -> Double {
        switch state { case .nominal: 0.2; case .fair: 0.5; case .serious: 0.78; case .critical: 1; @unknown default: 0 }
    }

    private func thermalSeverity(_ state: ProcessInfo.ThermalState) -> MetricRow.Severity {
        switch state { case .serious: .warning; case .critical: .critical; default: .normal }
    }
}

@MainActor
private final class MetricRow: NSView {
    enum Severity { case normal, warning, critical }

    private let valueLabel = NSTextField(labelWithString: "—")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progress = MiniBar()

    init(icon: String, title: String) {
        super.init(frame: .zero)

        let image = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: title) ?? NSImage())
        image.contentTintColor = .secondaryLabelColor
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        image.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = .labelColor

        detailLabel.font = .systemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = -1

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let content = NSStackView(views: [image, labels, NSView(), valueLabel])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 9
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        progress.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progress)

        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 17),
            image.heightAnchor.constraint(equalToConstant: 17),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            progress.leadingAnchor.constraint(equalTo: labels.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor),
            progress.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 2),
            progress.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(value: String, detail: String, fraction: Double, severity: Severity) {
        valueLabel.stringValue = value
        detailLabel.stringValue = detail
        let color: NSColor = switch severity {
        case .normal: .systemMint
        case .warning: .systemOrange
        case .critical: .systemRed
        }
        progress.update(fraction: fraction, color: color)
    }
}

@MainActor
private final class MiniBar: NSView {
    private let fillLayer = CALayer()
    private var fraction: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        layer?.cornerRadius = 1
        fillLayer.cornerRadius = 1
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        CATransaction.commit()
    }

    func update(fraction: Double, color: NSColor) {
        self.fraction = max(0, min(1, fraction))
        fillLayer.backgroundColor = color.cgColor
        needsLayout = true
    }
}
