// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct ContentView: View {
    @StateObject private var model = SyncViewModel.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Sincronizza") { Task { await model.synchronize() } }
                        .disabled(model.isBusy || model.storageBlocked)
                    Button("Autorizza Salute") { Task { await model.authorize() } }
                        .disabled(model.isBusy || model.storageBlocked)
                    Text(model.status).accessibilityIdentifier("syncStatus")
                    if let bluetooth = model.bluetooth { BluetoothProgress(client: bluetooth) }
                } footer: {
                    Text("Solo in primo piano. Chiudi Oclean e risveglia il display. Nessuna modifica dellâ€™orologio o dei programmi.")
                }
                if !model.archive.warnings.isEmpty {
                    Section("Avvisi") {
                        ForEach(model.archive.warnings) { warning in
                            Label(warning.message, systemImage: "exclamationmark.triangle")
                        }
                    }
                }
                Section("Sessioni conservate") {
                    if model.sessions.isEmpty { Text("Nessuna sessione archiviata.") }
                    ForEach(model.sessions) { session in
                        NavigationLink {
                            SessionReviewView(model: model, id: session.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                if let start = session.startUTC {
                                    Text(start.formatted(date: .abbreviated, time: .standard))
                                } else { Text("Data non attendibile") }
                                Text(session.stateText).font(.headline)
                                if let record = session.representativeRecord {
                                    Text("Durata: \(record.actualDurationCandidateS) secondi")
                                }
                                ForEach(session.reviewReasons, id: \.self) { Text($0.message).font(.caption) }
                                Text("Rivedi sessione").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("OpenBrush")
            .task { await model.enterForeground() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.enterForeground() } }
                else if phase == .background { model.leaveForeground() }
            }
        }
    }
}

private struct BluetoothProgress: View {
    @ObservedObject var client: OcleanBLEClient
    var body: some View {
        if client.isBusy { ProgressView(client.status) }
    }
}

private struct SessionReviewView: View {
    @ObservedObject var model: SyncViewModel
    let id: String
    @State private var phoneStart = Date()
    @State private var measuredSeconds = ""
    private var measuredPhoneStart: Date? {
        guard let seconds = Int(measuredSeconds), (0...59).contains(seconds),
              let minute = Calendar.current.date(bySetting: .second, value: 0, of: phoneStart) else { return nil }
        return minute.addingTimeInterval(Double(seconds))
    }
    @State private var confirmingClock = false
    @State private var confirmingOverlap = false

    var body: some View {
        Form {
            if let entry = model.archive.sessions[id] {
                Section("Stato") {
                    Text(entry.stateText)
                    ForEach(entry.reviewReasons, id: \.self) { Text($0.message) }
                    Text("Nessuna data viene interpolata. La revisione non forza lâ€™esportazione di dati non attendibili.")
                    if entry.delivery != nil && !entry.reviewReasons.isEmpty {
                        Text("Una versione precedente puÃ² essere giÃ  in Salute. Non viene cancellata automaticamente.")
                    }
                }
                Section("Varianti conservate") {
                    ForEach(entry.variants.keys.sorted(), id: \.self) { fingerprint in
                        if let record = entry.variants[fingerprint] {
                            VStack(alignment: .leading) {
                                Text(record.deviceLocalTimestamp ?? "Data non valida")
                                Text("Programma \(record.schemeRaw), prevista \(record.scheduledDurationS)s, effettiva candidata \(record.actualDurationCandidateS)s, punteggio \(record.scoreRaw.map(String.init) ?? "assente")")
                                if entry.variants.count > 1 {
                                    Button(entry.selectedFingerprint == fingerprint ? "Variante selezionata" : "Usa questa variante verificata") {
                                        model.selectVariant(id: id, fingerprint: fingerprint)
                                    }.disabled(model.isBusy)
                                }
                            }
                        }
                    }
                }
                Section("Controllo dellâ€™orologio") {
                    Text("Inserisci solo lâ€™inizio di questa pulizia annotato indipendentemente sullâ€™iPhone. Non usare lâ€™ora visualizzata dallo spazzolino o una stima a memoria.")
                    DatePicker("Inizio misurato sullâ€™iPhone", selection: $phoneStart, displayedComponents: [.date, .hourAndMinute])
                    TextField("Secondi misurati (0–59)", text: $measuredSeconds).keyboardType(.numberPad)
                    Text("Lascia vuoto se non hai misurato i secondi. Nessun riferimento viene inventato.")
                    Button("Registra riferimento misurato") { confirmingClock = true }
                        .disabled(model.isBusy || entry.startUTC == nil || measuredPhoneStart == nil)
                }
                Section("Revisione") {
                    ForEach(model.reviewEvents[id] ?? []) { event in
                        VStack(alignment: .leading) {
                            Text("Evento giÃ  presente: " + event.sourceName)
                            Text(event.startUTC.formatted(date: .abbreviated, time: .standard))
                        }
                    }
                    Button("Rivedi e verifica in Salute") { Task { await model.review(id: id) } }
                        .disabled(model.isBusy || model.storageBlocked)
                    if !(model.reviewEvents[id] ?? []).isEmpty {
                        Button("Conferma invio nonostante la sovrapposizione") { confirmingOverlap = true }
                            .disabled(model.isBusy || model.storageBlocked)
                    }
                    Text(model.status)
                }
            }
        }
        .navigationTitle("Rivedi sessione")
        .confirmationDialog("Confermi che lâ€™inizio Ã¨ stato misurato indipendentemente?", isPresented: $confirmingClock) {
            Button("Confermo il riferimento") {
                if let measuredPhoneStart { model.noteClockReference(id: id, phoneStart: measuredPhoneStart) }
            }
        }
        .confirmationDialog("PuÃ² creare una seconda pulizia nello stesso intervallo. Nessun evento esistente verrÃ  cancellato.", isPresented: $confirmingOverlap) {
            Button("Invia anche questa sessione") { Task { await model.review(id: id, confirmOverlap: true) } }
        }
    }
}
