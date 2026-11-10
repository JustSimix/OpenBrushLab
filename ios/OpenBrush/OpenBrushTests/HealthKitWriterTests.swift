// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OpenBrush

@MainActor
private final class MemoryReceipts: ReceiptStore {
    var values: [String: WriteReceipt] = [:]
    var failOnSet = false
    func receipt(for identifier: String) throws -> WriteReceipt? { values[identifier] }
    func set(_ receipt: WriteReceipt, for identifier: String) throws {
        if failOnSet { throw OpenBrushError.localStorageUnavailable }
        values[identifier] = receipt
    }
}

@MainActor
private final class FakeHealthClient: HealthStoreClient {
    var isAvailable = true
    var writeAuthorization: HealthWriteAuthorization = .authorized
    let sourceBundleIdentifier = "it.imix.openbrush"
    var events: [StoredBrushEvent] = []
    var readHidden = false
    var failQuery = false
    var failSave = false
    var saveCalls = 0
    var queryCalls = 0
    var requests = 0

    func event(_ session: BrushSession, source: String? = nil) -> StoredBrushEvent {
        StoredBrushEvent(id: UUID(), sourceName: source == nil ? "OpenBrush" : "Oclean (test double)",
            sourceBundleIdentifier: source ?? sourceBundleIdentifier,
            startUTC: session.startUTC, endUTC: session.endUTC,
            syncIdentifier: session.syncIdentifier, syncVersion: session.syncVersion,
            timeZoneIdentifier: session.timeZoneIdentifier)
    }
    func requestAuthorization() async throws { requests += 1 }
    func matching(syncIdentifier: String) async throws -> [StoredBrushEvent] {
        queryCalls += 1
        if failQuery { throw OpenBrushError.queryFailed }
        return readHidden ? [] : events.filter { $0.syncIdentifier == syncIdentifier }
    }
    func overlapping(startUTC: Date, endUTC: Date) async throws -> [StoredBrushEvent] {
        if failQuery { throw OpenBrushError.queryFailed }
        return readHidden ? [] : events.filter { $0.startUTC < endUTC && $0.endUTC > startUTC }
    }
    func save(_ session: BrushSession) async throws {
        saveCalls += 1
        if failSave { throw OpenBrushError.saveFailed }
        // Simulated HealthKit policy only; actual OS replacement must be tested on iPhone.
        let own = events.filter { $0.sourceBundleIdentifier == sourceBundleIdentifier && $0.syncIdentifier == session.syncIdentifier }
        if own.contains(where: { ($0.syncVersion ?? 0) >= session.syncVersion }) { return }
        events.removeAll { $0.sourceBundleIdentifier == sourceBundleIdentifier && $0.syncIdentifier == session.syncIdentifier }
        events.append(event(session))
    }
}

@MainActor
final class HealthKitWriterTests: XCTestCase {
    func testSecondTapDoesNotSaveAgain() async throws {
        let client = FakeHealthClient()
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        let session = try TestSession.make()
        let first = try await writer.write(session)
        let second = try await writer.write(session)
        XCTAssertEqual(first, .written(version: 1))
        XCTAssertEqual(second, .alreadyPresent(version: 1))
        XCTAssertEqual(client.saveCalls, 1)
        XCTAssertEqual(client.events.count, 1)
        XCTAssertGreaterThan(client.queryCalls, 0)
    }

    func testHigherVersionUsesOneSaveAndSameIdentity() async throws {
        let client = FakeHealthClient()
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        _ = try await writer.write(TestSession.make(version: 1))
        let outcome = try await writer.write(TestSession.make(version: 2))
        XCTAssertEqual(outcome, .versionUpdated(from: 1, to: 2))
        XCTAssertEqual(client.events.count, 1)
        XCTAssertEqual(client.events.first?.syncVersion, 2)
        let repeated = try await writer.write(TestSession.make(version: 2))
        XCTAssertEqual(repeated, .alreadyPresent(version: 2))
        XCTAssertEqual(client.saveCalls, 2)
    }

    func testNoDowngrade() async throws {
        let client = FakeHealthClient()
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        _ = try await writer.write(TestSession.make(version: 2))
        let result = try await writer.write(TestSession.make(version: 1))
        XCTAssertEqual(result, .alreadyPresent(version: 2))
        XCTAssertEqual(client.saveCalls, 1)
    }

