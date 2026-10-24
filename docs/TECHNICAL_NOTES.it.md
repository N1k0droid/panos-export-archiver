# Note tecniche

[English](TECHNICAL_NOTES.md) | **Italiano**

Come e perché `panos_csv_archiver.bat` e `panos_csv_search.bat` funzionano così. Installazione e opzioni sono nel [README](../README.it.md).

## 1. Batch puro

Non vengono usati PowerShell, WMIC, VBScript né `reg.exe`: le policy aziendali spesso li bloccano. Vengono chiamati solo `cmd.exe` e programmi di System32, sempre con percorso assoluto (`%SystemRoot%\System32\...`), così il `PATH` non può cambiare il programma eseguito. I file `.bat` devono mantenere i fine riga CRLF: con il solo LF `cmd.exe` può non trovare le etichette.

## 2. Data e ora indipendenti dalla lingua di sistema

`%DATE%` e `%~t` dipendono dalle impostazioni internazionali e non vengono usati.

- **Ora locale**: robocopy scrive le proprie righe di errore con un prefisso fisso `aaaa/mm/gg hh:mm:ss`; gli script lanciano robocopy su una sorgente non valida (`"|"`) con `/L` e leggono quella riga (`:Now`).
- **Ora UTC**: `robocopy /TS` elenca le date dei file in UTC con lo stesso formato. All'avvio viene creato ed elencato un file temporaneo (`:ClockInit`); ora locale meno ora UTC, arrotondata a 15 minuti, è lo scostamento dall'UTC.
- **Epoch**: le date sono convertite con l'algoritmo days-from-civil in aritmetica `set /a` a 32 bit (valida fino al 19-01-2038).
- **Orario del log**: `%TIME%` diviso su qualsiasi separatore (`:` `.` `,` o spazio) dà ore, minuti e secondi in ogni lingua; la data viene dall'ultima lettura di robocopy e viene riletta quando l'ora torna indietro (mezzanotte).

## 3. Dati del disco indipendenti dalla lingua

- Byte liberi: terzo elemento dell'ultima riga di `dir /-c` (`<n> Dir(s) <byte> bytes free` in ogni lingua).
- Byte totali: seconda riga di `fsutil volume diskfree <percorso>`, solo le cifre (i separatori delle migliaia dipendono dalla lingua).
- Totali dell'archivio: riepilogo di `robocopy <archivio> <vuota> *.7z /L /S /NFL /NDL /BYTES` (nessuna riga per file). Dopo la riga `-----` le righe numeriche sono, in quest'ordine, cartelle, file e byte (colonna *Total*), in qualunque lingua. Prima si usava un `for /f` su `dir /s`: legge una riga per ogni archivio e con centinaia di migliaia di archivi (un anno di log traffic) impiegava ore, così le metriche finali non venivano mai inviate. Misurato su 400.000 archivi: robocopy 3 s, intera fase statistiche 25 s. La riga di log `98` ne riporta la durata.
- Numeri oltre 2^31: confronti su stringhe allineate con zeri (`:BigLess`), somme in due parti da 9 cifre (`:BigAdd` e contatori in linea), percentuali sulle prime 5 cifre significative (`:Percent`).

## 4. Lock e registro

- **Una sola esecuzione per istanza**: lo script tiene aperto in scrittura `panos_csv_archiver_<id>.lock` (`9>"file" call :Main`). Una seconda esecuzione non riesce ad aprirlo ed esce con codice 20. L'handle appartiene al processo, quindi Windows lo rilascia anche se l'esecuzione viene interrotta: nessun lock orfano.
- **Registro delle istanze** (`panos_csv_archiver.registry`, creato automaticamente, righe `id|ultimo_epoch`): aggiornato sotto un secondo file di lock, riscritto in un file temporaneo, ordinato, privato dei duplicati e spostato sopra l'originale (sostituzione atomica). Le voci più vecchie di `INSTANCE_RETENTION_DAYS` vengono eliminate.
- Il registro viene aggiornato e la discovery inviata **prima** dei controlli su percorso e prerequisiti, così Zabbix crea gli item e riceve anche le metriche di errore.

## 5. Controllo dei percorsi (`ALLOW_REMOTE_PATHS=0`)

Per la cartella sorgente e quella dei log (`:CheckLocalPath`):

