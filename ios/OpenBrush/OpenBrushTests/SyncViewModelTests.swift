// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import HealthKit
@testable import OpenBrush

@MainActor
private final class ArchiveMemory: SessionArchivePersistence {
    var value = SessionArchive()
    var failLoad = false
    var failSave = false
    var saves = 0
    func load() throws -> SessionArchive {
        if failLoad { throw OpenBrushError.receiptCorrupted }; return value
    }
    func save(_ archive: SessionArchive) throws {
        if failSave { throw OpenBrushError.localStorageUnavailable }
        value = archive; saves += 1
    }
}

@MainActor
private final class CaptureMemory: OcleanCaptureSource {
    var next = SyntheticSession.capture([])
    var calls = 0
    var cancellations = 0
    func acquire() async throws -> OcleanCaptureEnvelope { calls += 1; return next }
    func cancel() { cancellations += 1 }
}

@MainActor
private final class SyncReceipts: ReceiptStore {
    var values: [String: WriteReceipt] = [:]
    func receipt(for identifier: String) throws -> WriteReceipt? { values[identifier] }
    func set(_ receipt: WriteReceipt, for identifier: String) throws { values[identifier] = receipt }
}

@MainActor
private final class SyncHealth: HealthStoreClient {
    var isAvailable = true
    var writeAuthorization: HealthWriteAuthorization = .authorized
    let sourceBundleIdentifier = "it.imix.openbrush"
    var events: [StoredBrushEvent] = []
    var saves = 0
    var requests = 0
    var beforeSave: (() -> Void)?
    var hidden = false
    func requestAuthorization() async throws { requests += 1; writeAuthorization = .authorized }
    func matching(syncIdentifier: String) async throws -> [StoredBrushEvent] {
        hidden ? [] : events.filter { $0.syncIdentifier == syncIdentifier }
    }
    func overlapping(startUTC: Date, endUTC: Date) async throws -> [StoredBrushEvent] {
        hidden ? [] : events.filter { $0.startUTC < endUTC && $0.endUTC > startUTC }
    }
    func save(_ session: BrushSession) async throws {
        beforeSave?(); saves += 1
        events.removeAll { $0.sourceBundleIdentifier == sourceBundleIdentifier && $0.syncIdentifier == session.syncIdentifier }
        events.append(StoredBrushEvent(id: UUID(), sourceName: "OpenBrush (simulato)",
            sourceBundleIdentifier: sourceBundleIdentifier, startUTC: session.startUTC, endUTC: session.endUTC,
            syncIdentifier: session.syncIdentifier, syncVersion: session.syncVersion,
            timeZoneIdentifier: session.timeZoneIdentifier))
    }
}

@MainActor
final class SyncViewModelTests: XCTestCase {
    func testSimulatedSevenDaysFourteenSessionsEachSavedOnceAcrossRelaunch() async throws {
        let source = CaptureMemory(); let health = SyncHealth(); let storage = ArchiveMemory(); let receipts = SyncReceipts()
        var all: [OcleanTYPE1Record] = []
        for day in 1...7 {
            for hour in [8,20] {
                all.append(SyntheticSession.record(local: String(format: "2026-11-%02dT%02d:00:00", day, hour)))
            }
            // An overlapping rolling window; previously archived records eventually leave it.
            source.next = SyntheticSession.capture(Array(all.suffix(4)),
                at: SyntheticSession.date(String(format: "2026-11-%02dT22:00:00Z", day)))
            let model = SyncViewModel(capture: source, writer: HealthKitWriter(client: health, receipts: receipts), store: storage)
            await model.synchronize(); await model.synchronize()
        }
        XCTAssertEqual(health.saves, 14); XCTAssertEqual(health.events.count, 14)
        XCTAssertEqual(storage.value.sessions.count, 14)
        XCTAssertEqual(Set(health.events.compactMap(\.syncIdentifier)).count, 14)
        XCTAssertTrue(storage.value.sessions.values.allSatisfy { $0.delivery?.state == .verified })
    }

    func testArchiveIsPersistedBeforeHealthWriteAndPendingReceiptRecovers() async throws {
        let source = CaptureMemory(); source.next = SyntheticSession.capture([SyntheticSession.record()])
        let health = SyncHealth(); let storage = ArchiveMemory(); let receipts = SyncReceipts()
        health.beforeSave = {
            XCTAssertEqual(storage.value.sessions.count, 1)
            XCTAssertEqual(storage.value.sessions.values.first?.delivery?.state, .pending)
        }
        let writer = HealthKitWriter(client: health, receipts: receipts)
        let first = SyncViewModel(capture: source, writer: writer, store: storage)
        await first.synchronize()
        let key = try XCTUnwrap(storage.value.sessions.keys.first)
        storage.value.sessions[key]!.delivery?.state = .pending // Simulated interrupted final persistence.
        health.hidden = true
        let relaunched = SyncViewModel(capture: source, writer: writer, store: storage)
        await relaunched.synchronize()
        XCTAssertEqual(health.saves, 1)
        XCTAssertEqual(storage.value.sessions[key]?.delivery?.state, .acceptedUnverified)
    }

