// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct OcleanCaptureView: View {
    @StateObject private var client = OcleanBLEClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Chiudi l’app Oclean, avvicina lo spazzolino e risveglia il display. Non serve avviare il motore.")
                Button("Leggi sessioni") { client.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(client.isBusy)
                if client.isBusy { ProgressView("Acquisizione in corso…") }
                Text(client.status).accessibilityIdentifier("ocleanCaptureStatus")
                Text("Notifiche ricevute: \(client.notificationCount). Byte ricevuti: \(client.receivedBytes).")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Le sessioni lette non vengono salvate automaticamente in Salute.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let result = client.lastResult {
                    ForEach(Array(result.records.enumerated()), id: \.offset) { item in
                        let record = item.element
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.deviceLocalTimestamp ?? "Data dello spazzolino non attendibile")
                                Text("Durata letta: \(record.actualDurationCandidateS) s · Programma: \(record.scheduledDurationS) s")
                                if let score = record.scoreRaw {
                                    Text(score == 255 ? "Punteggio non disponibile" : "Punteggio grezzo: \(score)")
                                }
                                if !record.issues.isEmpty { Text("Dati da verificare").foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Sessioni Oclean")
        .onDisappear { client.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { client.cancel() }
        }
    }
}
