# Roadmap OpenBrushLab

Priorità dell'utente: P0 sessioni e Apple Health prima delle altre feature.
Stato del 2026-11-10; niente nuove operazioni BLE nella fase di normalizzazione.

## P0 — sessioni e Salute

1. Completato sul dispositivo: scanner, discovery, revisioni/batteria, due download
   minimi senza conferma, un nuovo record coerente con una pulizia reale da75s e score59.
2. Completato Python: normalizzazione, deduplica persistente/provenienza, controlli
   data/offset/IANA e staging JSON candidato. Reimport identico non crea duplicati
   o nuove versioni. 33 voci archiviate, 1 candidata iOS e 32 hold.
3. Da validare durante un futuro utilizzo normale: durata in un ciclo interrotto,
   pause e semantica temporale; non serve una nuova pulizia immediata. Le30 date
   anomale restano tali: non sincronizzare o resettare per tentare di ripararle.
4. Prossima implementazione: componente iOS minima che importa lo staging,
   richiede autorizzazione HealthKit, mostra la revisione e gestisce ID/versioni
   sync e ritiri. Provare prima un evento reale, poi invio ripetuto senza duplicati.
   JSON Windows non scrive direttamente in Salute. Mac/Xcode/iPhone e percorso
   di firma/distribuzione andranno verificati prima di promettere installazione.

## P1 — qualità, statistiche e gamification

Score59 riscontrato per una sessione. Validare zone/pressione/movimenti su fixture
e dati reali prima di attribuire significati; zero non equivale a misura assente.
Poi totali giornalieri/settimanali, streak, confronti e report sui soli record
con tempo attendibile. Dashboard e UI dopo il P0. Nessuna metrica clinica inventata.

## P2 — programmi e display

Identificativo programma231 osservato, nome/intensità/fasi non ancora letti.
Studiare encoder upstream e letture impostazioni prima di mutazioni, con prove
e autorizzazione separate. Lingua/tema non provano rendering arbitrario.
Testo, immagini, icone e animazioni sono ricerca: nessuna capacità confermata.

## P3 — esperimenti

Telemetria live poco supportata dalle evidenze TYPE1. Batteria già disponibile,
autonomia e testina richiedono misure nel tempo. Home Assistant dopo eventi P0
affidabili. Mini-giochi/easter egg subordinati a un vero canale display.
Non eseguire brute force, flash/OTA, reset o opcode sconosciuti.

Ogni feature avrà prove specifiche e stato implementato/validato/da verificare.
Le autorizzazioni alle due catture minime non autorizzano tutte le future mutazioni.
