# OpenBrushLab — passaggio di consegne a un altro agente

**Aggiornato al 10 novembre 2026.** Documento autonomo per capire obiettivo,
stato effettivo, risultati, vincoli e prossimi passi senza rileggere la chat.
La fonte operativa resta il codice locale: distinguere sempre osservazioni
hardware, test simulati e ipotesi upstream.

## 1. Obiettivo e decisioni dell'utente

Creare un progetto indipendente per lo spazzolino Oclean, iniziando con Python
su Windows e riutilizzando responsabilmente il reverse engineering già disponibile.

La priorità assoluta è **recuperare data, ora e durata effettiva delle pulizie e
farle arrivare nell'app Salute dell'iPhone tramite HealthKit**, senza duplicati.
Lo storico nell'app ufficiale Oclean risultava vuoto: individuarne la causa è un
obiettivo di ricerca, non una diagnosi già risolta.

Scelte approvate:

- progetto in `E:\Simix\Projects\OpenBrushLab`, creato realmente e accessibile;
- Python, Bleak, terminale e JSON, senza SQLite, Flutter, dashboard o server;
- prima provare il recupero e la decodifica; poi componente iOS minima per HealthKit;
- mantenere tutte le altre feature nella roadmap, affrontandole dopo il P0;
- conservare e rispettare le licenze; nessuna pubblicazione automatica;
- l'utente preferisce che l'agente esegua i comandi sul suo PC e gli dica soltanto
  quando risvegliare lo spazzolino e quali azioni fisiche servono.

L'intenzione «voglio fare tutte le feature» non equivale a confermare che tutte
siano tecnicamente possibili, né autorizza flash o comandi vendor sconosciuti.

## 2. Ambiente e Git

| Voce | Stato osservato |
|---|---|
| Sistema | Windows, PowerShell |
| Cartella progetto | `E:\Simix\Projects\OpenBrushLab` |
| Python usato | 3.12.10; progetto richiede >=3.11 |
| Ambiente | `.venv`, installazione editable del progetto |
| Runtime verificato | Bleak 3.1.0, tzdata 2026.6 |
| Test | pytest 9.2.0; ultimo esito completo **134 passati** |
| Versione progetto | 0.1.0 |
| Zona di confronto | `Europe/Rome`, scelta dal contesto dell'utente |
| Git | repository locale, remoto chiamato `origin` già configurato dall'utente |
| HEAD osservato | `04385b7` — Update README and documentation; implement revision comparison logic |

**Attenzione al passaggio del codice:** ci sono numerose modifiche locali e file
nuovi non tracciati. Cattura sessioni e normalizzazione non risultano nel commit
HEAD osservato. Non presumere che un clone dal remoto contenga il lavoro più recente.
Il remoto non è stato interrogato per attestare ciò che contiene. Usare la cartella
locale oppure ottenere dall'utente una copia aggiornata dei sorgenti.

Non sono stati creati commit o push per queste ultime fasi. Non fare reset/clean
o sostituire il working tree per «ripartire pulito». Verificare `git status` e
preservare il lavoro presente; pubblicazione e gestione del remoto spettano all'utente.

Il documento non include indirizzi BLE, chiavi locali o catture grezze. Gli orari
della singola prova sotto sono riportati perché necessari a verificare il risultato.

## 3. Identificazione hardware reale

| Campo | Risultato letto |
|---|---|
| Prodotto dichiarato | Oclean X Pro Elite Y208 |
| DIS Model Number, 2A24 | **OCLEANY3X** |
| DIS Firmware Revision, 2A26 | **1.0** |
| DIS Software Revision, 2A28 | **1.0.0.36** |
| Hardware Revision, 2A27 | letto ma nascosto dal filtro, formato non riconosciuto |
| Batteria nelle prove | 83% |
| Inventario GATT | **8 servizi, 28 caratteristiche** |

