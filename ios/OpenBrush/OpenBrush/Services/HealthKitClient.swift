// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import HealthKit

@MainActor
final class HealthKitClient: HealthStoreClient {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var sourceBundleIdentifier: String { HKSource.default().bundleIdentifier }
    var writeAuthorization: HealthWriteAuthorization {
        guard let type = HKObjectType.categoryType(forIdentifier: .toothbrushingEvent) else { return .denied }
        switch store.authorizationStatus(for: type) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private func brushingType() throws -> HKCategoryType {
        guard isAvailable, let type = HKObjectType.categoryType(forIdentifier: .toothbrushingEvent) else {
            throw OpenBrushError.healthUnavailable
        }
        return type
    }

    func requestAuthorization() async throws {
        let type = try brushingType()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: Set<HKSampleType>([type]), read: Set<HKObjectType>([type])) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: OpenBrushError.authorizationFailed) }
            }
        }
        // Successful completion does NOT reveal whether read access was granted.
    }

    func matching(syncIdentifier: String) async throws -> [StoredBrushEvent] {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                   operatorType: .equalTo, value: syncIdentifier)
        return try await query(predicate: predicate)
    }

    func overlapping(startUTC: Date, endUTC: Date) async throws -> [StoredBrushEvent] {
        let predicate = HKQuery.predicateForSamples(withStart: startUTC, end: endUTC, options: [])
        return try await query(predicate: predicate)
    }

    private func query(predicate: NSPredicate) async throws -> [StoredBrushEvent] {
        let type = try brushingType()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[StoredBrushEvent], Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let events = (samples as? [HKCategorySample] ?? []).map { sample in
                    StoredBrushEvent(id: sample.uuid,
                                     sourceName: sample.sourceRevision.source.name,
                                     sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                                     startUTC: sample.startDate, endUTC: sample.endDate,
                                     syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                                     syncVersion: (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue,
                                     timeZoneIdentifier: sample.metadata?[HKMetadataKeyTimeZone] as? String)
                }
                continuation.resume(returning: events)
            }
            store.execute(query)
        }
    }

    func save(_ session: BrushSession) async throws {
        _ = try brushingType()
        guard writeAuthorization == .authorized else { throw OpenBrushError.writeNotAuthorized }
        let sample = try Self.makeSample(session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(sample) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: OpenBrushError.saveFailed) }
            }
        }
    }

    // Pure sample construction, inspectable in unit tests without touching HealthKit storage.
    static func makeSample(_ session: BrushSession) throws -> HKCategorySample {
        guard let type = HKObjectType.categoryType(forIdentifier: .toothbrushingEvent) else {
            throw OpenBrushError.healthUnavailable
        }
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: session.syncIdentifier,
            HKMetadataKeySyncVersion: NSNumber(value: session.syncVersion),
            HKMetadataKeyTimeZone: session.timeZoneIdentifier
        ]
        if session.isTestFixture { metadata["it.imix.openbrush.fixture"] = NSNumber(value: true) }
        return HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                start: session.startUTC, end: session.endUTC, metadata: metadata)
    }
}
