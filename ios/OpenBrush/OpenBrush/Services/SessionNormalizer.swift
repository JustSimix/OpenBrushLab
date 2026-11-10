// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum SessionNormalizer {
    static let offsetMinutes = [-720,-660,-600,-540,-480,-420,-360,-300,-240,-210,-180,-120,-60,0,
                                60,120,180,210,240,270,300,330,345,360,390,420,480,540,570,600,660,720,780]

    struct TimeCheck {
        var startUTC: Date?
        var reasons: Set<SessionReviewReason> = []
        var foldDisambiguated = false
    }

    static func verifyTime(_ record: OcleanTYPE1Record) -> TimeCheck {
        guard let text = record.deviceLocalTimestamp,
              let wallAsUTC = ISO8601DateFormatter().date(from: text + "Z"),
              record.deviceDatetimeRaw.count == 6, record.deviceDatetimeRaw[0] + 2000 >= 2015 else {
            return TimeCheck(reasons: [.invalidDate])
        }
        guard let index = record.timezoneRaw, (1...offsetMinutes.count).contains(index),
              let zone = TimeZone(identifier: "Europe/Rome") else { return TimeCheck(reasons: [.unknownTimezone]) }
        let offset = offsetMinutes[index-1] * 60
        let instant = wallAsUTC.addingTimeInterval(-Double(offset))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let raw = record.deviceDatetimeRaw
        func matches(_ date: Date) -> Bool {
            let c = calendar.dateComponents(in: zone, from: date)
            return [c.year,c.month,c.day,c.hour,c.minute,c.second] ==
                   [raw[0]+2000,raw[1],raw[2],raw[3],raw[4],raw[5]].map(Optional.some)
        }
        // Consider the actual IANA offsets around this day, not today's iPhone offset.
        let nearby = Set([-36,-24,0,24,36].map { zone.secondsFromGMT(for: wallAsUTC.addingTimeInterval(Double($0)*3600)) })
        let valid = Set(nearby.map { wallAsUTC.addingTimeInterval(-Double($0)) }.filter(matches))
        if valid.isEmpty { return TimeCheck(startUTC: instant, reasons: [.nonexistentLocalTime]) }
        if !valid.contains(instant) { return TimeCheck(startUTC: instant, reasons: [.timezoneMismatch]) }
        return TimeCheck(startUTC: instant, foldDisambiguated: valid.count == 2)
    }

    static func identity(deviceKey: String, record: OcleanTYPE1Record) throws -> String {
        if record.kind == "full-record", let local = record.deviceLocalTimestamp {
            // Same array and namespace as Python, even for an unknown wire index.
            let timezone: Any = record.timezoneRaw.map { $0 as Any } ?? NSNull()
            let identity: [Any] = [deviceKey, local, timezone, record.schemeRaw]
            return try SessionHash.canonical(["openbrushlab-session-v1", identity])
        }
        return try SessionHash.canonical(["openbrushlab-session-v1", [deviceKey,"unresolved",record.recordFingerprint]])
    }

    static func refresh(_ entry: inout ArchivedBrushSession, boundDeviceKey: String?) {
        var reasons = Set<SessionReviewReason>()
        if entry.deviceKey != boundDeviceKey { reasons.insert(.differentDevice) }
        if entry.variants.count > 1 && entry.selectedFingerprint == nil { reasons.insert(.conflictingVariants) }
        guard let record = entry.selectedRecord else {
            entry.reviewReasons = reasons.sorted { $0.rawValue < $1.rawValue }
            entry.startUTC = nil; entry.endUTC = nil
            return
        }
        if record.kind != "full-record" { reasons.insert(.incompleteRecord) }
        if !entry.confirmedFingerprints.contains(record.recordFingerprint) { reasons.insert(.incompleteTransport) }
        if record.scoreRaw == 1 { reasons.insert(.voidScore) }
        if record.actualDurationCandidateS <= 14 { reasons.insert(.tooShort) }
        if !(1...7200).contains(record.actualDurationCandidateS) || !(1...7200).contains(record.scheduledDurationS)
            || record.actualDurationCandidateS > record.scheduledDurationS { reasons.insert(.durationInvalid) }
        let time = verifyTime(record)
        reasons.formUnion(time.reasons)
        entry.startUTC = time.startUTC
        entry.endUTC = time.startUTC?.addingTimeInterval(Double(record.actualDurationCandidateS))
        if let end = entry.endUTC {
            // Earliest successful observation is a bound; old historical age is NOT drift.
            let captures = entry.sources.values.filter { $0.transportCompleted && $0.fingerprints.contains(record.recordFingerprint) }.map(\.capturedAt)
            if let capturedAt = captures.min(), end.timeIntervalSince(capturedAt) > 5 {
                reasons.insert(.futureEnd)
                if end.timeIntervalSince(capturedAt) > 120 { reasons.insert(.clockDrift) }
            }
        }
        if let drift = entry.estimatedClockDriftSeconds, !drift.isFinite || abs(drift) > 120 { reasons.insert(.clockDrift) }
        if entry.delivery?.state == .needsReview { reasons.insert(.deliveryUncertain) }
        // Overlap is removed only by an explicit user decision or a successful fresh preflight.
        if entry.reviewReasons.contains(.overlappingHealthEvent) { reasons.insert(.overlappingHealthEvent) }
        entry.reviewReasons = reasons.sorted { $0.rawValue < $1.rawValue }
    }

    static func warnings(for capture: OcleanCaptureEnvelope, archive: SessionArchive) -> [SyncWarning] {
        var warnings: [SyncWarning] = []
        if capture.issue == .connectionUnavailable {
            warnings.append(.init(code: "coexistence", message: "Connessione non riuscita: chiudi l'app Oclean e scollega gli altri central. Il dispositivo puÃƒÆ’Ã‚Â² rifiutare un secondo central o richiedere un'associazione giÃƒÆ’Ã‚Â  esistente; non viene forzato il pairing."))
        }
        if capture.issue == .securityReported {
            warnings.append(.init(code: "bonding", message: "Il sistema segnala un problema di associazione. Questo iPhone potrebbe non essere accettato come secondo central. Chiudi Oclean; nessun pairing forzato."))
        }
        if capture.result.status == .zeroCount {
            warnings.append(.init(code: "empty-ring", message: "L'anello non offre uno storico completo. Chiudi l'app Oclean: potrebbe aver confermato le sessioni o tenere occupata la connessione. Conteggio zero non dimostra da solo che la memoria sia vuota."))
        }
        if capture.result.declaredCount == 32 && capture.transportCompleted && capture.result.status == .complete {
            let starts = capture.result.records.compactMap { record -> Date? in
                let check = verifyTime(record)
                return check.reasons.isEmpty ? check.startUTC : nil
            }
            let previous = archive.sessions.values.filter {
                $0.deviceKey == capture.deviceKey && $0.delivery?.state == .verified
            }.compactMap(\.startUTC).max()
            if starts.count != 32 {
                warnings.append(.init(code: "ring-date-coverage", message: "Anello pieno con date non attendibili: non ÃƒÆ’Ã‚Â¨ possibile verificare tutta la copertura dello storico."))
            } else if let previous, let oldest = starts.min(), oldest > previous {
                warnings.append(.init(code: "ring-loss", message: "Possibile perdita di dati: l'anello ÃƒÆ’Ã‚Â¨ pieno e il record piÃƒÆ’Ã‚Â¹ vecchio ÃƒÆ’Ã‚Â¨ successivo all'ultimo giÃƒÆ’Ã‚Â  sincronizzato."))
            } else if previous == nil {
                warnings.append(.init(code: "first-full-ring", message: "Primo storico con anello pieno: eventuali sessioni precedenti non sono verificabili."))
            }
        }
        if capture.estimatedClockDriftSeconds == nil && archive.clockReferences[capture.deviceKey] == nil {
            warnings.append(.init(code: "clock-reference", message: "Deriva non misurabile senza un riferimento temporale indipendente. Le date sono controllate, ma l'etÃƒÆ’Ã‚Â  di una sessione non misura la deriva."))
        }
        return warnings
    }

    static func ingest(_ capture: OcleanCaptureEnvelope, into archive: inout SessionArchive) throws {
        let captureWarnings = warnings(for: capture, archive: archive)
        archive.warnings = archive.warnings.filter { $0.code == "ring-loss" }
        archive.warnings += captureWarnings.filter { new in !archive.warnings.contains(where: { $0.code == new.code }) }
        if archive.captures[capture.id] != nil { return }
        if archive.boundDeviceKey == nil, capture.transportCompleted, capture.result.status == .complete {
            archive.boundDeviceKey = capture.deviceKey
        }
        archive.captures[capture.id] = CaptureAudit(deviceKey: capture.deviceKey, capturedAt: capture.capturedAt,
            status: capture.result.status, declaredCount: capture.result.declaredCount,
            recordFingerprints: capture.result.records.map(\.recordFingerprint),
            transportCompleted: capture.transportCompleted, issue: capture.issue)
        for record in capture.result.records {
            let key = try identity(deviceKey: capture.deviceKey, record: record)
            var entry = archive.sessions[key] ?? ArchivedBrushSession(id: key, deviceKey: capture.deviceKey,
                variants: [:], sources: [:], confirmedFingerprints: [], firstSeen: capture.capturedAt, lastSeen: capture.capturedAt)
            if entry.variants[record.recordFingerprint] == nil && !entry.variants.isEmpty { entry.selectedFingerprint = nil }
            entry.variants[record.recordFingerprint] = record
            let confirmed = capture.transportCompleted && capture.result.status == .complete
            if confirmed { entry.confirmedFingerprints.insert(record.recordFingerprint) }
            var observed = entry.sources[capture.id]?.fingerprints ?? []
            observed.insert(record.recordFingerprint)
            entry.sources[capture.id] = SessionSourceStamp(capturedAt: capture.capturedAt, transportCompleted: confirmed, fingerprints: observed)
            entry.firstSeen = min(entry.firstSeen, capture.capturedAt); entry.lastSeen = max(entry.lastSeen, capture.capturedAt)
            if entry.estimatedClockDriftSeconds == nil {
                entry.estimatedClockDriftSeconds = capture.estimatedClockDriftSeconds ?? archive.clockReferences[capture.deviceKey]?.driftSeconds
            }
            refresh(&entry, boundDeviceKey: archive.boundDeviceKey)
            if entry.canExport {
                let session = try entry.healthSession()
                if let old = entry.lastProposedPayloadHash, old != session.payloadHash { entry.syncVersion += 1 }
                entry.lastProposedPayloadHash = session.payloadHash
            }
            archive.sessions[key] = entry
        }
        if archive.sessions.values.contains(where: { $0.reviewReasons.contains(.clockDrift) }) {
            archive.warnings.append(.init(code: "clock-drift", message: "Alcune sessioni hanno una deriva stimata oltre 2 minuti: restano in revisione. Nessuna correzione dell'orologio inviata."))
        }
    }
}
