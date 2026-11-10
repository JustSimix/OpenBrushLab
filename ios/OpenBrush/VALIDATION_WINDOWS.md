# Verifiche Windows

Progetto iOS preparato il10 novembre2026 su Windows.

| Verifica | Esito |
|---|---|
| Parsing sintattico Swift |11 file,0 errori tree-sitter-swift0.7.4/tree-sitter0.26.1 |
| OpenStep project.pbxproj |Parsing e riferimenti55 oggetti verificati |
| Scheme/workspace e plist XML |Validi; file referenziati esistenti |
| Bundle e target |it.imix.openbrush, iOS17.0, HealthKit |
| Vettore sync pubblico Python |Calcolato, inserito nel test Swift |
| Sorgenti Python |Hash prima/dopo identici |
| XCTest |17 casi preparati, NON eseguiti |
| Build Xcode / firma |NON eseguite; SDK Apple assente |
| Prova HealthKit iPhone |NON eseguita |
| BLE, commit, push, reset, clean |Nessuna operazione |

Il parsing sintattico non attesta che il codice compili contro SDK Apple.
Simone verifica sul Mac mini e sul proprio iPhone seguendo README_iOS.md.
