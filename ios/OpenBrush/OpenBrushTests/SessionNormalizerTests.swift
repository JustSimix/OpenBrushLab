// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OpenBrush

enum SyntheticSession {
    static let key = String(repeating: "a", count: 64)
    static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    static func record(local: String = "2026-11-10T11:37:15", duration: Int = 75,
                       score: Int = 59, zone: Int = 15, salt: Int = 0) -> OcleanTYPE1Record {
        var raw = Array(repeating: UInt8(0), count: 42)
        let parts = local.split(whereSeparator: { "-T:".contains($0) }).map { Int($0)! }
        raw.replaceSubrange(0..<6, with: ([parts[0]-2000] + Array(parts[1...5])).map { UInt8($0) })
        raw[6] = 231; raw[7] = 0; raw[8] = 75
        raw[9] = UInt8(duration >> 8); raw[10] = UInt8(duration & 255)
        raw[17] = UInt8(zone); raw[33] = UInt8(score); raw[41] = UInt8(salt)
        let frame = Data(OcleanTYPE1Decoder.magic + [0,1] + raw)
        return OcleanTYPE1Decoder.decode([frame], deviceKey: key).records[0]
    }
    static func capture(_ records: [OcleanTYPE1Record], at: Date = date("2026-11-11T12:00:00Z"),
                        complete: Bool = true, status: TYPE1Status = .complete,
                        drift: Double? = nil, issue: CaptureIssue? = nil) -> OcleanCaptureEnvelope {
        OcleanCaptureEnvelope(deviceKey: key, capturedAt: at,
            result: .init(status: status, records: records, declaredCount: records.count),
            transportCompleted: complete, issue: issue, estimatedClockDriftSeconds: drift)
    }
    static func archive(_ records: [OcleanTYPE1Record], at: Date = date("2026-11-11T12:00:00Z"),
                        drift: Double? = nil) throws -> SessionArchive {
        var value = SessionArchive()
        try SessionNormalizer.ingest(capture(records, at: at, drift: drift), into: &value)
        return value
    }
}

@MainActor
final class SessionNormalizerTests: XCTestCase {
    func testIdentityMatchesPythonRuleAndIgnoresDurationScore() throws {
        let first = SyntheticSession.record()
        let changed = SyntheticSession.record(duration: 30, score: 37)
        let a = try SessionNormalizer.identity(deviceKey: SyntheticSession.key, record: first)
        XCTAssertEqual(a, "2fc2bf9412d6d0ab5b5af6a1e2d7453b802db3096e764e0625f5e3e6e12a7eb6") // Independent Python canonical JSON hash.
        XCTAssertEqual(a, try SessionNormalizer.identity(deviceKey: SyntheticSession.key, record: changed))
        XCTAssertEqual("openbrushlab:toothbrushing:v1:" + a,
            try SynchronizationIdentity.make(deviceKey: SyntheticSession.key,
                deviceLocalTimestamp: "2026-11-10T11:37:15", timezoneWireIndex: 15, scheme: 231))
    }

    func testTrustProfileExportsNormalAndInterruptedThirtySecondSession() throws {
        for duration in [75,30] {
            let archive = try SyntheticSession.archive([SyntheticSession.record(duration: duration, score: 37)])
            let entry = try XCTUnwrap(archive.sessions.values.first)
            XCTAssertTrue(entry.canExport)
            XCTAssertEqual(try entry.healthSession().durationSeconds, duration)
            XCTAssertFalse(try entry.healthSession().isTestFixture)
        }
    }

    func testVariantsBlockExportAndRetainBoth() throws {
        var archive = try SyntheticSession.archive([SyntheticSession.record()])
        try SessionNormalizer.ingest(SyntheticSession.capture([SyntheticSession.record(duration: 30, score: 37)],
            at: SyntheticSession.date("2026-11-12T12:00:00Z")), into: &archive)
        let entry = try XCTUnwrap(archive.sessions.values.first)
        XCTAssertEqual(archive.sessions.count, 1)
        XCTAssertEqual(entry.variants.count, 2)
        XCTAssertTrue(entry.reviewReasons.contains(.conflictingVariants))
        XCTAssertFalse(entry.canExport)
    }