Non rinominare arbitrariamente Firmware e Software Revision. La versione target
compare nel campo Software Revision: il confronto ora considera entrambi e indica
`matching_fields=["software"]`. Questo match non certifica tutto il protocollo.

## 4. Fonti open source, licenze e livello di evidenza

**dzikus/esphome-oclean**

- Repository: https://github.com/dzikus/esphome-oclean
- Commit studiato: `e74100f042ccb3a01b9cac8acd2a8f5289488466`.
- Copia locale shallow: `.research/esphome-oclean`, ignorata dal Git del progetto.
- Fonti principali: `PROTOCOL.md`, `components/oclean/oclean_protocol.{h,cpp}`,
  `oclean_profile.cpp`, README e test upstream.
- Licenza GPL v3, testo integrale nel `LICENSE` di OpenBrushLab.
- Non c'è una voce testuale specifica Y3X nella copia esaminata; il dispatch per
  prefisso `OCLEANY3` seleziona comunque TYPE1. È una deduzione dal codice.
- Le prove hardware dichiarate upstream per X Pro Elite riguardano Y3P/1.0.0.30
  e Y3PD/1.0.0.31, non automaticamente questo Y3X.

**deniskie/ha-oclean-integration**

- Repository: https://github.com/deniskie/ha-oclean-integration
- Commit studiato: `8b831484c92a02372ee88b1828148ab9552d1007`.
- Copia locale: `.research/ha-oclean-integration`, ignorata da Git.
- Fonti: `custom_components/oclean_ble/{const,protocol,parser}.py`, docs e test.
- Licenza MIT, copyright 2026 Denis Kiesel: conservati integralmente in
  `third_party/deniskie-MIT.txt`.
- Mappa esplicitamente **OCLEANY3X -> TYPE1**, supporto dichiarato parziale.
  La PR #145 spiega che il mapping deriva dall'identificazione come X Pro Elite
  del segnalante #110, senza handler APK specifico disponibile:
  https://github.com/deniskie/ha-oclean-integration/pull/145
- L'issue #110 non era recuperabile dal lettore web; non attribuirle dettagli
  ulteriori non presenti nella PR o nei sorgenti.

OpenBrushLab è GPL-3.0-only e conserva gli avvisi MIT delle parti riutilizzate.
Le adattazioni sono documentate in `THIRD_PARTY_NOTICES.md`. Non sono importati
o eseguiti i cicli di polling ESPHome/Home Assistant: possono inviare comandi
non ammessi dal nostro perimetro. I commit sopra sono snapshot, non promessa
che siano gli ultimi disponibili in futuro.

## 5. BLE: topologia e autorizzazioni effettive

Servizio Oclean: `8082caa8-41a6-4021-91c6-56f9b954cc18`.

| UUID completo | Handle osservato | Proprietà | Ruolo upstream |
|---|---:|---|---|
| `9d84b9a3-000c-49d8-9183-855b673fbb85` | 20 | read/write | TX principale |
| `5f78df94-798c-46f5-990a-855b673fbb86` | 22 | read/notify | RX stato/impostazioni |
| `5f78df94-798c-46f5-990a-855b673fbb87` | 25 | read/write | non attribuito |
| `5f78df94-798c-46f5-990a-855b673fbb88` | 27 | read/notify | non attribuito |
| `5f78df94-798c-46f5-990a-855b673fbb89` | 29 | read/write | TX richiesta sessioni |
| `5f78df94-798c-46f5-990a-855b673fbb90` | 31 | read/notify | RX sessioni |

Gli handle descrivono la cattura: il client risolve gli UUID nel servizio corrente,
senza hardcoding degli handle. Il servizio FEF5 ha altre10 caratteristiche:
non è stato identificato con certezza; non chiamarlo display/OTA per supposizione.

### Confine da preservare

- `scan`, `gatt`, `read`: niente scritture GATT o subscription. La scansione BLE
  normale può comunque inviare scan request radio: non è uno sniffer passivo.
