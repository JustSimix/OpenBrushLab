// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

enum TYPE1Status: String, Codable, Sendable {
    case incomplete = "incomplete"
    case complete = "complete-candidate"
    case limitExceeded = "capture-limit-exceeded"
    case unknownFormat = "unknown-format"
    case invalidCount = "invalid-record-count"
    case zeroCount = "zero-count-no-complete-history"
    case trailingBytes = "unexpected-trailing-bytes"

    var italianDescription: String {
        switch self {
        case .incomplete: return "Risposta incompleta"
        case .complete: return "Risposta ricomposta"
        case .limitExceeded: return "Superati i limiti di acquisizione"
        case .unknownFormat: return "Formato non riconosciuto"
        case .invalidCount: return "Conteggio dei record non valido"
        case .zeroCount: return "Conteggio zero: lo storico completo non è disponibile"
        case .trailingBytes: return "Byte finali non previsti"
        }
    }
}

struct OcleanTYPE1Record: Codable, Equatable, Sendable {
    let kind: String
    let recordFingerprint: String
    let deviceLocalTimestamp: String?
    let deviceDatetimeRaw: [Int]
    let timestampSemantics: String
    let schemeRaw: Int
    let scheduledDurationS: Int
    let actualDurationCandidateS: Int
    let timezoneRaw: Int?
    let scoreRaw: Int?
    let issues: [String]
    let protocolValidation: String
    let healthkitReady: Bool

    enum CodingKeys: String, CodingKey {
        case kind, issues
        case recordFingerprint = "record_fingerprint", deviceLocalTimestamp = "device_local_timestamp"
        case deviceDatetimeRaw = "device_datetime_raw", timestampSemantics = "timestamp_semantics"
        case schemeRaw = "scheme_raw", scheduledDurationS = "scheduled_duration_s"
        case actualDurationCandidateS = "actual_duration_candidate_s", timezoneRaw = "timezone_raw"
        case scoreRaw = "score_raw", protocolValidation = "protocol_validation", healthkitReady = "healthkit_ready"
    }

    // Python emits explicit null values for these record fields, not missing keys.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(recordFingerprint, forKey: .recordFingerprint)
        try values.encode(deviceLocalTimestamp, forKey: .deviceLocalTimestamp)
        try values.encode(deviceDatetimeRaw, forKey: .deviceDatetimeRaw)
        try values.encode(timestampSemantics, forKey: .timestampSemantics)
        try values.encode(schemeRaw, forKey: .schemeRaw)
        try values.encode(scheduledDurationS, forKey: .scheduledDurationS)
        try values.encode(actualDurationCandidateS, forKey: .actualDurationCandidateS)
        try values.encode(timezoneRaw, forKey: .timezoneRaw)
        try values.encode(scoreRaw, forKey: .scoreRaw)
        try values.encode(issues, forKey: .issues)
        try values.encode(protocolValidation, forKey: .protocolValidation)
        try values.encode(healthkitReady, forKey: .healthkitReady)
    }
}

struct OcleanTYPE1Result: Codable, Equatable, Sendable {
    var status: TYPE1Status
    var records: [OcleanTYPE1Record] = []
    var receivedBytes: Int?
    var declaredCount: Int?
    var expectedBytes: Int?
    var transportPaddingZeroBytes: Int?
    var duplicateRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case status, records
        case receivedBytes = "received_bytes", declaredCount = "declared_count"
        case expectedBytes = "expected_bytes", transportPaddingZeroBytes = "transport_padding_zero_bytes"
        case duplicateRecordCount = "duplicate_record_count"
    }
}

enum OcleanTYPE1Decoder {
    static let maximumRecords = 64
    static let maximumNotifications = 256
    static let maximumBytes = 8192
    static let magic: [UInt8] = [0x03, 0x07, 0x2A, 0x42, 0x23]

