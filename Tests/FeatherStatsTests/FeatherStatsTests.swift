import Foundation
import Testing
@testable import FeatherStats

@Test func snapshotContainsCoreCountAndMemoryTotal() {
    let sampler = SystemMetricsSampler()
    sampler.primeCPU()
    Thread.sleep(forTimeInterval: 0.05)
    let snapshot = sampler.sample()

    #expect(snapshot.coreCount > 0)
    #expect(snapshot.memoryTotal > 0)
    #expect(snapshot.memoryUsed <= snapshot.memoryTotal)
    #expect(snapshot.cpuUsage == nil || (0...100).contains(snapshot.cpuUsage!))
}