    func testYearZeroVoidScoreAndShortStayInHold() throws {
        let inputs = [SyntheticSession.record(local: "2000-01-01T00:00:00"),
            SyntheticSession.record(score: 1), SyntheticSession.record(duration: 14)]
        for (record, reason) in zip(inputs, [SessionReviewReason.invalidDate,.voidScore,.tooShort]) {
            let entry = try XCTUnwrap(try SyntheticSession.archive([record]).sessions.values.first)
            XCTAssertTrue(entry.reviewReasons.contains(reason)); XCTAssertFalse(entry.canExport)
        }
    }

    func testDSTGapFoldAndWinterSummerWireOffsets() {
        XCTAssertTrue(SessionNormalizer.verifyTime(SyntheticSession.record(local: "2026-03-29T02:30:00")).reasons.contains(.nonexistentLocalTime))
        let winterFold = SessionNormalizer.verifyTime(SyntheticSession.record(local: "2026-10-25T02:30:00", zone: 15))
        let summerFold = SessionNormalizer.verifyTime(SyntheticSession.record(local: "2026-10-25T02:30:00", zone: 16))
        XCTAssertTrue(winterFold.reasons.isEmpty); XCTAssertTrue(summerFold.reasons.isEmpty)
        XCTAssertTrue(winterFold.foldDisambiguated); XCTAssertTrue(summerFold.foldDisambiguated)
        XCTAssertEqual(winterFold.startUTC!.timeIntervalSince(summerFold.startUTC!), 3600)
        XCTAssertTrue(SessionNormalizer.verifyTime(SyntheticSession.record(zone: 16)).reasons.contains(.timezoneMismatch))
        XCTAssertTrue(SessionNormalizer.verifyTime(SyntheticSession.record(local: "2026-07-10T11:37:15", zone: 16)).reasons.isEmpty)
    }

    func testFutureEndThresholdAndHistoricalAgeIsNotDrift() throws {
        let end = SyntheticSession.date("2026-11-10T10:38:30Z")
        let record = SyntheticSession.record()
        let boundary = try SyntheticSession.archive([record], at: end.addingTimeInterval(-5))
        XCTAssertFalse(boundary.sessions.values.first!.reviewReasons.contains(.futureEnd))
        let future = try SyntheticSession.archive([record], at: end.addingTimeInterval(-6))
        XCTAssertTrue(future.sessions.values.first!.reviewReasons.contains(.futureEnd))
        let distantFuture = try SyntheticSession.archive([record], at: end.addingTimeInterval(-121))
        XCTAssertTrue(distantFuture.sessions.values.first!.reviewReasons.contains(.clockDrift))
        let old = try SyntheticSession.archive([record], at: end.addingTimeInterval(100*86400))
        XCTAssertTrue(old.sessions.values.first!.canExport)
    }

    func testIndependentDriftAboveTwoMinutesBothDirections() throws {
        for drift in [-121.0,121.0] {
            let entry = try XCTUnwrap(try SyntheticSession.archive([SyntheticSession.record()], drift: drift).sessions.values.first)
            XCTAssertTrue(entry.reviewReasons.contains(.clockDrift)); XCTAssertFalse(entry.canExport)
        }
        XCTAssertTrue(try SyntheticSession.archive([SyntheticSession.record()], drift: 120).sessions.values.first!.canExport)
    }

    func testIncompleteTransportNeverPromotesUntilConfirmed() throws {
        let record = SyntheticSession.record()
        var archive = SessionArchive()
        try SessionNormalizer.ingest(SyntheticSession.capture([record], complete: false), into: &archive)
        XCTAssertFalse(archive.sessions.values.first!.canExport)
        try SessionNormalizer.ingest(SyntheticSession.capture([record]), into: &archive)
        XCTAssertTrue(archive.sessions.values.first!.canExport)
    }

    func testFullRingLossWarningAndFirstFullRingWarning() throws {
        let previous = SyntheticSession.record(local: "2026-11-01T08:00:00")
        var archive = try SyntheticSession.archive([previous])
        let key = try XCTUnwrap(archive.sessions.keys.first)
        let payload = try archive.sessions[key]!.healthSession().payloadHash
        archive.sessions[key]!.delivery = SessionDelivery(state: .verified, version: 1, payloadHash: payload, recordedAt: Date())
        let records = (0..<32).map { SyntheticSession.record(local: String(format: "2026-11-10T11:%02d:00", $0)) }
        let capture = SyntheticSession.capture(records)
        XCTAssertTrue(SessionNormalizer.warnings(for: capture, archive: archive).contains { $0.code == "ring-loss" })
        XCTAssertTrue(SessionNormalizer.warnings(for: capture, archive: SessionArchive()).contains { $0.code == "first-full-ring" })
        let overlap = SyntheticSession.capture([previous] + Array(records.dropFirst()))
        XCTAssertFalse(SessionNormalizer.warnings(for: overlap, archive: archive).contains { $0.code == "ring-loss" })
    }