- prefisso `\\` (UNC, percorsi `\\?\`): rifiutato;
- unità SUBST: viene controllata la destinazione reale;
- `net use X:` riesce: unità di rete mappata, rifiutata;
- `mountvol X:\ /L` fallisce: non è un volume locale (solo i volumi locali hanno un GUID), rifiutata;
- ogni componente esistente del percorso viene controllato per l'attributo reparse; la destinazione di link simbolici e junction viene letta da `dir /a:l` e deve essere locale (`Volume{...}`, un'unità locale o un percorso relativo).

I motivi inviati a Zabbix non contengono mai nomi di cartelle.

## 5b. Cartella archivio (`/archive`)

- `ARCHIVE_DIR` è la cartella sorgente oppure la cartella `/archive`. Deve stare sullo stesso volume, così `move` è una rinomina: istantanea, atomica, e spazio libero e metriche del disco restano quelli di un unico volume.
- Volume di un percorso (`:VolumeId`): prima vengono risolte le unità SUBST; poi si risale il percorso finché `mountvol "<cartella>\\" /L` restituisce un nome `\\?\Volume{...}` (un punto di montaggio o la radice dell'unità). Un link incontrato lungo il percorso rende il volume sconosciuto e la cartella viene rifiutata: una junction potrebbe puntare a un altro volume.
- La barra finale viene raddoppiata in `mountvol "percorso\\" /L`: con una sola il runtime C legge `\"` come una virgoletta con escape, mountvol stampa il suo aiuto con exit code 0 e la prima parola dell'aiuto verrebbe presa per un nome di volume. Sono accettati solo valori che iniziano con `\\?\Volume{`.
- Albero dell'archivio, recupero, totali, conteggio giornaliero e rotazione usano `ARCHIVE_DIR`; l'elenco dei CSV da archiviare e dei file in attesa usa la cartella sorgente.

## 6. Zabbix

- Il monitoraggio non blocca mai l'archiviazione: le metriche vengono inviate solo con `ZABBIX_ENABLED=1` e `zabbix_sender` presente. Senza sender il registro viene comunque aggiornato (la discovery includerà l'istanza quando il sender tornerà) e `sender_status.txt` va a 0. Con `ZABBIX_ENABLED=0` non c'è aggiornamento del registro, discovery né metrica, e `ZABBIX_SERVER` / `ZABBIX_HOST` non vengono controllati.
- LLD: il JSON `[{"{#INSTANCE}":"id"},...]` viene scritto in un file di input di zabbix_sender con le virgolette come `\"` (sulla riga di comando `cmd.exe` le eliminerebbe). Viene sempre inviato un array, anche con una sola istanza.
- Tutte le metriche di un'esecuzione vanno in un unico file e in un'unica chiamata a zabbix_sender.
- Codici di uscita di zabbix_sender: `0` inviato, `1` errore (ripetuto), `2` il server ha risposto ma ha rifiutato alcuni o tutti i valori (non ripetuto, conteggiato come errore). Alla prima esecuzione di una nuova istanza il codice 2 è considerato temporaneo (LLD e cache di configurazione sono asincrone): la discovery viene reinviata e le metriche ritentate una volta dopo `NEW_INSTANCE_DELAY`.
- Più destinazioni (`:SenderTarget`): con `,` o `;` in `ZABBIX_SERVER` lo script scrive una configurazione agent temporanea con `ServerActive=...` (alle voci senza porta viene aggiunta `ZABBIX_PORT`) e chiama `zabbix_sender -c` invece di `-z`/`-p`, che accettano un solo indirizzo. zabbix_sender invia in parallelo alle destinazioni separate da virgola, e ai nodi separati da punto e virgola in ordine finché uno risponde (cluster HA). Misurato con zabbix_sender 7.0 verso Zabbix 7.0 e 7.4: entrambi raggiungibili, codice 0; uno rifiuta i valori o non è raggiungibile, codice 2 e l'altro riceve i dati; nessuno raggiungibile, codice 1. Il codice 2 quindi non viene ripetuto (un nuovo tentativo invierebbe due volte i valori al server che li ha ricevuti; solo il nuovo tentativo per una nuova istanza descritto sopra può farlo, senza conseguenze) e nel log diventa *At least one Zabbix destination rejected the values or was unreachable*.
- `panos.csv.sender.status` è l'esito della trasmissione finale **precedente** (quella corrente non può riferire su se stessa); parte da 1 per non generare un falso allarme alla prima esecuzione.
- I valori non misurabili (spazio libero con percorso rifiutato, totali dell'archivio) vengono omessi, mai inviati come 0, per evitare falsi allarmi.
- Template: item trapper con `allowed_hosts = {$PANOS.CSV.ALLOWED.HOSTS}` (un valore vuoto rifiuta tutto, da qui il default `0.0.0.0/0,::/0`); le soglie usano macro di contesto `{$MACRO:"{#INSTANCE}"}`; gli allarmi sul conteggio giornaliero confrontano `last()` con `avg(...,{$PANOS.CSV.DAY.FILES.BASELINE}:now-1d)`. *No new CSV files for …* usa `max(files.processed, periodo)=0` (il valore è inviato una volta per esecuzione, nel report finale) ed è valutato solo se esiste un valore più vecchio del periodo, così un'istanza nuova con la cartella vuota non genera allarmi; dipende dai trigger di errore, e *Daily CSV files decreased* dipende da lui. Non esiste di proposito un trigger separato per i file falliti: un file fallito rende già l'esecuzione *Failed* o *Partial*.

## 7. Ciclo di archiviazione e prestazioni

- L'elenco dei CSV viene da `robocopy /L /TS` (dimensione, ora UTC, percorso completo) e viene letto prima di spostare qualsiasi file.
- In batch una `call` costa circa 20 ms, quindi il codice per file (`:ProcessFile`) usa pochissime call: i giorni di ogni data e la cartella del giorno sono memorizzati in variabili (`PC_D...`, `PC_N...`), contatori e controlli di spazio sono in linea. Risultato: circa 0,3 s per file più 7-Zip, invece di circa 1 s.
- Controllo dello spazio: gestito in MB (sicuro a 32 bit) e riletto dal disco ogni 50 file, oppure a ogni file quando si è entro 1 GB dalla riserva. L'archiviazione non riduce mai lo spazio libero più della dimensione del file, perché il CSV viene cancellato dopo la verifica dell'archivio.
- 7-Zip: con il solo `-mx9`, LZMA2 usa un unico blocco per un file da 40-50 MB e lavora un solo core. `-m0=LZMA2:c=8m -mmt=on` divide il file in blocchi da 8 MB compressi in parallelo: circa 2,7 volte più veloce su 4 core, meno memoria (circa 50 MB per thread), archivi più grandi di circa lo 0,5%. Le opzioni vengono verificate a ogni avvio.

## 8. Ciclo di vita dei file e recupero

```
sorgente\x.csv -> sposta -> cartella del giorno\x.csv -> 7z a -> x.7z -> 7z t -> cancella cartella del giorno\x.csv
```

- I file modificati da meno di `MIN_FILE_AGE_MINUTES` vengono saltati (caricamento in corso). L'esecuzione resta un successo: i file in attesa sono controllati dal trigger dei "pending".
- Un archivio o un CSV con lo stesso nome già presente nella cartella del giorno è un errore: nulla viene sovrascritto.
- Un nuovo archivio fallito o non valido viene cancellato (è stato creato da questa esecuzione); il CSV resta nella cartella del giorno e viene recuperato all'esecuzione successiva.
- Recupero (`:RecoverOrphans`) per ogni CSV dentro una cartella del giorno: archivio mancante → nuova archiviazione; archivio valido che contiene lo stesso file con la stessa dimensione → cancellazione del CSV; altrimenti l'archivio viene rinominato `*.7z.invalid-<epoch>` (mai cancellato) e il CSV archiviato di nuovo.
- Data della cartella del giorno: prima sequenza `AAAA MM GG` nel nome del file (separatori `_` o `-`, controllo di data reale con andata e ritorno), altrimenti data di modifica; meno un giorno per le modalità `*previous_day`.
- Nome della cartella del mese (`MONTH_FOLDER_NAME`): nessuno, inglese o italiano. Le cartelle di tutte le varianti, e del formato precedente alla 1.0 `MM-AAAA (Mese)\GG-MM-AAAA` direttamente nella cartella sorgente, sono incluse in totali, recupero, conteggi e ricerche.

## 9. Conteggio giornaliero dei file

Il giorno contato è oggi meno `DAY_COUNT_LAG_DAYS` (`auto`: 1, oppure 2 per le modalità `*previous_day`, le cui cartelle si completano un giorno dopo); prima di `DAY_COMPLETE_HOUR` si torna indietro di un altro giorno. L'impostazione presuppone che gli export del firewall finiscano prima dell'avvio delle attività di archiviazione (per esempio export di notte, attività al mattino). Il valore viene inviato a ogni esecuzione, quindi la media sul periodo di riferimento è la media dei conteggi giornalieri.

## 10. Output a schermo, debug e lingua

- `CONSOLE_OUTPUT=1` (o `/console`): intestazione, ogni riga del log e un riepilogo finale a schermo; il file di log non cambia.
- `DEBUG_OUTPUT=1` (o `/debug`): anche valori interni (scostamento UTC, controllo dei percorsi, opzioni), la cartella del giorno di ogni file, le letture dello spazio libero, i dati inviati a Zabbix, `zabbix_sender -vv` e l'output di 7-Zip. L'output dei programmi esterni è controllato dalla variabile `QUIET` (`>nul 2>&1` oppure vuota), espansa come `%QUIET%`.
- `LANGUAGE` (`en`/`it`, nella ricerca anche `/lang`): sono tradotti solo i messaggi a schermo (etichette `L_*` caricate da `:LangLoad`). Righe del log, valori Zabbix e contenuto dei file restano in inglese, per poterli confrontare e filtrare.
- Tutte e tre si possono impostare come variabili d'ambiente prima della chiamata, senza modificare lo script.
- Formato delle righe di log: `[AAAA-MM-GG hh:mm:ss] LIVELLO (code NN) | messaggio`. Il livello è INFO, SUCCESS, WARNING o FAILURE; il codice identifica l'evento (es. 10 file archiviato, 11 file fallito, 98 statistiche dell'archivio, 99 invio finale), non è un numero di errore.
- Le uscite anticipate (configurazione, argomenti) scrivono sempre un messaggio su stderr.

