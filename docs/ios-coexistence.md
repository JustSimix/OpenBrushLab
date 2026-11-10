# Coesistenza iOS con Oclean e altri central

OpenBrush non rileva i processi dell'app ufficiale e non dimostra la causa di un
errore generico di connessione. Gli avvisi sono condizionali: «chiudi l'app Oclean»
è un'azione utile, non una diagnosi certa.

Prima di una prova chiudere l'app Oclean, interrompere eventuali letture Python,
avvicinare lo spazzolino e risvegliare il display. Mantenere OpenBrush in primo
piano. Mai due acquisizioni contemporanee. Non è necessario avviare una pulizia
per scaricare lo storico già presente.

La sincronizzazione ufficiale può inviare `02 02` per confermare/consumare la coda
delle sessioni, oppure tenere occupata la connessione. OpenBrush non invia mai
questo comando. Un conteggio zero non prova da solo una cancellazione: può
contenere un frammento inline, che non viene esportato come sessione completa.
I dati già archiviati localmente non vengono eliminati se l'anello torna vuoto.

Un device può rifiutare un secondo central o dipendere da un bonding già esistente.
OpenBrush segnala questa possibilità se il collegamento fallisce. Se CoreBluetooth
riporta peerRemovedPairingInformation, mostra un avviso specifico di associazione.
Non forza pairing, non rimuove associazioni e non propone opcode alternativi.
Un errore generico non permette di distinguere bonding, app ufficiale, distanza,
standby o problemi radio. La compatibilità come secondo central resta da validare
sul dispositivo reale. Un eventuale prompt di sicurezza gestito da iOS non è una
procedura di pairing esplicita avviata dall'app.

Se Salute rende visibile un evento Oclean sovrapposto, OpenBrush blocca l'invio
automatico e lo mostra in revisione. Non cancella dati di altre sorgenti. Se la
lettura di Salute è negata, una query può risultare vuota senza rivelare il diniego:
assenza di duplicati fra sorgenti diverse non garantibile in quel caso.

Non aprire Oclean durante la prova di sette giorni senza annotarlo: potrebbe
alterare ciò che resta nell'anello. Non si può recuperare ciò che non è stato
letto prima della sovrascrittura/consumo. Un anello da 32 slot non garantisce
due settimane: anche tentativi brevi o record anomali possono occupare spazio.
