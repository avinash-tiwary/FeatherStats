import Darwin
import Foundation
import IOKit.ps

struct MetricSnapshot {
    let cpuUsage: Double?
    let coreCount: Int
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let temperature: Double?
    let thermalState: ProcessInfo.ThermalState
    let diskUsed: UInt64
    let diskTotal: UInt64
    let batteryPercent: Int?
    let batteryIsCharging: Bool

    var commandLineDescription: String {
        let cpu = cpuUsage.map { String(format: "%.1f%%", $0) } ?? "warming up"
        let memory = "\(Self.gibibytes(memoryUsed)) / \(Self.gibibytes(memoryTotal)) GiB"
        let temperature = temperature.map { String(format: "%.1f °C", $0) }
            ?? "unavailable (thermal state: \(thermalState.label))"
        let disk = "\(Self.gibibytes(diskUsed)) / \(Self.gibibytes(diskTotal)) GiB"
        let battery = batteryPercent.map { "\($0)%\(batteryIsCharging ? " charging" : "")" } ?? "not present"
        return "CPU: \(cpu) across \(coreCount) logical cores\nMemory: \(memory)\nTemperature: \(temperature)\nDisk: \(disk)\nBattery: \(battery)"
    }

    private static func gibibytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

final class SystemMetricsSampler {
    private struct CPUTicks {
        let used: UInt64
        let total: UInt64
    }

    private var previousCPUTicks: CPUTicks?
    private let smc = SMCReader()
    private var cachedTemperature: Double?
    private var cachedDisk: (used: UInt64, total: UInt64) = (0, 0)
    private var cachedBattery: (percent: Int, charging: Bool)?
    private var lastTemperatureRead = Date.distantPast
    private var lastDiskRead = Date.distantPast
    private var lastBatteryRead = Date.distantPast

    var coreCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    func primeCPU() {
        previousCPUTicks = readCPUTicks()
    }

    func sample() -> MetricSnapshot {
        let now = Date()
        let cpu = readCPUUsage()
        let memory = readMemory()
        if now.timeIntervalSince(lastTemperatureRead) >= 30 {
            cachedTemperature = smc.temperature()
            lastTemperatureRead = now
        }
        if now.timeIntervalSince(lastDiskRead) >= 60 {
            cachedDisk = readDisk()
            lastDiskRead = now
        }
        if now.timeIntervalSince(lastBatteryRead) >= 30 {
            cachedBattery = readBattery()
            lastBatteryRead = now
        }

        return MetricSnapshot(
            cpuUsage: cpu,
            coreCount: coreCount,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            temperature: cachedTemperature,
            thermalState: ProcessInfo.processInfo.thermalState,
            diskUsed: cachedDisk.used,
            diskTotal: cachedDisk.total,
            batteryPercent: cachedBattery?.percent,
            batteryIsCharging: cachedBattery?.charging ?? false
        )
    }

    private func readCPUUsage() -> Double? {
        guard let current = readCPUTicks() else { return nil }
        defer { previousCPUTicks = current }
        guard let previous = previousCPUTicks,
              current.total >= previous.total,
              current.used >= previous.used else { return nil }

        let totalDelta = current.total - previous.total
        let usedDelta = current.used - previous.used
        guard totalDelta > 0 else { return 0 }
        return min(100, max(0, Double(usedDelta) / Double(totalDelta) * 100))
    }

    private func readCPUTicks() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let byteCount = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }

        let ticks = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))
        var used: UInt64 = 0
        var total: UInt64 = 0

        for core in 0..<Int(cpuCount) {
            let base = core * Int(CPU_STATE_MAX)
            guard base + Int(CPU_STATE_IDLE) < ticks.count else { break }
            let user = UInt64(UInt32(bitPattern: ticks[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: ticks[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: ticks[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: ticks[base + Int(CPU_STATE_IDLE)]))
            used += user + system + nice
            total += user + system + nice + idle
        }
        return CPUTicks(used: used, total: total)
    }

    private func readMemory() -> (used: UInt64, total: UInt64) {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total) }
        var kernelPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &kernelPageSize)
        let pageSize = UInt64(kernelPageSize)
        let reclaimablePages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        let available = min(total, reclaimablePages * pageSize)
        return (total - available, total)
    }

    private func readDisk() -> (used: UInt64, total: UInt64) {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let available = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
            return (total > available ? total - available : 0, total)
        } catch {
            return (0, 0)
        }
    }

    private func readBattery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = state == kIOPSACPowerValue
                && (description[kIOPSIsChargingKey] as? Bool ?? false)
            return (Int((Double(current) / Double(maximum) * 100).rounded()), charging)
        }
        return nil
    }
}
