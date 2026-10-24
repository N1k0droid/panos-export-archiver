# Note per i revisori

[English](REVIEW_NOTES.md) | **Italiano**

Per chi revisiona questo codice, persone o strumenti di revisione automatica. Raccoglie i punti già verificati con test reali, per evitare "correzioni" inutili o dannose.

**Controllare i file reali, non il testo incollato in una chat.** Copiando il codice in una chat gli indirizzi possono diventare link e `<` `>` `&` entità HTML (`&lt;` `&gt;` `&amp;`). Nei file non ce ne sono.

## 1. Controlli rapidi sui file reali

Nessuna entità HTML o link negli script (atteso: nessun output, exit code 1):

```bat
findstr /n /i /c:"&gt;" /c:"&lt;" /c:"&amp;" /c:"<a href" panos_csv_archiver.bat panos_csv_search.bat
```

I fine riga CRLF sono obbligatori per i file `.bat`: con il solo LF `cmd.exe` può non trovare le etichette. Non convertirli in LF (vedi anche `.gitattributes`).

Righe che devono restare esattamente così:

```bat
set "SCRIPT_URL=https://github.com/N1k0droid"
set "ZABBIX_SERVER=<ZABBIX_SERVER_OR_PROXY>"      & rem segnaposto voluto
set "QUIET=>nul 2>&1"                             & rem redirezione in variabile, usata come %QUIET%
set "CARET=^"                                     & rem caret in una riga senza "!"
```

## 2. Scelte intenzionali (non sono errori)

