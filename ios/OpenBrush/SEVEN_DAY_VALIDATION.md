# Collaudo iPhone — sette giorni reali (da eseguire)

Il test simulato non soddisfa questo criterio reale. Build, XCTest, autorizzazione
HealthKit, radio e sostituzione di versione vanno prima verificati sul Mac/iPhone.
Conservare l'installazione e lo stesso bundle ID, senza disinstallare/reset.
Non includere diario reale o archivio con dati personali nel repository.

Preparazione: chiudere Oclean e altri central, annotare versione iOS/Xcode e SW,
autorizzare lettura e scrittura Salute. Eventuali fixture già in Salute vanno
riconosciute durante la revisione; nessuna cancellazione automatica.

Per ogni pulizia annotare su un diario PRIVATO: data/ora iPhone realmente
misurata, durata/stop/pausa misurati o «non misurato», display, apertura eventuale
di Oclean, esito OpenBrush, fonte/inizio/fine osservati in Salute. Non inventare
i secondi mancanti. Aprire OpenBrush dopo la pulizia, risvegliando il display.
Ripetere Sincronizza sullo stesso anello; chiudere e riaprire almeno una volta.
Verificare UNA sola pulizia per identità, intervallo corretto, archivio mantenuto.

| Giorno | Pulizie fisiche annotate | Eventi unici in Salute | Hold / avvisi e motivi | Secondo sync senza nuovi eventi | Esito |
|---|---|---|---|---|---|
| 1 | da compilare | | | | |
| 2 | da compilare | | | | |
| 3 | da compilare | | | | |
| 4 | da compilare | | | | |
| 5 | da compilare | | | | |
| 6 | da compilare | | | | |
| 7 | da compilare | | | | |

Un hold rende la prova incompleta finché non è spiegato; non forzare date invalide
per ottenere un esito verde. Verificare anche che il ritorno di un anello vuoto
non cancelli lo storico locale. Non provocare in radio clock errati, overflow o
bonding: i casi di avviso si simulano con XCTest.

Prima del diario: Product > Test, tutti i test verdi; prova versione maggiore con
HealthKitWriterTests e conferma sul telefono con identico syncIdentifier. Se un
errore nativo appare, riportare il primo errore Xcode e la versione SDK. La fase
reale può iniziare soltanto dopo build/test e prima sincronizzazione riusciti.
