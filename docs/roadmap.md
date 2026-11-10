# Roadmap basata su evidenze

1. **Ora, implementato e verificato offline:** scanner, inventario GATT,
   letture standard, privacy, timeout e test con client simulati. L'utente ha
   riportato scan/connessione/letture standard riuscite su OCLEANY3X; vedere
   [evidenze e limiti](ocleany3x.md). Inventario GATT e protocollo vendor da validare.
2. **Validazione Y208 / 1.0.0.36:** raccogliere scan/gatt/read redatti, confermare
   DIS e proprietà UUID; annotare stato base e risveglio. Criterio: batteria e
   revisioni ripetibili, nessuna scrittura GATT o subscription. Non aggiornare
   firmware per rendere il dispositivo compatibile.
3. **Sessioni offline:** ottenere catture preesistenti e autorizzate, rimuovere
   identificativi, sviluppare assembler con limiti di dimensione, frammentazione,
   duplicati, count=0, date invalide e stream incompleti. Conservare distinzione
   tra campioni sintetici e catture reali; confrontare i due parser upstream.
   Decodifica, deduplica e timeline in JSON, senza database.
4. **Sessioni live, bloccate dal vincolo attuale:** download richiede GATT write
   e subscription. Non saranno abilitate in questa versione. Un'eventuale fase
   futura richiede una nuova autorizzazione esplicita e analisi separata delle
   query; escludere comunque conferma 02 02, reset, sincronizzazione orologio
   e altri comandi mutanti da ogni test iniziale.
5. **Display, ricerca offline:** catalogare impostazioni e riferimenti APK/asset
   ottenuti legittimamente; verificare se esiste un meccanismo documentato per
   contenuti personalizzati. Distinguere preset da rendering arbitrario.
   Niente brute force di opcode, upload o flash. Esito possibile: non supportato.

Prima di ogni implementazione futura: aggiornare provenienza e licenze, aggiungere
fixture redatte con contesto modello/firmware e segnare le ipotesi ancora aperte.
