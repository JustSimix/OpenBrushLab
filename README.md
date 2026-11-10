# OpenBrushLab

Laboratorio Python locale per studiare Oclean X Pro Elite **Y208**, firmware
**1.0.0.36**. Progetto non ufficiale, senza account o cloud. Solo terminale,
Bleak e file JSONL: niente Flutter, SQLite, server o interfacce grafiche.

## Stato reale

Implementati: scansione BLE, selezione esplicita del dispositivo, inventario
GATT, letture standard con allowlist (modello, firmware, hardware, software,
batteria), log redatti, decoder STATUS esclusivamente offline e test simulati.
Non implementati: comandi vendor, lettura sessioni dal dispositivo, impostazioni,
capture notifiche, display, OTA. Il firmware 1.0.0.36 **non è validato**.
Y208 è il modello commerciale: il modello DIS va misurato, non presunto.

Nessuna funzione trasmette scritture GATT. Non si attivano notifiche, perché
la subscription può scrivere il CCCD; nessun pairing esplicito o flash.
Una scansione Bleak normale può inviare scan request radio; connessione,
discovery e letture comportano traffico BLE. Sola lettura non significa sniffer passivo.

## Windows / PowerShell

Python 3.11+ e Bluetooth LE con driver Windows funzionanti (test software eseguiti
con Python 3.12). Usare un terminale PowerShell normale, non un notebook.

```powershell
Set-Location E:\Simix\Projects\OpenBrushLab
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m openbrushlab --help
```

L'ambiente locale è già stato creato durante la preparazione. Non serve attivarlo
né cambiare ExecutionPolicy. Per reinstallarlo basta il comando pip sopra.
`requirements.txt` installa solo il progetto con le dipendenze runtime;
`requirements-dev.txt` aggiunge pytest. I vincoli sono in pyproject.toml;
`docs/environment-tested.txt` registra le versioni effettivamente verificate.

## Primo esperimento sullo spazzolino

Chiudere l'app Oclean sul telefono, attivare Bluetooth Windows, avvicinare e
svegliare lo spazzolino. Nessun esperimento sul dispositivo è stato eseguito
automaticamente nella preparazione del progetto.

```powershell
.\.venv\Scripts\python.exe -m openbrushlab scan --log logs\scan-01.jsonl
.\.venv\Scripts\python.exe -m openbrushlab gatt --index 1 --log logs\gatt-01.jsonl
.\.venv\Scripts\python.exe -m openbrushlab read --index 1 --log logs\read-01.jsonl
```

Controllare che ci sia un solo candidato atteso prima di scegliere `--index 1`.
Ogni comando ripete la scansione; gli indici sono ordinati per indirizzo ma possono
cambiare se cambiano i dispositivi presenti. I token pseudonimi cambiano a ogni
esecuzione e non consentono di correlare catture diverse. Se ci sono più spazzolini,
usare l'indirizzo noto localmente tramite variabile d'ambiente:

```powershell
$env:OPENBRUSHLAB_ADDRESS = 'AA:BB:CC:DD:EE:FF' # sostituire: esempio fittizio
.\.venv\Scripts\python.exe -m openbrushlab read --log logs\read-02.jsonl
Remove-Item Env:OPENBRUSHLAB_ADDRESS
```

`.env.example` è solo un esempio: `.env` non viene caricato automaticamente.
`--all` include candidati senza nome riconoscibile: usarlo per diagnosticare una
scansione vuota, verificando con attenzione il dispositivo da selezionare.
`--address` è disponibile ma può finire nella cronologia del terminale.

`gatt` elenca UUID, handle, proprietà e metadati dei descrittori; non ne legge i
valori. `read` non legge seriale, System ID o caratteristiche proprietarie.
Valori DIS inattesi sono sostituiti con `[redacted-unrecognized-value]`.
Ogni lettura richiede una sola caratteristica leggibile nel servizio standard
atteso; duplicati vengono saltati. Nessun tentativo automatico di pairing.

Codici di uscita: 0 successo, 1 errore generale, 2 letture parziali/saltate,
130 interruzione. Un campo mancante non dimostra incompatibilità del protocollo.
Timeout configurabili con `--scan-seconds`, `--operation-timeout`, `--total-timeout`.
Gli errori del backend sono ridotti a categorie per evitare fughe di identificativi.

## Offline

```powershell
.\.venv\Scripts\python.exe -m openbrushlab decode-status 0303020e74500000
```

Questo payload è sintetico: batteria 80%, 3700 mV, fuori base. Non è una cattura
del dispositivo. Il decoder non apre il Bluetooth e non invia STATUS.

## Log e privacy

Output e `--log` sono JSONL (un oggetto JSON per riga, schema 1, timestamp UTC).
Il file deve essere nuovo: nessuna sovrascrittura. Indirizzi sostituiti da token
HMAC con chiave casuale effimera; niente nomi BLE, manufacturer/service data,
payload grezzi o testo delle eccezioni. Non è un anonimizzatore generico per
catture esterne: UUID GATT, orari, RSSI, modello e revisioni restano visibili e
possono consentire correlazioni. Controllare i log prima di condividerli.
`logs/`, `captures/`, `.env` e `.research/` sono esclusi da Git.

## Problemi Windows

- Nessun risultato: svegliare lo spazzolino, chiudere l'app, riprovare con `scan --all`.
- Errore connessione: controllare Bluetooth/driver e provare dopo aver chiuso altre
  connessioni. Non attivare pairing o notifiche per aggirare l'errore.
- Blocco WinRT/STA: usare il comando Python da PowerShell pulito, senza importare
  pywin32 o librerie GUI. Non viene forzato alcun workaround STA.
- Lettura parziale: esaminare prima `gatt`; il dato può non essere esposto o leggibile.
- File log già presente: scegliere un nuovo nome.

## Riferimenti, licenze e prossime fasi

Vedere [protocollo](docs/protocol.md), [roadmap](docs/roadmap.md),
[provenienza](THIRD_PARTY_NOTICES.md) e [inventario](docs/created-files.md).
Sorgenti adattati distribuiti con GPL-3.0-only; licenza MIT conservata per le
costanti di deniskie. Nessuna dipendenza runtime da ESPHome o Home Assistant.
Le copie di studio complete sono in `.research/`, ignorate da Git e mai importate.
Repository Git solo locale, nessun remoto configurato e nessuna pubblicazione.
