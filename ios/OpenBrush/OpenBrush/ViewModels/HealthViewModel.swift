// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

@MainActor
final class HealthViewModel: ObservableObject {
    @Published private(set) var status = "Nessuna scrittura eseguita. Autorizza Salute per iniziare."
    @Published private(set) var isBusy = false
    @Published private(set) var foreignEvents: [StoredBrushEvent] = []
    @Published var asksForeignConfirmation = false
    private let writer: HealthKitWriter
    private let fixture: () throws -> BrushSession

    init(writer: HealthKitWriter, fixture: @escaping () throws -> BrushSession = { try TestSession.make() }) {
        self.writer = writer
        self.fixture = fixture
    }

    static func live() -> HealthViewModel {
        HealthViewModel(writer: HealthKitWriter(client: HealthKitClient(), receipts: FileReceiptStore()))
    }

    func authorize() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await writer.requestAuthorization()
            let preview = try await writer.preflight(fixture())
            foreignEvents = preview.foreignEvents
            switch writer.client.writeAuthorization {
            case .authorized:
                status = "Richiesta completata. Scrittura autorizzata; nessun evento scritto."
            case .denied:
                status = "Scrittura non autorizzata. Puoi modificare i permessi in Salute."
            case .notDetermined:
                status = "Permesso di scrittura non ancora deciso. Nessun evento scritto."
            }
        } catch { status = error.localizedDescription }
    }

    func writeFixture(allowForeignOverlap: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let outcome = try await writer.write(fixture(), allowForeignOverlap: allowForeignOverlap)
            foreignEvents = writer.lastPreflight?.foreignEvents ?? []
            switch outcome {
            case .written(let version): status = "Scritto e verificato: un evento OpenBrush, versione \(version)."
            case .alreadyPresent(let version): status = "Già presente in Salute, versione \(version). Nessun nuovo salvataggio."
            case .versionUpdated(let old, let new): status = "Versione aggiornata da \(old) a \(new). Verificato un solo evento OpenBrush."
            case .alreadySubmittedLocally(let version):
                status = "Già inviato, versione \(version), secondo la ricevuta locale. Verifica in Salute: potrebbe non essere leggibile o essere stato rimosso. Nessun nuovo invio."
            case .submittedNotVerified(let version, let wasUpdate):
                status = "\(wasUpdate ? "Aggiornamento" : "Salvataggio") accettato da Salute, versione \(version). Presenza non verificabile con i dati leggibili."
            case .foreignConfirmationRequired:
                status = "Sono visibili eventi di altre sorgenti. Scrittura sospesa in attesa della tua scelta."
                asksForeignConfirmation = true
            case .savedButReceiptFailed:
                status = "Salute ha accettato il salvataggio, ma la ricevuta locale non è stata salvata. Verifica Salute prima di riprovare."
            case .saveAcceptedNeedsReview:
                status = "Salvataggio accettato, ma la verifica non conferma un unico evento con la versione richiesta. Controlla Salute; nessuna cancellazione eseguita."
            }
        } catch {
            foreignEvents = writer.lastPreflight?.foreignEvents ?? []
            status = error.localizedDescription
        }
    }
}
