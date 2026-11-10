// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct HealthPreflight: Equatable {
    let ownMatches: [StoredBrushEvent]
    let foreignEvents: [StoredBrushEvent]
    var otherIdentityEvents: [StoredBrushEvent] = []
    var reviewEvents: [StoredBrushEvent] { foreignEvents + otherIdentityEvents }
}

enum WriteOutcome: Equatable {
    case written(version: Int)
    case alreadyPresent(version: Int)
    case versionUpdated(from: Int, to: Int)
    case alreadySubmittedLocally(version: Int)
    case submittedNotVerified(version: Int, wasUpdate: Bool)
    case foreignConfirmationRequired([StoredBrushEvent])
    case savedButReceiptFailed
    case saveAcceptedNeedsReview
}

@MainActor
final class HealthKitWriter {
    let client: any HealthStoreClient
    private let receipts: any ReceiptStore
    private var isWriting = false
    private(set) var lastPreflight: HealthPreflight?

    init(client: any HealthStoreClient, receipts: any ReceiptStore) {
        self.client = client
        self.receipts = receipts
    }

    func requestAuthorization() async throws {
        guard client.isAvailable else { throw OpenBrushError.healthUnavailable }
        try await client.requestAuthorization()
    }

    func preflight(_ session: BrushSession) async throws -> HealthPreflight {
        let matches: [StoredBrushEvent]
        let overlaps: [StoredBrushEvent]
        do {
            matches = try await client.matching(syncIdentifier: session.syncIdentifier)
            overlaps = try await client.overlapping(startUTC: session.startUTC, endUTC: session.endUTC)
        } catch { throw OpenBrushError.queryFailed }
        let ownSource = client.sourceBundleIdentifier
        let own = matches.filter { $0.sourceBundleIdentifier == ownSource && $0.syncIdentifier == session.syncIdentifier }
        // Include a foreign sync-id match even if outside the requested interval.
        var seen = Set<UUID>()
        let foreign = (matches + overlaps).filter {
            $0.sourceBundleIdentifier != ownSource && seen.insert($0.id).inserted
        }.sorted { $0.startUTC < $1.startUTC }
        let otherIdentity = overlaps.filter {
            $0.sourceBundleIdentifier == ownSource && $0.syncIdentifier != session.syncIdentifier
        }
        let value = HealthPreflight(ownMatches: own, foreignEvents: foreign, otherIdentityEvents: otherIdentity)
        lastPreflight = value
        return value
    }

    func write(_ session: BrushSession, allowForeignOverlap: Bool = false,
               shouldProceed: () -> Bool = { true }) async throws -> WriteOutcome {
        guard !isWriting else { throw OpenBrushError.busy }
        isWriting = true
        defer { isWriting = false }
        guard client.isAvailable else { throw OpenBrushError.healthUnavailable }
        guard client.writeAuthorization == .authorized else { throw OpenBrushError.writeNotAuthorized }
        let preview = try await preflight(session) // Always query BEFORE a save.
        guard preview.ownMatches.count <= 1 else { throw OpenBrushError.conflictingSamples }
        let existing = preview.ownMatches.first
        if let existing, existing.syncVersion == nil || (existing.syncVersion ?? 0) < 1 {
            throw OpenBrushError.conflictingSamples
        }
        let receipt = try receipts.receipt(for: session.syncIdentifier)
        if let version = existing?.syncVersion, version > session.syncVersion {
            return .alreadyPresent(version: version) // Never downgrade.
        }
        if let receipt, receipt.version > session.syncVersion {
            return .alreadySubmittedLocally(version: receipt.version)
        }
        if let existing, existing.syncVersion == session.syncVersion {
            guard existing.matchesPayload(session) else { throw OpenBrushError.sameVersionDifferentPayload }
            return .alreadyPresent(version: session.syncVersion)
        }
        if let receipt, receipt.version == session.syncVersion {
            guard receipt.payloadHash == session.payloadHash else { throw OpenBrushError.sameVersionDifferentPayload }
            // Read denial and user deletion cannot be reliably distinguished.
            // No automatic recreation of a previously submitted fixture.
            return .alreadySubmittedLocally(version: receipt.version)
        }
        if !preview.reviewEvents.isEmpty && !allowForeignOverlap {
            return .foreignConfirmationRequired(preview.reviewEvents)
        }
        let oldVersion = max(existing?.syncVersion ?? 0, receipt?.version ?? 0)
        guard shouldProceed() else { throw OpenBrushError.operationCancelled }
        try await client.save(session) // Sync metadata lets HealthKit replace our older version.
        do {
            try receipts.set(WriteReceipt(version: session.syncVersion, payloadHash: session.payloadHash),
                             for: session.syncIdentifier)
        } catch { return .savedButReceiptFailed } // Save succeeded; do not claim nothing was written.
        let visible: [StoredBrushEvent]
        do {
            let readback = try await client.matching(syncIdentifier: session.syncIdentifier)
            visible = readback.filter { $0.sourceBundleIdentifier == client.sourceBundleIdentifier }
        } catch { return .submittedNotVerified(version: session.syncVersion, wasUpdate: oldVersion > 0) }
        if visible.isEmpty {
            return .submittedNotVerified(version: session.syncVersion, wasUpdate: oldVersion > 0)
        }
        guard visible.count == 1, visible[0].syncVersion == session.syncVersion,
              visible[0].matchesPayload(session) else { return .saveAcceptedNeedsReview }
        return oldVersion > 0 ? .versionUpdated(from: oldVersion, to: session.syncVersion)
                             : .written(version: session.syncVersion)
    }
}
