# OCLEANY3X: evidenze, confronto revisioni e limiti

Aggiornamento 2026-11-10, senza scansioni, connessioni o scritture BLE da parte
dell'agente. Analizzati i sorgenti locali fissati sotto e la PR upstream #145.

## Osservazioni ricevute dall'utente

Output del comando read riportato nella chat: modello DIS **OCLEANY3X**,
Firmware Revision 2A26 **1.0**, Software Revision 2A28 **1.0.0.36**, batteria
83%. Questi sono risultati hardware riferiti dall'utente, non catture ottenute
dall'agente. Revisione hardware redatta dal filtro: contenuto non disponibile.
Non sono stati salvati indirizzi, token, nomi BLE o payload pubblicitari.
La discovery GATT completa e le funzioni vendor restano da verificare.

## Correzione confronto nel laboratorio

Prima si emetteva il confronto subito dopo 2A26, ignorando 2A28. Ora si emette
un solo target_comparison dopo tutte le letture consentite. Le due revisioni
restano campi distinti: nessuna viene rinominata o assunta come firmware reale.

- matches=true se almeno una revisione numerica coincide esattamente con 1.0.0.36.
- matching_fields indica firmware, software o entrambi; observed_revisions
  conserva le sole versioni numeriche valide effettivamente lette.
- matches=false se esistono revisioni numeriche ma nessuna coincide.
- matches=null se non c'è nessuna revisione numerica disponibile; non è mismatch.
- compatibility rimane unvalidated: confronto di etichette, non validazione TYPE1.

Per il caso riportato: matches=true, matching_fields=[software], revisioni
osservate firmware=1.0 e software=1.0.0.36. Nessuna richiesta BLE aggiunta.
Lo schema resta 1: i campi nuovi sono aggiuntivi e matches ora può essere null.

## deniskie/ha-oclean-integration

Commit locale studiato: `8b831484c92a02372ee88b1828148ab9552d1007` (MIT).

- `custom_components/oclean_ble/protocol.py`, righe 181-184:
  mappatura **esplicita OCLEANY3X -> TYPE1**. Il commento dice che non è presente
  nel DeviceType dell'APK esaminato; la scelta deriva dall'identificazione del
  dispositivo come X Pro Elite da parte dell'autore della segnalazione #110.
- README, tabella compatibilità: supporto **Partial**, stessa famiglia di
  OCLEANY3P secondo la segnalazione. Non è una convalida completa sul nostro FW.
- CHANGELOG e test_protocol.py confermano l'aggiunta del mapping; quei test
  verificano selezione del profilo, non comportamento fisico del dispositivo.
- [PR #145, unita il 19 settembre 2026](https://github.com/deniskie/ha-oclean-integration/pull/145):
  spiega l'inferenza per famiglia, l'assenza di evidenza dal relativo handler APK
  e l'intento di rimuovere l'avviso modello sconosciuto. La nota su #110 dice
  che il report precede v1.3.4 e invita alla conferma dell'utente. La sola chiusura
  dell'issue non dimostra che score, zone e sessioni siano tutti validati.

La pagina issue #110 non era recuperabile dal lettore web durante lo studio:
non attribuiamo a quel report dettagli non presenti nella PR o nel codice.

## dzikus/esphome-oclean

Commit locale studiato: `e74100f042ccb3a01b9cac8acd2a8f5289488466` (GPL v3).

La ricerca testuale dell'identificativo esatto OCLEANY3X non restituisce
occorrenze nella copia del repository. Tuttavia `components/oclean/oclean_profile.cpp`
contiene il prefisso generico **OCLEANY3 -> PROFILE_TYPE1** (riga 249), e
profile_for_model (righe 262-272) usa strncmp sul prefisso. Quindi OCLEANY3X
viene selezionato come TYPE1 dal codice: è una deduzione verificabile dalla
funzione di dispatch, non un test hardware specifico per Y3X.

Il README indica come prove hardware X Pro Elite OCLEANY3P 1.0.0.30 e
OCLEANY3PD 1.0.0.31; non le estendiamo automaticamente a OCLEANY3X/1.0.0.36.

Fonte fissata:
[oclean_profile.cpp](https://github.com/dzikus/esphome-oclean/blob/e74100f042ccb3a01b9cac8acd2a8f5289488466/components/oclean/oclean_profile.cpp).
La copia locale è stata letta; il lettore web non ha recuperato questa pagina.

## Decisione per OpenBrushLab

TYPE1 è un candidato motivato da entrambi i progetti, con livelli di evidenza
diversi. Manteniamo soltanto scan, discovery e letture standard allowlisted.
Nessun polling upstream eseguito o importato; nessuna subscription, query
vendor, conferma 02 02, cambio orologio, impostazione display o firmware.
Le letture standard riuscite non dimostrano il formato delle sessioni.

Prossimo riscontro utile: inventario GATT del dispositivo, poi confronti offline.
Non è stata trovata in queste evidenze una conferma di upload di testo/immagini
o rendering arbitrario sul display OCLEANY3X.