- L'utente ha autorizzato ed eseguito tramite l'agente **due catture minime**:
  una scrittura `03 07` su fbb89 con risposta, subscription/cleanup fbb90 e
  disconnessione. Subscription/unsubscribe possono scrivere il CCCD.
- `capture-sessions` è separato e richiede `--allow-session-query`; prima verifica
  modello esatto e Software Revision, unicità e proprietà delle caratteristiche.
- Nessuna conferma `02 02`, reset, modifica orologio, programma, lingua/display,
  pairing esplicito, brute force o firmware/DFU/OTA è stata eseguita.
- `02 02` è particolarmente importante: upstream documenta che conferma/consuma
  la coda delle sessioni. Il nome `CMD_DEVICE_INFO` in un riferimento non lo
  rende innocuo. Non aggiungerlo al polling.
- Nessun retry vendor o fallback a opcode diversi è implementato.

L'agente successivo può continuare offline senza tenere sveglio il dispositivo.
Prima di una futura prova live coordinare il risveglio con l'utente; ogni nuova
mutazione oltre la cattura minima richiede un'autorizzazione distinta.

## 6. Cosa abbiamo fatto, nell'ordine

1. Creato progetto Python, ambiente, configurazione packaging, README Windows,
   test e licenze. Git inizializzato senza pubblicazione; remoto poi aggiunto
   autonomamente dall'utente.
2. Implementato scanner e discovery, letture standard allowlisted e logging
   JSONL con indirizzi/nome/payload identificativi omessi o pseudonimizzati.
3. Corretto confronto revisioni: target1.0.0.36 è in 2A28 sul dispositivo.
4. Scoperta topologia GATT reale, confrontata con TYPE1 dei due upstream.
5. Preparato e testato offline il percorso minimo di cattura, poi lanciato due
   volte soltanto dopo il via dell'utente.
6. Ricomposti i record TYPE1; adeguato il decoder al padding finale osservato.
7. Confrontato una pulizia reale con il record appena comparso.
8. Creato archivio JSON persistente, controlli temporali, deduplica e staging
   per futura importazione HealthKit; applicati alle due catture reali.

## 7. Risultati delle due catture

**Prima cattura:** 68 notifiche da20 byte, 1360 byte complessivi, count32.
Il corpo atteso è `7 + 32*42 = 1351` byte: i restanti9 byte sono tutti zero.
Il decoder iniziale ha rifiutato la coda; l'originale è rimasto intatto. Correzione:
accetta solo padding di1..19 byte zero nell'ultimo pacchetto se tutte le notifiche
sono da20 byte. Byte non zero, frame interi extra e framing diverso restano rifiutati.

**Prova reale:** l'utente ha riferito inizio alle11:37, completamento del programma
personalizzato abituale da75s e punteggio display59. La seconda cattura ha trovato:

| Dato | Nuovo record |
|---|---|
| Data/ora locale dispositivo | 2026-11-10 11:37:15 |
| Durata programmata | 75s |
| Durata effettiva candidata | 75s |
| Score grezzo | 59 |
| Programma grezzo | 231, nome/fasi/intensità non decodificati |
| Timezone grezzo | 15 |

Tra le catture: **31 record identici, uno nuovo, uno vecchio rimosso**. Coerente
con anello da32 record: non promettere uno storico illimitato. L'archivio locale
conserva anche le voci che escono dall'anello.

### Limiti della validazione

- Durata e score coincidono per **una pulizia reale completata**.
- Un ciclo completo da75s non distingue sperimentalmente durata prevista ed
  effettiva: servirà un ciclo interrotto durante un futuro utilizzo normale.
- Il timestamp è coerente con l'inizio riferito al minuto; questo supporta
  l'interpretazione come inizio, senza attestare il secondo esatto o ogni firmware.
