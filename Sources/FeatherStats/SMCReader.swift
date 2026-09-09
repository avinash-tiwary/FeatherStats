import Foundation
import IOKit
import CSystemSensors

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

final class SMCReader {
    private let connection: io_connect_t
    private var temperatureKeys: [String]

    init() {
        var openedConnection: io_connect_t = 0
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service != IO_OBJECT_NULL {
            IOServiceOpen(service, mach_task_self_, 0, &openedConnection)
            IOObjectRelease(service)
        }
        connection = openedConnection

        let knownKeys = [
            "TC0P", "TC0E", "TC0F", "TC1C", "TC2C",
            "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T",
            "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp0n", "Tp0r", "Tp0v"
        ]
        temperatureKeys = knownKeys.filter { Self.readTemperature(key: $0, connection: openedConnection) != nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func temperature() -> Double? {
        let hidTemperature = FSReadHIDTemperature()
        if hidTemperature.isFinite, (10...115).contains(hidTemperature) {
            return hidTemperature
        }
        guard connection != 0 else { return nil }
        let readings = temperatureKeys.compactMap { Self.readTemperature(key: $0, connection: connection) }
            .filter { (10...115).contains($0) }
        return readings.max()
    }

    private static func readTemperature(key: String, connection: io_connect_t) -> Double? {
        guard connection != 0 else { return nil }
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharacterCode(key)
        input.data8 = 9 // get key info

        var outputSize = MemoryLayout<SMCKeyData>.stride
        var result = IOConnectCallStructMethod(
            connection, 2, &input, MemoryLayout<SMCKeyData>.stride, &output, &outputSize
        )
        guard result == kIOReturnSuccess, output.keyInfo.dataSize > 0 else { return nil }

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = 5 // read bytes
        output = SMCKeyData()
        outputSize = MemoryLayout<SMCKeyData>.stride
        result = IOConnectCallStructMethod(
            connection, 2, &input, MemoryLayout<SMCKeyData>.stride, &output, &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0) }
        let type = string(from: output.keyInfo.dataType)
        switch type {
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return Double(Float(bitPattern: bits))
        default:
            return nil
        }
    }

    private static func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff), UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