    func testFailedOrCorruptStorageNeverWritesHealthOrResetsFile() async {
        let source = CaptureMemory(); source.next = SyntheticSession.capture([SyntheticSession.record()])
        let health = SyncHealth(); let storage = ArchiveMemory()
        storage.failLoad = true
        let corrupt = SyncViewModel(capture: source, writer: HealthKitWriter(client: health, receipts: SyncReceipts()), store: storage)
        await corrupt.synchronize()
        XCTAssertTrue(corrupt.storageBlocked); XCTAssertEqual(source.calls, 0)
        storage.failLoad = false; storage.failSave = true
        let unwritable = SyncViewModel(capture: source, writer: HealthKitWriter(client: health, receipts: SyncReceipts()), store: storage)
        await unwritable.synchronize()
        XCTAssertEqual(health.saves, 0); XCTAssertTrue(unwritable.storageBlocked)
    }

    func testForegroundOnceAndNoBackgroundOrAutomaticRetry() async {
        let source = CaptureMemory(); source.next = SyntheticSession.capture([], complete: false, issue: .connectionUnavailable)
        let model = SyncViewModel(capture: source, writer: HealthKitWriter(client: SyncHealth(), receipts: SyncReceipts()), store: ArchiveMemory())
        await model.enterForeground(); await model.enterForeground()
        XCTAssertEqual(source.calls, 1)
        model.leaveForeground(); await model.synchronize()
        XCTAssertEqual(source.calls, 1); XCTAssertEqual(source.cancellations, 1)
        await model.enterForeground(); XCTAssertEqual(source.calls, 2)
    }

    func testHoldsAndDeniedPermissionPreserveWithoutExport() async {
        let source = CaptureMemory(); source.next = SyntheticSession.capture([SyntheticSession.record(score: 1)])
        let health = SyncHealth(); let storage = ArchiveMemory()
        let model = SyncViewModel(capture: source, writer: HealthKitWriter(client: health, receipts: SyncReceipts()), store: storage)
        await model.synchronize()
        XCTAssertEqual(health.saves, 0); XCTAssertEqual(storage.value.sessions.count, 1)
        health.writeAuthorization = .denied
        source.next = SyntheticSession.capture([SyntheticSession.record(local: "2026-11-10T08:00:00")])
        await model.synchronize()
        XCTAssertEqual(health.saves, 0); XCTAssertEqual(health.requests, 0)
        XCTAssertEqual(storage.value.sessions.count, 2)
    }

    func testExistingFixtureSameSourceOtherIdentityRequiresReview() async throws {
        let source = CaptureMemory(); source.next = SyntheticSession.capture([SyntheticSession.record()])
        let health = SyncHealth(); let storage = ArchiveMemory()
        let fixture = try TestSession.make()
        health.events = [StoredBrushEvent(id: UUID(), sourceName: "OpenBrush prova",
            sourceBundleIdentifier: health.sourceBundleIdentifier, startUTC: fixture.startUTC,
            endUTC: fixture.endUTC, syncIdentifier: fixture.syncIdentifier, syncVersion: 1,
            timeZoneIdentifier: "Europe/Rome")]
        let model = SyncViewModel(capture: source, writer: HealthKitWriter(client: health, receipts: SyncReceipts()), store: storage)
        await model.synchronize()
        XCTAssertEqual(health.saves, 0)
        let id = try XCTUnwrap(model.sessions.first?.id)
        XCTAssertTrue(model.sessions[0].reviewReasons.contains(.overlappingHealthEvent))
        XCTAssertEqual(model.reviewEvents[id]?.count, 1)
        await model.review(id: id) // No implicit approval.
        XCTAssertEqual(health.saves, 0)
    }

    func testExplicitVariantSelectionChangesVersionWithoutAnotherIdentity() async throws {
        let source = CaptureMemory(); let initial = SyntheticSession.record()
        source.next = SyntheticSession.capture([initial])
        let health = SyncHealth(); let storage = ArchiveMemory()
        let model = SyncViewModel(capture: source, writer: HealthKitWriter(client: health, receipts: SyncReceipts()), store: storage)
        await model.synchronize()
        let changed = SyntheticSession.record(duration: 30, score: 37)
        source.next = SyntheticSession.capture([changed], at: SyntheticSession.date("2026-11-12T12:00:00Z"))
        await model.synchronize()
        XCTAssertEqual(health.saves, 1)
        let id = try XCTUnwrap(model.sessions.first?.id)
        model.selectVariant(id: id, fingerprint: changed.recordFingerprint)
        await model.review(id: id)
        XCTAssertEqual(health.saves, 2); XCTAssertEqual(health.events.count, 1)
        XCTAssertEqual(health.events.first?.syncVersion, 2)
        XCTAssertEqual(health.events.first?.endUTC.timeIntervalSince(health.events.first!.startUTC), 30)
    }

    func testWriterDoesNotStartSaveAfterForegroundGateCloses() async throws {
        let health = SyncHealth()
        let writer = HealthKitWriter(client: health, receipts: SyncReceipts())
        do {
            _ = try await writer.write(TestSession.make(), shouldProceed: { false })
            XCTFail("La scrittura deve essere interrotta prima di save")
        } catch OpenBrushError.operationCancelled { }
        XCTAssertEqual(health.saves, 0)
    }

    func testLiveSampleDoesNotCarryTestFixtureMarker() throws {
        let archive = try SyntheticSession.archive([SyntheticSession.record()])
        let session = try XCTUnwrap(archive.sessions.values.first).healthSession()
        let sample = try HealthKitClient.makeSample(session)
        XCTAssertNil(sample.metadata?["it.imix.openbrush.fixture"])
        XCTAssertEqual(sample.metadata?[HKMetadataKeySyncIdentifier] as? String, session.syncIdentifier)
    }
}