- La fine11:38:30 è **derivata** da inizio+75s, non osservata indipendentemente.
- Pause, clock drift, altri fusi e significati delle zone non sono validati sul campo.
- L'app ufficiale non è stata riaperta per un confronto dopo la prova. Non sappiamo
  con certezza perché mostrasse zero.

## 8. Decoder candidato TYPE1

Header: `03 07 2A 42 23` + count u16 big endian. Record da42 byte.

| Offset nel record | Campo candidato |
|---|---|
| 0..5 | anno-2000, mese, giorno, ora, minuto, secondo |
| 6 | programma |
| 7..8 | durata prevista, BE |
| 9..10 | durata effettiva, BE |
| 17 | indice timezone TYPE1 |
| 33 | score grezzo |

Il decoder ricompone frammenti anche dell'header, limita dimensioni e conteggi,
conserva componenti della data e distingue frammenti inline da record completi.
Una risposta count0 può contenere un vecchio frammento inline: non significa
storico completo vuoto e non garantisce che quel frammento sia l'ultima pulizia.

Upstream associa score1 a sessioni invalidate, ad esempio molto brevi o quasi
senza movimento; FF significa score assente. Non trasformare questi marker
in valutazioni cliniche né attribuire automaticamente pressione/coverage ai byte.

## 9. Archivio, deduplica e date: stato attuale

**2 catture / 64 osservazioni -> 33 voci distinte / 31 ripetizioni esatte.**

- **1 candidata per revisione iOS:** la pulizia reale da75s/score59.
- **32 hold:** 30 voci con data non attendibile e due recenti brevissime.
  Le ragioni possono sovrapporsi: tre voci complessive hanno durata breve e marker1,
  una delle quali rientra anche nelle30 con data anomala.
- Le30 hanno year byte0 e mese1; non sostituire l'anno con2026 né interpolare date.
  Il materiale può indicare clock non inizializzato o richiedere ulteriore studio.

Identità: per record completi con data plausibile, hash di device_key persistente,
timestamp locale, indice timezone e programma. Durata/score non fanno parte della
chiave. Tutte le varianti binarie e provenienze sono conservate. Varianti differenti
nello stesso gruppo bloccano l'export; non si sceglie automaticamente la più recente
o il valore maggiore. Date invalide/inline usano solo il fingerprint binario.

La device_key è una pseudonima derivata dalla chiave privata locale delle catture.
Non usare per deduplicare i token di scan, che cambiano a ogni esecuzione.
Perdere `.device-key` può separare future catture dello stesso spazzolino.

### Fuso verificato

Tabella TYPE1 di dzikus: indice15=UTC+01:00, indice16=UTC+02:00; non sono
quarter-hours. Confronto con IANA `Europe/Rome` alla data della sessione:
11:37:15 locale -> **10:37:15Z**; fine derivata **10:38:30Z**.

