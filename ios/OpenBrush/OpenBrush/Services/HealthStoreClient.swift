// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum HealthWriteAuthorization: Equatable { case notDetermined, denied, authorized }

struct StoredBrushEvent: Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceName: String
    let sourceBundleIdentifier: String
    let startUTC: Date
    let endUTC: Date
    let syncIdentifier: String?
    let syncVersion: Int?
    let timeZoneIdentifier: String?

    func matchesPayload(_ session: BrushSession) -> Bool {
        abs(startUTC.timeIntervalSince(session.startUTC)) < 0.001 &&
        abs(endUTC.timeIntervalSince(session.endUTC)) < 0.001 &&
        timeZoneIdentifier == session.timeZoneIdentifier
    }
}

@MainActor
protocol HealthStoreClient: AnyObject {
    var isAvailable: Bool { get }
    var writeAuthorization: HealthWriteAuthorization { get }
    var sourceBundleIdentifier: String { get }
    func requestAuthorization() async throws
    func matching(syncIdentifier: String) async throws -> [StoredBrushEvent]
    func overlapping(startUTC: Date, endUTC: Date) async throws -> [StoredBrushEvent]
    func save(_ session: BrushSession) async throws
}
