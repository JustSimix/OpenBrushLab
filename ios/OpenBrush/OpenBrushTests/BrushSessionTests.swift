// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import HealthKit
@testable import OpenBrush

@MainActor
final class BrushSessionTests: XCTestCase {
    func testFixtureMatchesTheObservedIntervalAndSyntheticPythonIdentity() throws {
        let session = try TestSession.make()
        XCTAssertEqual(session.durationSeconds, 75)
        XCTAssertEqual(session.endUTC.timeIntervalSince(session.startUTC), 75)
        XCTAssertEqual(session.timeZoneIdentifier, "Europe/Rome")
        // Expected value calculated on Windows using Python stdlib canonical JSON + SHA256.
        XCTAssertEqual(session.syncIdentifier, "openbrushlab:toothbrushing:v1:90181c65110fdc440534e6d82f373793097ffe32d417f9a509a931b8f1c42fce")
        XCTAssertEqual(TestSession.publicSyntheticDeviceKey, String(repeating: "0", count: 64))
    }

    func testVersionBumpKeepsIdentityAndInterval() throws {
        let first = try TestSession.make(version: 1)
        let second = try TestSession.make(version: 2)
        XCTAssertEqual(first.syncIdentifier, second.syncIdentifier)
        XCTAssertEqual(first.startUTC, second.startUTC)
        XCTAssertEqual(first.endUTC, second.endUTC)
        XCTAssertEqual(first.payloadHash, second.payloadHash)
        XCTAssertEqual(second.syncVersion, 2)
    }

    func testMetadataAndCategoryValueAreHealthKitCompatible() throws {
        let session = try TestSession.make(version: 2)
        let sample = try HealthKitClient.makeSample(session)
        XCTAssertEqual(sample.categoryType.identifier, HKCategoryTypeIdentifier.toothbrushingEvent.rawValue)
        XCTAssertEqual(sample.value, HKCategoryValue.notApplicable.rawValue)
        XCTAssertEqual(sample.startDate, session.startUTC)
        XCTAssertEqual(sample.endDate, session.endUTC)
        XCTAssertEqual(sample.metadata?[HKMetadataKeySyncIdentifier] as? String, session.syncIdentifier)
        XCTAssertEqual((sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(sample.metadata?[HKMetadataKeyTimeZone] as? String, "Europe/Rome")
        XCTAssertEqual((sample.metadata?["it.imix.openbrush.fixture"] as? NSNumber)?.boolValue, true)
    }

    func testInvalidDurationZoneVersionAndIdentityAreRejected() throws {
        let valid = try TestSession.make()
        for (duration, zone, version, identifier) in [
            (74, "Europe/Rome", 1, valid.syncIdentifier),
            (75, "Invalid/Zone", 1, valid.syncIdentifier),
            (75, "Europe/Rome", 0, valid.syncIdentifier),
            (75, "Europe/Rome", 1, "unstable-random-id")
        ] {
            XCTAssertThrowsError(try BrushSession(startUTC: valid.startUTC, endUTC: valid.endUTC,
                durationSeconds: duration, timeZoneIdentifier: zone, syncIdentifier: identifier, syncVersion: version))
        }
    }

    func testFileReceiptPersistsAcrossInstancesWithoutSessionDates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try TestSession.make()
        let first = FileReceiptStore(directory: folder)
        let receipt = WriteReceipt(version: 1, payloadHash: session.payloadHash)
        try first.set(receipt, for: session.syncIdentifier)
        let second = FileReceiptStore(directory: folder)
        XCTAssertEqual(try second.receipt(for: session.syncIdentifier), receipt)
        let file = folder.appendingPathComponent("OpenBrush/health-write-receipts-v1.json")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains("2026-11-10"))
    }
}