ZoneInfo/tzdata controllano roundtrip, ore inesistenti in primavera, offset
incoerenti e doppie ore autunnali (disambiguate dall'offset wire). Vengono
segnalati anche futuro rispetto alla cattura e fine di una pulizia completata
successiva alla cattura, con tolleranza5s. Nessuna correzione del clock via BLE.

### Ripetibilità e salvataggio

Ripetuto import realmente: zero nuove catture, archivio/export byte per byte
identici, sync version ferma a1, SHA-256 degli originali invariati.
File lock esclusivo e replace atomico di ciascun JSON; non è una transazione
unica fra archivio ed export. Dopo un errore sullo staging, rilanciare rigenera
lo stesso payload senza aumentare le versioni. Non eliminare lock alla cieca.

## 10. Preparazione Apple Health: cosa significa e cosa manca

`data/healthkit-candidates.json` è **un contratto per una futura componente iOS**,
non un file importabile direttamente dall'app Salute, né un backup XML Apple.

- formato `openbrushlab-healthkit-staging`, schema1;
- `writes_to_apple_health=false`, `requires_review=true`;
- candidato tipo `HKCategoryTypeIdentifierToothbrushingEvent`;
- valore simbolico `notApplicable`, da mappare alla costante HealthKit in iOS;
- inizio/fine ISO8601 UTC, durata in secondi, zona IANA;
- fine esplicitamente derivata e revisione richiesta;
- `HKMetadataKeySyncIdentifier` stabile e `HKMetadataKeySyncVersion` intero;
- versione invariata per payload uguale, incrementata per cambiamento o riattivazione;
- `retired_candidates` per riconciliare un candidato in seguito bloccato, senza
  cancellazioni automatiche da Salute;
- `healthkit_ready=false` resta nell'archivio.

**Nessun evento è stato scritto in Apple Health.** L'importer iOS, l'autorizzazione
HealthKit, firma/installazione e test su iPhone non esistono ancora. I metadati
sync non eliminano automaticamente duplicati creati da altre app.

Fonti Apple consultate:
- https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/toothbrushingevent
- https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier
- https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncversion
- https://developer.apple.com/videos/play/wwdc2020/10184/

## 11. Mappa dei file per proseguire

| File/cartella | Responsabilità |
|---|---|
| `src/openbrushlab/cli.py` | comandi e opt-in cattura |
| `ble.py` | scan, inventario, letture standard allowlisted |
| `protocol.py` | UUID, decoder standard/STATUS offline e confronto revisioni |
| `privacy.py` | JSONL redatti e token effimeri |
| `capture.py` | unico percorso applicativo write0307 e notify fbb90 |
| `sessions.py` | lettura raw, assembler/decoder TYPE1 e padding |
| `normalize.py` | archivio, controlli date, deduplica e staging |
| `tests/test_{ble,cli,protocol,capture,normalize}.py` | verifiche offline e regressioni |
| `docs/session-normalization.md` | contratto archivio/export, controlli e recupero |
| `docs/healthkit-staging.schema.json` | schema JSON di staging per l'importer futuro |
| `docs/session-capture.md` | perimetro e procedura della cattura |
| `docs/first-session-capture.md`, `real-session-validation.md` | risultati hardware |
| `docs/ocleany3x.md`, `protocol.md`, `p0-feasibility.md` | ricerca e provenienza |
| `docs/*validation.txt`, `environment-tested.txt` | verifiche registrate |
| `README.md`, `docs/roadmap.md` | stato sintetico e priorità correnti |
| `THIRD_PARTY_NOTICES.md`, `LICENSE`, `third_party/` | licenze e attribuzioni |

I nomi dei moduli abbreviati sopra sono tutti sotto `src/openbrushlab/`.
Alcuni documenti storici contengono «non ancora eseguito» seguito da aggiornamenti:
per lo stato corrente usare questo handoff, README e le ultime verifiche.

### Dati privati, presenti solo sul PC

- `captures/*.raw.jsonl`: originali con byte grezzi e orari personali;
- `.decoded.json`, `.padding-decoded.json`, `.comparison.json`, `.sha256`:
  analisi derivate e impronte;
- `captures/.device-key`: segreto locale, non pubblicare;
- `data/sessions.json`: archivio, provenienza, osservazioni e registro sync;
- `data/observations.json`: osservazione della pulizia riferita dall'utente;
- `data/healthkit-candidates.json`: staging privato;
- `logs/`: output redatti delle prove, con UUID/orari/RSSI comunque visibili.

`captures/`, `data/`, `logs/`, `.env`, `.venv/`, `.research/` sono esclusi da Git.
I dati non sono cifrati dal programma. Non allegarli integralmente a issue o chat
pubbliche. Per un altro agente sullo stesso PC basta accedere al progetto locale;
su un'altra macchina occorrono sorgenti aggiornati e, solo se autorizzati, i dati
privati. **Il solo clone Git non contiene lo storico privato.**

## 12. Comandi operativi

Non serve attivare `.venv`; usare il Python dell'ambiente evita problemi di PATH.
Cominciare offline, senza accendere lo spazzolino:

```powershell
cd E:\Simix\Projects\OpenBrushLab
.\.venv\Scripts\python.exe -m openbrushlab --help
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m pip check
.\.venv\Scripts\python.exe -m openbrushlab normalize-sessions
```

L'ultimo comando aggiorna archivio/staging, non esegue BLE. Le osservazioni utente
restano nell'archivio anche omettendo `--observations`. Passare esplicitamente
un nuovo file sostituisce il set di riscontri; un set vuoto li revoca.

Su un ambiente da ricreare, prima leggere `pyproject.toml` e usare:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
```

Discovery/read di sola lettura, con file di log nuovi:

```powershell
.\.venv\Scripts\python.exe -m openbrushlab scan
.\.venv\Scripts\python.exe -m openbrushlab gatt --index 1 --scan-seconds 8 --operation-timeout 30
.\.venv\Scripts\python.exe -m openbrushlab read --index 1 --scan-seconds 8 --operation-timeout 30
```

Cattura live, **solo quando concordata con l'utente**:

```powershell
.\.venv\Scripts\python.exe -u -m openbrushlab capture-sessions --index 1 --allow-session-query --scan-seconds 15
```

Il comando richiede target unico con indice, modello e versione esatti. Raccolta
12s, massimo256 notifiche/8192 byte, 512 byte per frame, timeout totale predefinito
75s più cleanup limitato. Nessun ACK o retry vendor. In caso di risultato inatteso,
analizzare il raw offline prima di cambiare opcode o ripetere prove.

Replay offline senza sovrascrivere l'output:

```powershell
.\.venv\Scripts\python.exe -m openbrushlab decode-sessions captures\NOME.raw.jsonl --output captures\NOME-replay-nuovo.json
```

### Coordinamento fisico con l'utente

Chiudere app Oclean sul telefono, avvicinare il dispositivo, avvisare «risveglia
ora il display» e lanciare subito la scansione. Non serve il motore acceso né
muoverlo continuamente. In standby può non essere rilevato; risvegliare e riprovare
coordinandosi. `count:0` non prova incompatibilità. Gli indici si ricalcolano a
ogni scan. Uno dei vecchi tentativi GATT è scaduto, ma tentativi successivi sono
riusciti: evitare di dedurre un guasto da un singolo timeout.

## 13. Verifiche e problemi noti

Ultimo test registrato: **134 test offline passati**, `pip check` senza dipendenze
rotte. Comprendono callback simulate, richiesta unica, cleanup/timeout, padding,
stream frammentati, record incompleti, privacy, date anomale, DST gap/fold,
deduplica, conflitti, persistenza osservazioni, lock, errori di scrittura,
versioni sync e recupero dello staging. Le prove hardware sono soltanto quelle
descritte, non134 esperimenti sullo spazzolino.

Questioni aperte da non mascherare:

- `total-timeout` nei vecchi comandi read/gatt è una categoria generica e può
  indicare un timeout di connessione; capture ha fasi più precise;
- vecchia descrizione packaging «read-only» in pyproject è più restrittiva del
  prodotto attuale: il percorso write separato è esplicito e documentato;
- i raw non vengono reinterpretati automaticamente a ogni futura modifica del
  decoder se sono già nel catalogo: progettare migrazione/rebuild controllato,
  preservando osservazioni e registro sync prima di cambiare semantica;
- una nuova sessione non avrà automaticamente il riscontro umano richiesto dal
  filtro attuale: rimarrà hold fino a revisione. Per sincronizzare normalmente
  servirà una politica di fiducia del profilo, fondata su ulteriori prove;
- deduplica fra dispositivi/installazioni/app diverse non è garantita;
- fine derivata e fuso corrente non devono essere spacciati per misure universali;
- non sappiamo recuperare le date vere dei30 record vecchi.

## 14. Prossimi passi consigliati e criteri di successo

### P0 — completare la catena fino a Salute

**A. Consolidare il contratto Python.** Verificare i test sul working tree corrente,
fare backup privato di raw/archivio/chiave. Mantenere stabile schema e identità,
documentando future migrazioni. Non cambiare record vecchi per ottenere più export.

**B. Verificare durata effettiva e pause.** Durante un futuro utilizzo normale,
concordare una prova interrotta o con pausa e annotare durata reale, orari e display.
Scaricare prima di conferme/reset. Criterio: il tempo effettivo differisce dal
programma quando opportuno e non viene gonfiato a75s. Non serve una pulizia extra
immediata. Se non è ricostruibile l'intervallo reale con pause, dichiarare il limite.

**C. Importer iOS minimo.** Prima verificare disponibilità di Mac/Xcode/iPhone,
firma e percorso d'installazione; non promettere compilazione nativa su Windows.
Importare inizialmente il JSON dalla macchina tramite un passaggio file scelto
dall'utente. Richiedere autorizzazione HealthKit e revisione dell'unico candidato.
Usare toothbrushingEvent/notApplicable, intervallo, zona e chiavi sync previste.
Niente dashboard o grande app prima del primo evento in Salute.

**D. Validare deduplica end-to-end.** Primo invio -> un evento; secondo invio
uguale -> nessun duplicato. Gestire aggiornamenti versionati e ritiri con
riconciliazione esplicita, senza cancellazioni arbitrarie. Controllare eventuali
eventi già presenti da Oclean prima di promettere unicità fra sorgenti.

**E. Automatizzare con criterio.** Dopo più riscontri reali, scegliere una politica
per sessioni nuove senza osservazione manuale e validare orologio/fuso. Solo dopo
portare eventualmente il client BLE su iPhone per eliminare il passaggio Windows.
Nessuno di questi pezzi iOS o BLE iPhone è implementato oggi.

### P1 — qualità, statistiche e gamification

1. Validare score, zone e significati dei byte su più sessioni e confronto display.
2. Studiare pressione/movimenti; non confondere una distribuzione di zone con
   pressione calibrata o copertura clinica.
3. Totali giornalieri/settimanali, confronti, streak, obiettivi, report mensili e
   annuali sui soli dati temporalmente affidabili.
4. Dashboard/UI soltanto dopo P0 e dopo una scelta esplicita dello stack futuro.

### P2 — programmi e display

5. Leggere/studiare i programmi esistenti e il programma231; encoder upstream
   disponibili non equivalgono a intensità/fasi validate sullo Y3X. Ogni modifica
   richiede nuova autorizzazione e prova di readback.
6. Lingua/tema/orologio sono distinti da testo, immagini, icone e animazioni.
   Nessun canale di rendering arbitrario è dimostrato. Esaminare legittimamente
   documentazione/asset, senza scansione a forza di opcode e senza flash.

### P3 — esperimenti

7. Telemetria live: evidenza attuale bassa, upstream descrive sessioni bufferizzate
   scaricate dopo la pulizia. Non promettere movimento/pressione live.
8. Batteria già letta; autonomia richiede serie temporali. Usura testina sarebbe
   una stima da utilizzo, non una misura dello stato fisico.
9. Home Assistant: sfruttare eventi validati dopo download, senza importare
   ciecamente il polling upstream o attivare conferme automatiche.
10. Easter egg/mini-giochi subordinati alla scoperta di un meccanismo display reale.

## 15. Punto di ripartenza per il prossimo agente

Aprire il progetto locale e preservare il working tree. Leggere questo documento,
`README.md`, `docs/session-normalization.md`, `normalize.py` e lo schema staging.
Verificare prima offline i134 test e il riepilogo archivio, senza nuove scritture
BLE. Discutere con l'utente il percorso pratico iOS/HealthKit e la prova di durata
interrotta. Continuare secondo P0 -> P1 -> P2 -> P3, segnalando per ogni funzione
cosa è implementato, cosa ha una prova reale e cosa è soltanto ricerca.