    func testSameVersionDifferentPayloadRefusesSave() async throws {
        let client = FakeHealthClient()
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        let initial = try TestSession.make()
        _ = try await writer.write(initial)
        let changed = try BrushSession(startUTC: initial.startUTC, endUTC: initial.startUTC.addingTimeInterval(60),
            durationSeconds: 60, timeZoneIdentifier: initial.timeZoneIdentifier,
            syncIdentifier: initial.syncIdentifier, syncVersion: initial.syncVersion)
        do { _ = try await writer.write(changed); XCTFail("Expected conflict") }
        catch { XCTAssertEqual(client.saveCalls, 1) }
    }

    func testForeignSourceIsShownBeforeWritingAndNeverModified() async throws {
        let client = FakeHealthClient()
        let session = try TestSession.make()
        let foreign = client.event(session, source: "example.oclean.synthetic-test")
        client.events = [foreign]
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        let outcome = try await writer.write(session)
        XCTAssertEqual(outcome, .foreignConfirmationRequired([foreign]))
        XCTAssertEqual(client.saveCalls, 0)
        _ = try await writer.write(session, allowForeignOverlap: true)
        XCTAssertEqual(client.events.filter { $0.id == foreign.id }, [foreign])
        XCTAssertEqual(client.events.count, 2)
    }

    func testReadHiddenUsesReceiptWithoutClaimingVerifiedPresence() async throws {
        let client = FakeHealthClient()
        client.readHidden = true
        let receipts = MemoryReceipts()
        let writer = HealthKitWriter(client: client, receipts: receipts)
        let session = try TestSession.make()
        let first = try await writer.write(session)
        XCTAssertEqual(first, .submittedNotVerified(version: 1, wasUpdate: false))
        // Simulate a new view-model/writer in the same installation.
        let secondWriter = HealthKitWriter(client: client, receipts: receipts)
        let second = try await secondWriter.write(session)
        XCTAssertEqual(second, .alreadySubmittedLocally(version: 1))
        XCTAssertEqual(client.saveCalls, 1)
    }

    func testHigherVersionStillWorksWhenReadIsHidden() async throws {
        let client = FakeHealthClient()
        client.readHidden = true
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        _ = try await writer.write(TestSession.make(version: 1))
        let result = try await writer.write(TestSession.make(version: 2))
        XCTAssertEqual(result, .submittedNotVerified(version: 2, wasUpdate: true))
        XCTAssertEqual(client.events.count, 1)
    }

    func testAuthorizationCompletionDoesNotProveWritePermission() async throws {
        let client = FakeHealthClient()
        client.writeAuthorization = .denied
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        try await writer.requestAuthorization()
        do { _ = try await writer.write(TestSession.make()); XCTFail("Expected denial") }
        catch { XCTAssertEqual(client.saveCalls, 0) }
        XCTAssertEqual(client.requests, 1)
    }

    func testQueryFailureDoesNotFallThroughToSave() async throws {
        let client = FakeHealthClient()
        client.failQuery = true
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        do { _ = try await writer.write(TestSession.make()); XCTFail("Expected query error") }
        catch { XCTAssertEqual(client.saveCalls, 0) }
    }

    func testMultipleOwnSamplesAreNotAutomaticallyDeleted() async throws {
        let client = FakeHealthClient()
        let session = try TestSession.make()
        client.events = [client.event(session), client.event(session)]
        let writer = HealthKitWriter(client: client, receipts: MemoryReceipts())
        do { _ = try await writer.write(session); XCTFail("Expected conflict") }
        catch { XCTAssertEqual(client.saveCalls, 0); XCTAssertEqual(client.events.count, 2) }
    }

    func testReceiptFailureReportsThatHealthSaveAlreadyHappened() async throws {
        let client = FakeHealthClient()
        let receipts = MemoryReceipts()
        receipts.failOnSet = true
        let writer = HealthKitWriter(client: client, receipts: receipts)
        let outcome = try await writer.write(TestSession.make())
        XCTAssertEqual(outcome, .savedButReceiptFailed)
        XCTAssertEqual(client.saveCalls, 1)
    }

    func testSaveFailureDoesNotCreateReceipt() async throws {
        let client = FakeHealthClient()
        client.failSave = true
        let receipts = MemoryReceipts()
        let session = try TestSession.make()
        let writer = HealthKitWriter(client: client, receipts: receipts)
        do { _ = try await writer.write(session); XCTFail("Expected save failure") }
        catch { XCTAssertNil(try receipts.receipt(for: session.syncIdentifier)) }
    }
}