- **Batch puro**: niente PowerShell, WMIC, VBScript o `reg.exe` (spesso bloccati dalle policy). Data e ora da robocopy, dati del disco da `dir` e `fsutil`, indipendenti dalla lingua di Windows.
- **`LOG_RETENTION_MONTHS=6` conserva 7 file mensili** (mese in corso + 6 mesi interi): voluto, così sono sempre disponibili almeno 6 mesi di storico, anche il primo giorno del mese.
- **`SENDER_PREVIOUS=1` iniziale**: evita il falso allarme "Previous final sender transmission failed" alla prima esecuzione di un'istanza.
- **`zabbix_sender` non è un prerequisito bloccante**: l'archiviazione prosegue, il mancato invio va nel log, `sender_status.txt` va a 0 e Zabbix segnala l'assenza di dati con `nodata()`. `ZABBIX_ENABLED=0` disattiva del tutto il monitoraggio.
- **SUCCESS anche con file rimandati** (`MIN_FILE_AGE_MINUTES`): un CSV ancora in caricamento non è un errore; i file rimasti sono controllati dal trigger dei pending.
- **`MIN_FILE_AGE_MINUTES=5`** è il valore di produzione (0 solo nei test).
- **Registro e discovery prima dei controlli su percorso e prerequisiti**: così Zabbix riceve anche le metriche di errore.
- **Valori non misurabili** (spazio libero con percorso rifiutato, totali dell'archivio) omessi, mai inviati come 0.
- **Exit code 2 di zabbix_sender** (valori rifiutati) non viene ripetuto, tranne una volta alla prima esecuzione di una nuova istanza (discovery di Zabbix asincrona). Con più destinazioni il codice 2 significa anche che una non era raggiungibile mentre le altre hanno ricevuto i dati.
- **Più destinazioni Zabbix tramite un file `-c` temporaneo** (`ServerActive=`): `-z` accetta un solo indirizzo; la virgola invia in parallelo a server indipendenti, il punto e virgola elenca i nodi di un cluster HA (provato con zabbix_sender 7.0).
- **`{$PANOS.CSV.ALLOWED.HOSTS}` ha default `0.0.0.0/0,::/0`**: un valore vuoto fa rifiutare a Zabbix TUTTI i dati (verificato su Zabbix 7.0, 7.2, 7.4).
- **Firma nel template**: il blocco `vendor` (N1k0droid) e i tag `template`, `class` e `target` sono voluti.
- **Nessun trigger separato per i "file falliti"**: un file fallito rende già l'esecuzione *Failed* o *Partial* (niente doppi allarmi).
- **Totali dell'archivio dal riepilogo di robocopy, non da `dir /s`**: un `for /f` su `dir /s` cresce con il numero di archivi ed è troppo lento con centinaia di migliaia di file (misurato).
- **Pochissime `call` nel ciclo di archiviazione** (`:ProcessFile`) e valori in cache: una call costa circa 20 ms e i file possono essere migliaia al giorno.
- **Ricerca: colonne utente controllate in batch dopo `findstr`**: le espressioni regolari di `findstr` non riescono a saltare 12-13 colonne (limite di complessità, misurato).
- **Righe del log e valori Zabbix in inglese** anche con `LANGUAGE=it`: sono tradotti solo i messaggi a schermo.

## 3. Caratteri supportati (testati)

| Caso | Risultato |
|---|---|
| Cartella con spazi e parentesi, es. `Log PA (prod)` | archiviato |
| Cartella con `&` | archiviato |
| Cartella con `^`, `%` oppure `!` (sorgente, `/archive`, log, cartella dello script) | exit 10, nessun file toccato, anche se esiste una cartella con lo stesso nome senza quel carattere |
| Nome CSV con `&` oppure `(1)` | archiviato |
| Nome CSV con `!` | quel file fallisce e resta al suo posto |

`|`, `<` e `>` non sono ammessi nei nomi di file Windows. Le cartelle del mese precedenti alla 1.0 `MM-AAAA (Mese)` (con parentesi) sono gestite.

## 4. Sicurezza e riservatezza

- A Zabbix non arrivano mai nomi di file, percorsi o nomi di cartelle.
- I nomi dei CSV sono nascosti di default nel log locale (`LOG_FILE_NAMES=0`).
- L'output di `/debug` mostra server Zabbix, nome host, metriche e nomi dei CSV (nessuna credenziale): rivederlo prima di salvarlo in sistemi condivisi.
- Lo script di archiviazione non cancella mai archivi: la rotazione è manuale. Un archivio non valido viene rinominato `*.7z.invalid-<epoch>`, mai eliminato.
- Con `ALLOW_REMOTE_PATHS=0` (default) percorsi UNC, unità di rete, SUBST e link verso la rete vengono rifiutati prima di qualsiasi operazione.

## 5. Come è stato verificato

- **Script**: Windows 11, 7-Zip 24.07 e un finto `zabbix_sender` che registra i dati. File normali, rimandati e in collisione, archivi danneggiati, esecuzioni interrotte, spazio insufficiente, 7-Zip mancante, opzioni 7-Zip rifiutate, percorsi UNC, unità di rete, link, esecuzioni concorrenti, 1.800 file al giorno, file da 46 MB, entrambe le lingue, tutte le varianti della cartella del mese; ricerca: ogni criterio con il numero esatto di righe atteso, caratteri speciali, jolly, periodi, archivi danneggiati.
- **Template**: importato in Zabbix 7.0.31, 7.2.15 e 7.4.15 (Docker) con dati inviati dal vero `zabbix_sender`: discovery, 34 item e 17 trigger per istanza, dipendenze, macro di contesto, value map, tag, allowed hosts, trigger basati sul tempo con storico sintetico.
- **Da verificare in ogni ambiente**: `mountvol` e `fsutil` con l'account di servizio e i tempi sui log reali.

## 6. Collaudo manuale suggerito

```bat
panos_csv_archiver.bat "C:\Test\FW01-TRAFFIC" "test-traffic" /console
echo Exit code: %ERRORLEVEL%
```

Atteso nel riepilogo: `Result : SUCCESS - exit code 0` (`Esito` con `LANGUAGE=it`), i file trovati e `Zabbix : metrics sent` solo con Zabbix configurato e `zabbix_sender` presente. Il percorso del log è indicato alla voce `Log file` (in `LOG_DIR`, oppure in `<cartella>\Logs` con `LOG_DIR_FALLBACK=1`).