## 11. Strumento di ricerca

- Gli archivi vengono letti una sola volta, come flusso: `7z e -so -bso0 -bsp0 archivio | findstr ... > risultati`. Nessuna estrazione temporanea; qualsiasi messaggio di 7-Zip su stderr segna l'archivio come illeggibile.
- I valori cercati vengono scritti in file e passati a `findstr /g:`: funziona qualsiasi carattere (`! & % "`), e più valori di un criterio sono in OR. Ogni criterio è uno stadio `findstr` della pipe (AND).
- Criteri sugli IP: un'espressione regolare ancorata all'inizio della riga salta le colonne precedenti (`^[^,]*,...` poi `"*VALORE"*,`), quindi deve corrispondere l'intero campo. Prima viene eseguito uno stadio letterale `findstr /l` sul valore semplice, così il controllo della colonna riceve poche righe.
- Criterio utente: `findstr` non riesce a saltare 12-13 colonne (le sue espressioni regolari hanno un limite di complessità: circa 14 classi di caratteri), quindi la pipe seleziona le righe che contengono il valore e lo script controlla poi le colonne utente solo di quelle righe.
- Le posizioni delle colonne vengono dall'intestazione del CSV del primo archivio del periodo; se i nomi mancano si usano le posizioni standard PAN-OS.
- Le righe di intestazione dei CSV vengono escluse dai risultati (`findstr /v /x /l` sull'intestazione).
- Gli archivi vengono elencati direttamente per cartella del giorno; il filtro sul periodo lavora sui nomi delle cartelle, quindi un periodo breve legge poche cartelle.

## 11b. Archiviazione degli export di configurazione

- `panos_config_archiver.bat` è generato da `panos_csv_archiver.bat` e resta uno script indipendente di proposito: una modifica a un tipo di job non può influire sull'altro. La logica comune (ora, lock, controllo dei percorsi, recupero, Zabbix) è identica.
- Differenze: estensione `FILE_EXT` / `/ext` invece di `.csv` (validata: lettere e cifre, massimo 10); `-mx0` (store) per le estensioni in `STORE_EXTENSIONS`, deciso una volta all'avvio e usato anche dal test delle opzioni di 7-Zip; nome dell'archivio `<nome originale>.7z`; date compatte (un token di 8-14 cifre viene letto come `AAAAMMGG[hhmm[ss]]` e passa dallo stesso controllo di data reale e dalla stessa cache); registro, lock, log e file temporanei propri (`panos_config_archiver*`, `panos_cfg_*`); chiavi Zabbix `panos.cfg.*`.
- Chiave di discovery separata (`panos.cfg.discovery`): con una chiave comune ogni script invierebbe solo le proprie istanze e Zabbix segnerebbe come perse quelle dell'altro.

## 12. Limiti

- I percorsi non devono contenere `!`, `%` o `^`. Con la delayed expansion un `!` viene eliminato senza errori, quindi `D:\FW!01` diventerebbe `D:\FW01` e potrebbe essere archiviata (o cercata) un'altra cartella esistente. Lo script di archiviazione parte quindi con la delayed expansion disattivata, legge la configurazione, controlla argomenti, cartella dello script, `LOG_DIR` e percorsi dei programmi (`for /f "delims=!^%%"` sul percorso completo) e solo dopo la attiva: exit 10 prima di toccare qualsiasi file. Lo script di ricerca controlla allo stesso modo la cartella (riga di comando o modalità guidata) e la propria cartella, prima di normalizzarla. Spazi, parentesi e `&` sono supportati (testati).
- Log mensili: `LOG_RETENTION_MONTHS` conta i mesi interi conservati oltre a quello in corso, così è sempre disponibile almeno quel numero di mesi di storico (con 6, il 1° ottobre restano i log da aprile in poi).
- I CSV con `!` nel nome falliscono singolarmente (file lasciato al suo posto, exit 1). `|`, `<` e `>` non possono comparire nei nomi di file Windows.
- Le date sono valide fino al 19-01-2038 (epoch a 32 bit).
- `mountvol` e `fsutil` sono stati testati con un account amministratore: verificarli con l'account delle attività pianificate.