    func testEmptyConnectionAndBondingWarningsAreConditional() {
        let empty = SyntheticSession.capture([], status: .zeroCount)
        XCTAssertTrue(SessionNormalizer.warnings(for: empty, archive: SessionArchive()).contains { $0.code == "empty-ring" })
        let failure = SyntheticSession.capture([], complete: false, issue: .connectionUnavailable)
        XCTAssertTrue(SessionNormalizer.warnings(for: failure, archive: SessionArchive()).contains { $0.code == "coexistence" })
        let security = SyntheticSession.capture([], complete: false, issue: .securityReported)
        XCTAssertTrue(SessionNormalizer.warnings(for: security, archive: SessionArchive()).contains { $0.code == "bonding" })
    }

    func testArchiveRetainsSessionsOutsideRingAndIdempotentCaptures() throws {
        let first = SyntheticSession.capture([SyntheticSession.record()])
        var archive = SessionArchive()
        try SessionNormalizer.ingest(first, into: &archive)
        try SessionNormalizer.ingest(first, into: &archive)
        XCTAssertEqual(archive.sessions.count, 1); XCTAssertEqual(archive.captures.count, 1)
        try SessionNormalizer.ingest(SyntheticSession.capture([SyntheticSession.record(local: "2026-11-11T08:00:00")]), into: &archive)
        XCTAssertEqual(archive.sessions.count, 2)
    }

    func testFullRingWithInvalidDateWarnsCoverageAndUnknownOffsetHolds() throws {
        let records = (0..<31).map { SyntheticSession.record(local: String(format: "2026-11-10T11:%02d:00", $0)) }
            + [SyntheticSession.record(local: "2000-01-01T00:00:00")]
        XCTAssertTrue(SessionNormalizer.warnings(for: SyntheticSession.capture(records), archive: SessionArchive()).contains { $0.code == "ring-date-coverage" })
        let invalid = try SyntheticSession.archive([SyntheticSession.record(zone: 0)])
        XCTAssertTrue(invalid.sessions.values.first!.reviewReasons.contains(.unknownTimezone))
    }

    func testDifferentDeviceIsHeldInsteadOfExportedAsAnotherBrush() throws {
        var archive = try SyntheticSession.archive([SyntheticSession.record()])
        let different = OcleanCaptureEnvelope(deviceKey: String(repeating: "b", count: 64),
            capturedAt: SyntheticSession.date("2026-11-12T12:00:00Z"),
            result: .init(status: .complete, records: [SyntheticSession.record()], declaredCount: 1),
            transportCompleted: true)
        try SessionNormalizer.ingest(different, into: &archive)
        XCTAssertEqual(archive.sessions.count, 2)
        XCTAssertTrue(archive.sessions.values.contains { $0.reviewReasons.contains(.differentDevice) && !$0.canExport })
    }

    func testFutureBoundUsesSelectedVariantsOwnCapture() throws {
        let shorter = SyntheticSession.record(duration: 30, score: 37)
        let complete = SyntheticSession.record()
        var archive = try SyntheticSession.archive([shorter], at: SyntheticSession.date("2026-11-10T10:37:50Z"))
        try SessionNormalizer.ingest(SyntheticSession.capture([complete], at: SyntheticSession.date("2026-11-10T10:39:00Z")), into: &archive)
        let key = try XCTUnwrap(archive.sessions.keys.first)
        var entry = try XCTUnwrap(archive.sessions[key])
        entry.selectedFingerprint = complete.recordFingerprint
        SessionNormalizer.refresh(&entry, boundDeviceKey: archive.boundDeviceKey)
        XCTAssertFalse(entry.reviewReasons.contains(.futureEnd))
        XCTAssertTrue(entry.canExport)
    }

    func testArchiveDiskRoundTripAndCorruptionFailsClosed() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = SessionArchiveFileStore(base: base)
        let archive = try SyntheticSession.archive([SyntheticSession.record()])
        try store.save(archive)
        XCTAssertEqual(try store.load().sessions.keys.sorted(), archive.sessions.keys.sorted())
        let file = base.appendingPathComponent("OpenBrush/session-archive-v1.json")
        try Data("corrotto".utf8).write(to: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "corrotto")
    }
}