    static func decode(_ notifications: [Data], deviceKey: String = "") -> OcleanTYPE1Result {
        guard notifications.count <= maximumNotifications else { return .init(status: .limitExceeded) }
        var countBytes = 0
        for frame in notifications {
            guard frame.count <= maximumBytes - countBytes else { return .init(status: .limitExceeded) }
            countBytes += frame.count
        }
        let bytes = Array(notifications.joined())
        var result = OcleanTYPE1Result(status: .incomplete, receivedBytes: bytes.count)
        guard bytes.count >= 7 else { return result }
        guard Array(bytes.prefix(5)) == magic else { result.status = .unknownFormat; return result }
        let count = bigEndian(bytes, at: 5)
        result.declaredCount = count
        guard count <= maximumRecords else { result.status = .invalidCount; return result }
        if count == 0 {
            result.status = .zeroCount
            if bytes.count >= 18 {
                let raw = Array(bytes[7..<18])
                if Array(raw.prefix(3)) != [0, 0, 0] {
                    result.records = [makeRecord(raw, inline: true, deviceKey: deviceKey)]
                }
            }
            return result
        }
        let required = 7 + count * 42
        result.expectedBytes = required
        guard bytes.count >= required else { return result }
        if bytes.count > required {
            let tail = bytes[required...]
            guard tail.count > 0, tail.count < 20,
                  notifications.allSatisfy({ $0.count == 20 }), tail.allSatisfy({ $0 == 0 }) else {
                result.status = .trailingBytes
                return result
            }
            result.transportPaddingZeroBytes = tail.count
        }
        result.records = (0..<count).map { index in
            let offset = 7 + index * 42
            return makeRecord(Array(bytes[offset..<(offset+42)]), inline: false, deviceKey: deviceKey)
        }
        result.status = .complete
        result.duplicateRecordCount = result.records.count - Set(result.records.map(\.recordFingerprint)).count
        return result
    }

    private static func bigEndian(_ bytes: [UInt8], at offset: Int) -> Int {
        Int(bytes[offset]) * 256 + Int(bytes[offset+1])
    }

    private static func timestamp(_ raw: [UInt8]) -> String? {
        let year = 2000 + Int(raw[0]), month = Int(raw[1]), day = Int(raw[2])
        let hour = Int(raw[3]), minute = Int(raw[4]), second = Int(raw[5])
        guard year >= 2015, (1...12).contains(month), (0...23).contains(hour),
              (0...59).contains(minute), (0...59).contains(second) else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month-1]).contains(day) else { return nil }
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
    }

    private static func makeRecord(_ raw: [UInt8], inline: Bool, deviceKey: String) -> OcleanTYPE1Record {
        var issues: [String] = []
        let date = timestamp(raw)
        if date == nil { issues.append("invalid-or-unverified-device-date") }
        let scheduled = bigEndian(raw, at: 7), actual = bigEndian(raw, at: 9)
        if !(1...7200).contains(actual) || !(1...7200).contains(scheduled) || actual > scheduled {
            issues.append("duration-needs-review")
        }
        if inline { issues.append("inline-fragment-not-complete-history-or-proven-newest") }
        var fingerprintData = Data(deviceKey.utf8)
        fingerprintData.append(0)
        fingerprintData.append(contentsOf: raw)
        let fingerprint = SHA256.hash(data: fingerprintData).map { String(format: "%02x", $0) }.joined()
        return OcleanTYPE1Record(kind: inline ? "inline-fragment" : "full-record",
            recordFingerprint: fingerprint, deviceLocalTimestamp: date,
            deviceDatetimeRaw: raw.prefix(6).map(Int.init), timestampSemantics: "start-or-end-unvalidated",
            schemeRaw: Int(raw[6]), scheduledDurationS: scheduled, actualDurationCandidateS: actual,
            timezoneRaw: inline ? nil : Int(raw[17]), scoreRaw: inline ? nil : Int(raw[33]),
            issues: issues, protocolValidation: "upstream-layout-candidate", healthkitReady: false)
    }
}

struct OcleanTYPE1Assembler {
    private(set) var notifications: [Data] = []
    private(set) var receivedBytes = 0
    private(set) var exceededLimit = false

    @discardableResult
    mutating func feed(_ notification: Data) -> Bool {
        guard !exceededLimit, notifications.count < OcleanTYPE1Decoder.maximumNotifications,
              notification.count <= OcleanTYPE1Decoder.maximumBytes - receivedBytes else {
            exceededLimit = true
            return false
        }
        notifications.append(notification)
        receivedBytes += notification.count
        return true
    }

    func result(deviceKey: String = "") -> OcleanTYPE1Result {
        exceededLimit ? .init(status: .limitExceeded) : OcleanTYPE1Decoder.decode(notifications, deviceKey: deviceKey)
    }
}
