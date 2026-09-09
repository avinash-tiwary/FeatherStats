import AppKit

if CommandLine.arguments.contains("--snapshot") {
    let sampler = SystemMetricsSampler()
    sampler.primeCPU()
    Thread.sleep(forTimeInterval: 0.25)
    let snapshot = sampler.sample()
    print(snapshot.commandLineDescription)
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
