# Prima cattura sessioni OCLEANY3X — 2026-11-10

Cattura live autorizzata dall'utente e completata: una richiesta 0307 su fbb89,
notifiche solo fbb90, poi unsubscribe/disconnessione. Nessuna conferma 0202,
reset, set clock, impostazione, programma o firmware. Nessun retry vendor.

Risultati osservati:
- 68 notifiche da 20 byte, totale 1360 byte;
- intestazione TYPE1 valida, count dichiarato 32;
- 32 record da 42 byte, nessun duplicato binario tra questi record;
- 9 byte finali zero nel pacchetto finale da 20 byte;
- durata prevista 75 s in tutti i record;
- durate effettive candidate osservate: 1, 3, 34, 61, 63, 75 s;
- 30 record: year byte=0, month=1, data non attendibile secondo layout year+2000;
- 2 record: date plausibili del giorno della cattura, durate candidate 3 e 1 s,
  score grezzo=1 per entrambi (upstream lo associa a sessioni invalidate);
- nessun record ancora pronto per importazione HealthKit.

Il decoder iniziale ha rifiutato i 9 byte extra. Correzione offline: accettare
solo una coda di 1..19 byte tutti zero quando TUTTE le notifiche sono da 20 byte.
Coda non zero, frame extra completi o framing diverso restano rifiutati.
96 test offline passati dopo la correzione, inclusi casi avversi del padding.
L'originale non è stato modificato. Nuovo risultato separato *.padding-decoded.json.

Questo conferma che il download documentato restituisce record sul dispositivo.
Non prova ancora la semantica di durata, timestamp e timezone sullo Y3X.
Date non sincronizzate e sessioni recenti brevissime sono una spiegazione
plausibile del problema nell'app, non una diagnosi conclusiva del suo filtro.
Non attribuire date reali ai 30 record vecchi per interpolazione e non correggere
silenziosamente l'anno. I dati potrebbero essere precedenti a una sincronizzazione
del clock o avere una diversa semantica da indagare.

Prossima prova: prima di qualsiasi mutazione, confronto con una normale pulizia
reale annotando inizio/fine/pause e durata visualizzata, poi nuova cattura senza
conferma. Nessuna nuova pulizia o seconda richiesta è stata eseguita dall'agente.
Per Apple Health mancano la validazione con durata osservata, la semantica
temporale, deduplica persistente e componente iOS.

I file grezzi e decodificati sono in captures/, esclusi da Git e non cifrati.
Non allegarli integralmente a issue pubbliche; usare estratti redatti.
Questa nota contiene solo conteggi e conclusioni, senza indirizzi o sessioni complete.
