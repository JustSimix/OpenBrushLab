// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum TestSession {
    // Change ONLY this constant to 2, rebuild and install over the same app
    // to test HealthKit version replacement. Do not change bundle ID or identity.
    static let syncVersion = 1

    // PUBLIC SYNTHETIC key, deliberately not the real brush's .device-key.
    // This fixture repeats the observed interval, but is a separately identified TEST event.
    static let publicSyntheticDeviceKey = String(repeating: "0", count: 64)

    static func make(version: Int = syncVersion) throws -> BrushSession {
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: "2026-11-10T10:37:15Z"),
              let end = formatter.date(from: "2026-11-10T10:38:30Z") else {
            throw OpenBrushError.invalidSession
        }
        let identifier = try SynchronizationIdentity.make(
            deviceKey: publicSyntheticDeviceKey,
            deviceLocalTimestamp: "2026-11-10T11:37:15",
            timezoneWireIndex: 15, scheme: 231)
        return try BrushSession(startUTC: start, endUTC: end, durationSeconds: 75,
                                timeZoneIdentifier: "Europe/Rome",
                                syncIdentifier: identifier, syncVersion: version, isTestFixture: true)
    }
}
