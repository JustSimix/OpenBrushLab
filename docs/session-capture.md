# Cattura sessioni: pronta per prova controllata

Preparata il 2026-11-10. NON ancora eseguita sullo spazzolino.
Modello consentito: OCLEANY3X con Software Revision DIS 1.0.0.36.

## Confine delle operazioni

scan/gatt/read restano senza scritture e senza subscription.
capture-sessions è un comando separato e richiede --allow-session-query.
Senza il flag termina prima di scansioni, connessioni o creazione di catture.

La cattura:
1. cerca il dispositivo; con --index 1 rifiuta più candidati;
2. connette senza pairing esplicito e verifica modello e Software Revision;
3. verifica una sola TX fbb89 scrivibile e una sola RX fbb90 notificabile
   nel servizio Oclean; duplicati, target diversi o revisioni diverse fermano tutto;
4. attiva SOLO le notifiche fbb90;
5. scrive UNA VOLTA 03 07 su fbb89 con response=True;
6. raccoglie per 12 secondi, massimo 256 notifiche/8192 byte, 512 byte per frame;
7. disattiva le notifiche e disconnette; timeout totale predefinito 75 secondi,
   cleanup limitato aggiuntivo fino a 5 secondi per subscription e 10 per disconnessione;
8. decodifica offline il formato candidato, senza ulteriori richieste BLE.

Subscription e stop_notify possono scrivere il CCCD. La sola scrittura
applicativa permessa dal codice è 0307. Non ci sono 0202 (conferma), 0303,
030201, set clock, reset testina, modifica programma, display, pairing o OTA.
Non ci sono retry o fallback a opcode diversi. Il comportamento di 0307 sul
firmware specifico resta da misurare: nessuna garanzia assoluta di assenza di effetti.
Le prove offline verificano la sequenza esatta e i limiti; non validano il firmware.

## Quando eseguirla

Il comando è pronto, ma l'agente non lo lancia finché l'utente non dà il via alla
prova live. Prima acquisizione: nessuna nuova spazzolata. Chiudere l'app Oclean,
avvicinare lo spazzolino e risvegliare il display. Motore spento, non serve agitare
continuamente. Se non viene trovato, fermarsi e coordinare un nuovo risveglio.

Comando live da far lanciare all'agente dopo il via:

```powershell
cd E:\Simix\Projects\OpenBrushLab
.\.venv\Scripts\python.exe -u -m openbrushlab capture-sessions --index 1 --allow-session-query
```

Non è una promessa di download completo: zero notifiche, count=0, formato
sconosciuto o date invalide sono risultati possibili da analizzare, senza tentare
comandi aggiuntivi. Il terminale mostra solo stato, conteggi e nomi file.

## File privati e decoder offline

In captures/ (esclusa da Git):
- sessions-<UTC>-<random>.raw.jsonl: ogni notifica grezza, timestamp di cattura,
  fase prima/dopo richiesta e conferma locale di invio; flush a ogni riga;
- sessions-<UTC>-<random>.decoded.json: risultati candidati e anomalie;
- .device-key: segreto casuale locale per correlare lo stesso spazzolino tra
  catture senza registrarne l'indirizzo. Va conservato localmente e non pubblicato.

Questi file NON sono cifrati né anonimizzati: i byte grezzi potrebbero contenere
identificativi sconosciuti e le sessioni contengono abitudini personali. Il filtro
dei normali log non viene applicato ai raw, che vanno mantenuti privati.
I file non vengono sovrascritti; un nome random evita collisioni.
Una cattura interrotta conserva le righe già salvate, anche senza footer.

Ripetere la decodifica senza BLE:

```powershell
python -m openbrushlab decode-sessions captures\NOME.raw.jsonl --output captures\NOME-replay.json
```

Il decoder riconosce header TYPE1 e record 42 byte, ricompone frammenti anche
dell'header, separa durata programma da durata effettiva candidata e conserva
score/timezone come campi grezzi. Zero-count inline è etichettato frammento,
non storico completo o sessione più recente. Date invalide e durate sospette
richiedono revisione; timestamp non viene automaticamente convertito in UTC.
Ogni record resta healthkit_ready=false. Nessuna esportazione Apple Health.

record_fingerprint è un riscontro binario legato allo spazzolino, stabile se
stesso record e stessa chiave locale. I duplicati sono contati e conservati,
non rimossi. Questo NON è ancora la deduplica definitiva per HealthKit o un
archivio delle sessioni; un record arricchito può avere un fingerprint diverso.
Frame prima della richiesta non sono interpretati come risposta. Se il trasporto
non ha footer o invio confermato, il decoder segnala una cattura incompleta.

## Passi successivi al primo risultato

Analisi offline della prima cattura; se leggibile, seconda richiesta identica
senza conferma per verificare ripetibilità. Poi normale pulizia reale del
programma abituale, annotando inizio/fine/pause, e nuovo confronto. Non iniziare
una nuova pulizia prima di aver salvato lo storico esistente. Sessioni brevissime
non sono il test principale perché upstream documenta record invalidabili.

## Provenienza

Nuovo modulo sessions.py adattato dalla struttura documentata e dai decoder
di dzikus/esphome-oclean, commit e74100f042ccb3a01b9cac8acd2a8f5289488466:
PROTOCOL.md, oclean_protocol.{h,cpp}. GPL-3.0-only, attribuzioni in
THIRD_PARTY_NOTICES.md. Non viene importato né eseguito il polling upstream.


## Primo risultato hardware

Cattura autorizzata completata il 2026-11-10: 32 record candidati, 30 con date non attendibili e due recenti brevissimi. Nessuna conferma o modifica del clock. Risultati e limiti in docs/first-session-capture.md (dalla cartella docs: first-session-capture.md). Le frasi sopra che indicano cattura non ancora eseguita descrivono lo stato alla preparazione.
