# Protocollo: evidenze e limiti

Target dichiarato dall'utente: Oclean X Pro Elite Y208, firmware 1.0.0.36.
Nessuna cattura hardware raccolta dall'agente. Letture standard OCLEANY3X
riportate dall'utente e nuove evidenze upstream sono in [ocleany3x.md](ocleany3x.md). Tutti gli offset
vendor sotto sono evidenze upstream o ipotesi da verificare su questo firmware.

## Fonti fissate

- dzikus/esphome-oclean, commit `e74100f042ccb3a01b9cac8acd2a8f5289488466`:
  [PROTOCOL.md](https://github.com/dzikus/esphome-oclean/blob/e74100f042ccb3a01b9cac8acd2a8f5289488466/PROTOCOL.md),
  `components/oclean/oclean_protocol.cpp`, `oclean_profile.cpp`, README. GPL v3.
- deniskie/ha-oclean-integration, commit `8b831484c92a02372ee88b1828148ab9552d1007`:
  [const.py](https://github.com/deniskie/ha-oclean-integration/blob/8b831484c92a02372ee88b1828148ab9552d1007/custom_components/oclean_ble/const.py),
  `protocol.py`, `parser.py`. MIT, copyright 2026 Denis Kiesel.
- [Bleak scanner](https://bleak.readthedocs.io/en/latest/api/scanner.html),
  [client](https://bleak.readthedocs.io/en/latest/api/client.html),
  [Windows troubleshooting](https://bleak.readthedocs.io/en/latest/troubleshooting.html).

Data studio: 2026-11-10. README dzikus segnala verifica X Pro Elite OCLEANY3P
1.0.0.30 e OCLEANY3PD 1.0.0.31. deniskie contiene osservazioni OCLEANY3P
1.0.0.41. Nessuna di queste costituisce validazione di 1.0.0.36.

## Topologia attesa

| Servizio | Caratteristica | Ruolo upstream | OpenBrushLab |
|---|---|---|---|
| 180A | 2A24/2A26/2A27/2A28 | modello/FW/HW/SW | lettura se esposta e leggibile |
| 180F | 2A19 | batteria percentuale, 1 byte | lettura, 0..100 |
| 8082caa8-41a6-4021-91c6-56f9b954cc18 | 9d84b9a3-000c-49d8-9183-855b673fbb85 | TX principale | solo inventario |
| stesso | 5f78df94-798c-46f5-990a-855b673fbb86 | RX read/notify | solo inventario |
| stesso | 5f78df94-798c-46f5-990a-855b673fbb89 | TX sessioni | solo inventario |
| stesso | 5f78df94-798c-46f5-990a-855b673fbb90 | RX sessioni notify | solo inventario |

Per UUID standard usare suffisso Bluetooth `-0000-1000-8000-00805f9b34fb`.
Serial Number 2A25 e System ID 2A23 non vengono letti. Il modello commerciale
Y208 non basta per selezionare un profilo: raccogliere modello DIS e revisioni.

## Query semantiche che richiedono scritture: non implementate

Upstream documenta TYPE1 senza auth/pairing, interi big endian, nessun CRC di
frame e Write With Response richiesto. Non assumere queste proprietà per Y208
1.0.0.36 senza verifica. Nessuna funzione di questo progetto costruisce o invia
le richieste elencate qui.

| Byte documentati | Significato | Rischio / stato |
|---|---|---|
| 03 03 | STATUS | richiede write, non inviato |
| 03 02 01 | SETTINGS | richiede write, non inviato |
| 03 07 su fbb89 | download sessioni | richiede write, non inviato |
| 02 02 | conferma sessioni / unread count | può consumare la coda; vietato |
| 02 01 + payload | imposta orologio | mutazione, non implementata |
| 02 0F | reset testina | mutazione, non implementata |
| 02 16 + lingua | lingua display | mutazione, non implementata |

La modalità `read_only` di un upstream non equivale alla nostra: può inviare
query scrivendo caratteristiche e limitarsi a evitare conferme/mutazioni.
Non importiamo i coordinator upstream e non eseguiamo i loro cicli di polling.
Il nome deniskie `CMD_DEVICE_INFO` per 02 02 non è una garanzia di innocuità:
dzikus ne documenta l'effetto sul contatore delle sessioni.
Un'altra divergenza: deniskie TYPE1 instrada varie query su fbb89, mentre
dzikus usa fbb85 per STATUS/SETTINGS e fbb89 per download. Nessuna scelta viene
sperimentata sul dispositivo in questa fase.

## Decoder offline implementato

STATUS TYPE1: esattamente 8 byte, prefisso 03 03, byte 2 dock (1 carica,
2 fuori base, 3 pieno sulla base); byte 3..4 mV BE; byte 5 batteria 0..100.
Byte 6..7 non interpretati. Layout adattato dalla documentazione dzikus,
con controlli più restrittivi. Non supporta la variante V20 a 6 byte.
Nessun dato sintetico viene presentato come osservazione hardware.

## Sessioni e impostazioni: solo documentazione

dzikus descrive SETTINGS in 2 notifiche ricomposte in 34 byte: tema a offset 0,
clock 16..21, lingua 31. Non è una normale lettura GATT del tema: prima serve
la query scritta. La lettura diretta fbb86 può essere vuota, vecchia o dipendere
dal precedente stato: per ora è esclusa.

TYPE1 sessioni: intestazione 03 07 2A 42 23 + count u16 BE, poi record di 42
byte frammentati; non assumere che una notifica sia un record. Timestamp 0..5,
programma 6, durata prevista 7..8 e durata effettiva 9..10 BE; score offset 33
(FF assente, 1 sessione invalidata secondo dzikus). Con count=0 può arrivare
un frammento inline di 13 byte della prima posizione: non trattarlo come
sessione completa né necessariamente come ultima sessione. Ordinare con cautela
secondo clock del dispositivo; non presumere UTC né ordine cronologico dell'anello.
Timezone e interpretazioni di pressione/zone differiscono tra fonti e famiglie.
Nessuna metrica derivata di coverage o pressione è implementata qui.

## Display

Tema, lingua e orologio non dimostrano la possibilità di inviare immagini,
testo o disegnare pixel. Non c'è un percorso di rendering arbitrario convalidato
per questo modello/firmware. Funzioni compleanno/meteo/BluFi del V20 non sono
evidenza trasferibile a X Pro Elite. Nessun OTA, DFU, firmware o asset caricato.
