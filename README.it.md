# PAN-OS Export Archiver

![PAN-OS](https://img.shields.io/badge/PAN--OS-Log%20%26%20Config%20Export-blue)
![Zabbix](https://img.shields.io/badge/Zabbix-7.0%2B-red)
![Windows](https://img.shields.io/badge/Windows-batch%2C%20no%20PowerShell-0078D6)
![License: MIT](https://img.shields.io/badge/License-MIT-lightgrey)

[English](README.md) | **Italiano**

Archiviazione, monitoraggio e ricerca degli export di log e configurazioni dei firewall Palo Alto Networks e di Panorama su Windows, con semplici script batch.

PAN-OS può esportare i propri log (traffic, threat, URL, WildFire, ...) in file CSV verso un server FTP/SCP con la funzione **Scheduled Log Export**. Nessuno gestisce poi quei file: su un firewall molto attivo ogni giorno si accumulano migliaia di CSV di grandi dimensioni. Questo progetto:

- **archivia** ogni CSV in un albero di cartelle per data (`AAAA\MM-AAAA\GG-MM-AAAA`), compresso con 7-Zip e verificato prima di cancellare l'originale;
- **monitora** i job di archiviazione con Zabbix 7 (opzionale): stato dei job, numero di file, spazio disco, volumi giornalieri anomali;
- **cerca** nell'archivio per IP sorgente/destinazione, utente o testo libero, indicando il giorno e il file di ogni risultato;
- **archivia anche gli export di configurazione** (Scheduled Config Export di Panorama `.tgz`, `.xml` dei firewall, ...) con uno script e un template dedicati.

| Strumento | Scopo |
|---|---|
| `panos_csv_archiver.bat` | Archivia gli export CSV dei log, invia le metriche a Zabbix |
| `panos_config_archiver.bat` | Archivia gli export di configurazione (`.tgz`, `.xml`, ...) con le stesse logiche |
| `panos_csv_search.bat` | Cerca nei log CSV archiviati per IP, utente o testo |
| `zabbix/*.yaml` | Due template Zabbix 7 (log CSV, configurazioni) che possono stare sullo stesso host |

Tutto funziona con `cmd.exe`, programmi standard di Windows, 7-Zip e (se serve) `zabbix_sender`: niente PowerShell e nessun runtime da installare.

> Progetto indipendente, non affiliato né approvato da Palo Alto Networks. PAN-OS e Palo Alto Networks sono marchi di Palo Alto Networks, Inc.

---

## Indice

- [Funzionalità](#funzionalità)
- [Come funziona](#come-funziona)
- [Requisiti](#requisiti)
- [Avvio rapido](#avvio-rapido)
- [Installazione](#installazione)
- [Configurazione](#configurazione)
- [Struttura dell'archivio e recupero](#struttura-dellarchivio-e-recupero)
- [Monitoraggio con Zabbix](#monitoraggio-con-zabbix)
- [Strumento di ricerca](#strumento-di-ricerca)
- [Export di configurazione](#export-di-configurazione)
- [Output a schermo e debug](#output-a-schermo-e-debug)
- [Codici di uscita](#codici-di-uscita)
- [Prestazioni](#prestazioni)
- [Limiti](#limiti)
- [Contenuto del repository](#contenuto-del-repository)
- [Note sullo sviluppo](#note-sullo-sviluppo)
- [Licenza](#licenza)

## Funzionalità

**Archiviazione** (`panos_csv_archiver.bat`)
- Un'attività pianificata per cartella sorgente (una per firewall e tipo di log), stesso script per tutte.
- Albero dell'archivio nella cartella sorgente, oppure in un'altra cartella dello stesso volume (`/archive`).
- Cartella del giorno ricavata dalla data nel nome del file PAN-OS o dalla data di modifica; a scelta spostata al giorno dei log contenuti.
- Compressione 7-Zip massima con blocchi LZMA2 in parallelo (circa 2,7 volte più veloce di `-mx9` semplice su file da 40-50 MB, archivi più grandi di circa lo 0,5%).
- Ogni archivio viene testato prima di cancellare il CSV; i file esistenti non vengono mai sovrascritti.
- I file ancora in caricamento (modificati da poco) vengono lasciati all'esecuzione successiva.
- Recupero automatico delle esecuzioni interrotte dopo lo spostamento: gli archivi incompleti vengono messi da parte, mai cancellati.
- Controllo dello spazio libero per ogni file con una riserva configurabile: un disco quasi pieno non blocca l'archiviazione.
- Protezione: le cartelle sorgente e dei log devono stare su dischi locali (percorsi UNC, unità di rete, SUBST e link verso la rete vengono rifiutati prima di toccare qualsiasi file).
- Una sola esecuzione per istanza (lock su handle di file, rilasciato da Windows anche se l'esecuzione viene interrotta).
- Log locali mensili con conservazione automatica (minimo 6 mesi); i nomi dei file possono essere nascosti.
- Silenzioso nelle attività pianificate; modalità `/console` e `/debug` per le esecuzioni manuali.
- Messaggi a schermo in inglese o in italiano.

**Monitoraggio** (Zabbix 7.0 o successivo, opzionale)
- Low-level discovery: ogni attività pianificata compare da sola in Zabbix.
- 34 item e 18 trigger per istanza: esecuzioni fallite o parziali, job bloccati o non eseguiti, prerequisiti mancanti, percorsi rifiutati, poco spazio disco (in percentuale), file in attesa, esecuzioni interrotte, numero di file giornaliero anomalo, archivi più vecchi del periodo di conservazione.
- Soglie personalizzabili per istanza con le macro di contesto.
- La mancanza di `zabbix_sender` non blocca mai l'archiviazione.

**Ricerca** (`panos_csv_search.bat`)
- Modalità guidata (doppio clic, oppure trascinare una cartella dei log sullo script) o riga di comando.
- Ricerca per campo: un IP viene confrontato con l'intero campo *Source address* / *Destination address* (`192.0.2.1` non trova `192.0.2.10` né le colonne NAT); gli utenti vengono cercati nelle colonne degli utenti.
- Criteri combinabili (sorgente E destinazione, IP E utente), più valori per criterio, jolly `*`, qualsiasi carattere nel testo libero.
- Ogni archivio viene letto una sola volta, direttamente dal `.7z`, senza estrarlo su disco.
- Risultati in CSV con il giorno e il nome dell'archivio di ogni riga, più un riepilogo.

## Come funziona

```
 PAN-OS Scheduled Log Export
          |  FTP / SCP
          v
 D:\FTP\FW01-TRAFFIC\FW01_traffic_2026_04_02_last_calendar_day_0.csv
          |
          |  panos_csv_archiver.bat  (Utilita' di pianificazione, un'attivita' per cartella)
          v
 D:\FTP\FW01-TRAFFIC\2026\04-2026\02-04-2026\FW01_traffic_..._0.7z
          |                                   |
          | zabbix_sender (opzionale)         | panos_csv_search.bat
          v                                   v
 Zabbix: template PAN-OS CSV Archiver   results\search_....csv
```

Per ogni CSV lo script di archiviazione: individua la cartella del giorno, ci sposta il file, lo comprime in `.7z`, testa l'archivio, cancella il CSV e alla fine invia a Zabbix le metriche dell'esecuzione.

## Requisiti

- Windows 10 / Windows Server 2016 o successivi (sviluppato e testato su Windows 11).
- [7-Zip](https://www.7-zip.org/) (`7z.exe`).
- Opzionale, per il monitoraggio: server o proxy Zabbix 7.0 LTS o successivo e `zabbix_sender.exe` (incluso nei pacchetti Zabbix agent / agent 2 per Windows).
- Un account per le attività pianificate con: lettura/scrittura sulle cartelle sorgente, scrittura sulla cartella degli script e sulla cartella dei log.
- Programmi standard di `%SystemRoot%\System32` (sempre presenti): robocopy, findstr, sort, mountvol, net, subst, ping, fsutil.

## Avvio rapido

```bat
rem 1. Copiare gli script in una cartella locale
rem 2. Modificare la sezione "Configuration" di panos_csv_archiver.bat
rem    (ZABBIX_ENABLED=0 per partire senza Zabbix, e LOG_DIR; LANGUAGE=it per i messaggi in italiano)
rem 3. Provare su una copia di una cartella sorgente:
panos_csv_archiver.bat "D:\Test\FW01-TRAFFIC" "fw01-traffic" /console
rem 4. Cercare:
panos_csv_search.bat "D:\Test\FW01-TRAFFIC" /from 02-04-2026 /src 192.0.2.10 /lang it
```

## Installazione

1. **7-Zip** – installarlo (percorso predefinito `C:\Program Files\7-Zip\7z.exe`).
2. **Script** – copiare `panos_csv_archiver.bat`, `panos_csv_search.bat` e (per gli export di configurazione) `panos_config_archiver.bat` in una cartella locale, per esempio `C:\Scripts\PaloAlto\panos-export-archiver\`. La cartella deve essere scrivibile dall'account delle attività (vi vengono creati il registro delle istanze e i file di lock).
3. **Configurazione** – modificare l'inizio di `panos_csv_archiver.bat` (vedi [Configurazione](#configurazione)). Finché resta un `<segnaposto>`, lo script si ferma con codice 15 e indica quale valore manca.
4. **Zabbix** (opzionale)
   1. Installare `zabbix_sender.exe` (pacchetto Zabbix agent) e impostare `ZABBIX_SENDER_PATH`.
   2. *Data collection > Templates > Import*: `zabbix/zbx7_template_panos_csv_archiver.yaml`.
   3. Collegare il template *PAN-OS CSV Archiver by Zabbix trapper* all'host indicato in `ZABBIX_HOST` (se l'host è monitorato da un proxy, `ZABBIX_SERVER` deve essere quel proxy).
   4. Impostare sull'host la macro `{$PANOS.CSV.ALLOWED.HOSTS}` con l'indirizzo del server Windows. Non lasciarla mai vuota: con un valore vuoto Zabbix rifiuta tutti i dati.
   5. Con più destinazioni indipendenti in `ZABBIX_SERVER`, ripetere i passi 2-4 su ognuna, con lo stesso nome host.
5. **Prima esecuzione** – su una copia di una cartella sorgente, con l'account delle attività:
   ```bat
   panos_csv_archiver.bat "D:\Test\FW01-TRAFFIC" "fw01-traffic" /console
   ```
   Atteso: `Esito : SUCCESS - exit code 0` (con `LANGUAGE=it`), gli archivi in `AAAA\MM-AAAA\GG-MM-AAAA` e (con Zabbix) l'istanza scoperta dopo la prima esecuzione.
   Per tenere gli archivi fuori dalla cartella FTP aggiungere `/archive "D:\Archivio\FW01-TRAFFIC"` (vedi [Cartella archivio](#cartella-archivio)).
6. **Attività pianificate** – una per ogni cartella sorgente:
   - Programma: `C:\Scripts\PaloAlto\panos-export-archiver\panos_csv_archiver.bat`
   - Argomenti: `"D:\FTP\FW01-TRAFFIC" "fw01-traffic"` (eventualmente `/archive "D:\Archivio\FW01-TRAFFIC"`)
   - Eseguire indipendentemente dalla connessione dell'utente, con l'account di servizio.
   - Impostazioni: *Se l'attività è già in esecuzione: Non avviare una nuova istanza*.
   - Pianificazione dopo la fine degli export del firewall. Un job grande usa tutti i core durante la compressione: scaglionare le attività.

`INSTANCE_ID` (secondo argomento): lettere minuscole, cifre, `_` e `-`, al massimo 64 caratteri, unico per ogni cartella sorgente.

## Configurazione

All'inizio di `panos_csv_archiver.bat`. `LANGUAGE`, `CONSOLE_OUTPUT` e `DEBUG_OUTPUT` si possono impostare anche come variabili d'ambiente.

| Impostazione | Default | Descrizione |
|---|---|---|
| `LANGUAGE` | `en` | Messaggi a schermo: `en` o `it`. Log e dati Zabbix sono sempre in inglese. |
| `CONSOLE_OUTPUT` | `0` | `1` = avanzamento e riepilogo a schermo (come `/console`). |
| `DEBUG_OUTPUT` | `0` | `1` = anche valori interni, dati inviati a Zabbix, output di 7-Zip e zabbix_sender (come `/debug`). |
| `SEVENZIP_PATH` | `C:\Program Files\7-Zip\7z.exe` | Eseguibile di 7-Zip. |
| `SEVENZIP_OPTIONS` | `-mx9 -m0=LZMA2:c=8m -mmt=on` | Opzioni di compressione, verificate a ogni avvio (opzioni rifiutate: exit 14). `-mx9` = compressione su un solo core. |
| `ZABBIX_ENABLED` | `1` | `0` = solo archiviazione: niente metriche né discovery, impostazioni Zabbix ignorate. |
| `ZABBIX_SENDER_PATH` | `C:\Program Files\Zabbix Agent 2\zabbix_sender.exe` | Se manca, i file vengono archiviati comunque e il log lo segnala. |
| `ZABBIX_SERVER` / `ZABBIX_PORT` | segnaposto / `10051` | Server Zabbix, o il proxy che monitora l'host. Più destinazioni: `"zbx-a,zbx-b"` invia gli stessi dati in parallelo a installazioni Zabbix indipendenti, `"node1;node2"` elenca i nodi di un unico cluster HA. Una voce può avere la sua porta (`host:porta`); le altre usano `ZABBIX_PORT`. |
| `ZABBIX_HOST` | segnaposto | Nome tecnico dell'host in Zabbix. |
| `LOG_DIR` | segnaposto | Cartella locale per log e stato. |
| `LOG_DIR_FALLBACK` | `0` | `1` = un `LOG_DIR` vuoto o non configurato diventa `<cartella sorgente>\Logs`. |
| `ALLOW_REMOTE_PATHS` | `0` | `1` = ammette percorsi di rete per le cartelle sorgente e dei log. |
| `DISK_RESERVE_BYTES` | `2147483648` (2 GB) | Un file viene archiviato solo se lo spazio libero è >= dimensione del file + riserva. |
| `DAY_FOLDER_DATE` | `filename` | `filename` = data nel nome del file (giorno dell'export); `filename_previous_day` = il giorno prima (giorno dei log); `modified` / `previous_day` = data di modifica / il giorno prima. |
| `MONTH_FOLDER_NAME` | `none` | Cartella del mese `09-2026`; `en` = `09-2026 (September)`; `it` = `09-2026 (Settembre)`. |
| `DAY_COUNT_LAG_DAYS` | `auto` | Giorno misurato dal conteggio giornaliero: ieri, oppure l'altro ieri con le modalità `*previous_day`. |
| `DAY_COMPLETE_HOUR` | `7` | Prima di quest'ora si torna indietro di un altro giorno (il giorno deve essere completo). |
| `LOG_FILE_NAMES` | `0` | `1` = nomi dei CSV nel log locale (mai inviati a Zabbix). |
| `MIN_FILE_AGE_MINUTES` | `5` | I file più recenti vengono lasciati all'esecuzione successiva. In produzione tenerlo sopra 0. |
| `LOG_RETENTION_MONTHS` | `6` | Mesi interi di log conservati oltre al mese in corso (minimo 6): con 6, il 1° ottobre restano i log da aprile in poi. |
| `INSTANCE_RETENTION_DAYS` | `45` | Le istanze senza esecuzioni escono dal registro e dalla discovery. |
| `NEW_INSTANCE_DELAY` | `30` | Secondi di attesa per la discovery di una nuova istanza (un nuovo tentativo se Zabbix non è pronto). |
| `*_RETRY_COUNT` / `*_RETRY_DELAY` | `3` / `5` | Tentativi e pausa di zabbix_sender. |

## Cartella archivio

```bat
panos_csv_archiver.bat "CARTELLA_SORGENTE" "ID_ISTANZA" [/archive "CARTELLA_ARCHIVIO"] [/console o /debug]
```

- Senza `/archive` l'albero dell'archivio viene creato dentro la cartella sorgente.
- Con `/archive` viene creato in `CARTELLA_ARCHIVIO`, che deve stare **sullo stesso volume** della cartella sorgente: spostare un CSV è così una rinomina (istantanea e atomica), mai una copia. La cartella viene creata se manca.
- Una cartella su un altro volume, un percorso di rete o un percorso che contiene un link simbolico o una junction vengono rifiutati (exit 13, trigger *Path rejected*) prima di toccare qualsiasi file.
- Usare una cartella archivio diversa per ogni istanza: lo script non può accorgersi di due attività che ne condividono una.
- Gli archivi già creati nella cartella sorgente non vengono spostati: prima di cambiare, spostare le cartelle degli anni nella nuova posizione (stesso volume, istantaneo).
- Lo strumento di ricerca lavora sulla cartella archivio; per cercare nei CSV non ancora archiviati (`/unarchived`) va lanciato sulla cartella sorgente.

## Struttura dell'archivio e recupero

```
D:\FTP\FW01-TRAFFIC\                      cartella sorgente (oppure la cartella /archive)
  2026\
    04-2026\
      02-04-2026\
        FW01_traffic_2026_04_02_last_calendar_day_0.7z
        FW01_traffic_2026_04_02_last_calendar_day_1.7z
        report\FAILED-JOB.txt             solo se un file di quel giorno e' fallito
```

- Un file con lo stesso nome già presente nella cartella del giorno è un errore: nulla viene sovrascritto.
- Un CSV rimasto nella cartella del giorno per un'esecuzione interrotta viene completato all'esecuzione successiva: archiviato se l'archivio non esiste, cancellato se un archivio valido contiene già lo stesso file con la stessa dimensione; un archivio incompleto o diverso viene rinominato `*.7z.invalid-<epoch>` e segnalato.
- Lo script non cancella mai gli archivi: la rotazione è a cura dell'utente. Zabbix riceve la dimensione totale, il numero di archivi e il giorno archiviato più vecchio.

## Monitoraggio con Zabbix

Template **PAN-OS CSV Archiver by Zabbix trapper** (`zabbix/zbx7_template_panos_csv_archiver.yaml`, formato di export 7.0, testato su Zabbix 7.0, 7.2 e 7.4). Tutti gli item sono di tipo trapper con chiave `panos.csv.*[<INSTANCE_ID>]`, creati dalla regola di discovery `panos.csv.discovery`. I problemi hanno i tag `instance=<INSTANCE_ID>` e `component=job|storage|health`.

| Trigger | Gravità |
|---|---|
| Last execution failed | High |
| Last execution completed partially | Warning |
| Job running too long | High |
| No recent job metrics | High |
| No completed execution within `{$PANOS.CSV.JOB.MAX.AGE}` | High |
| No successful execution within expected period | High |
| No new CSV files for `{$PANOS.CSV.NO.FILES.MAX.AGE}` | High |
| Required programs missing | High |
| Path rejected, not on a local disk | High |
| Source files pending on two consecutive runs | Warning |
| Source disk free space below `{$PANOS.CSV.DISK.MIN.PFREE}`% | Warning |
| Disk usage data missing | Warning |
| CSV files left inside archive folders | Warning |
| Invalid archives set aside, manual review needed | Warning |
| Daily CSV files increased / decreased by more than `{$PANOS.CSV.DAY.FILES.CHANGE.PCT}`% | Warning |
| Previous final sender transmission failed | Warning |
| Archives older than retention, manual rotation due | Info |

| Macro | Default | Significato |
|---|---|---|
| `{$PANOS.CSV.ALLOWED.HOSTS}` | `0.0.0.0/0,::/0` | Indirizzi autorizzati a inviare dati. Impostarla sul server Windows; mai vuota. |
| `{$PANOS.CSV.JOB.MAX.DURATION}` | `8h` | Durata massima di un'esecuzione. |
| `{$PANOS.CSV.JOB.MAX.AGE}` | `26h` | Tempo massimo senza dati / senza un'esecuzione completata. |
| `{$PANOS.CSV.JOB.SUCCESS.MAX.AGE}` | `26h` | Età massima dell'ultima esecuzione riuscita. |
| `{$PANOS.CSV.NO.FILES.MAX.AGE}` | `3d` | Tempo massimo senza alcun CSV archiviato mentre il job continua a girare: l'export del firewall non arriva (massimo `30d`). |
| `{$PANOS.CSV.PENDING.MAX}` | `0` | File ammessi nella cartella sorgente per due esecuzioni consecutive. |
| `{$PANOS.CSV.DISK.MIN.PFREE}` | `10` | Avviso sullo spazio libero, in percentuale del volume. |
| `{$PANOS.CSV.DAY.FILES.BASELINE}` | `7d` | Periodo di riferimento per il conteggio giornaliero dei file. |
| `{$PANOS.CSV.DAY.FILES.CHANGE.PCT}` | `50` | Variazione del conteggio giornaliero che fa scattare l'allarme. |
| `{$PANOS.CSV.ARCHIVE.ROTATION.AGE}` | `365d` | Età del giorno archiviato più vecchio oltre la quale serve una rotazione. |

Ogni soglia accetta un contesto per istanza, per esempio `{$PANOS.CSV.JOB.MAX.DURATION:"fw01-traffic"} = 10h`.

## Strumento di ricerca

```bat
rem Guidata: doppio clic su panos_csv_search.bat, oppure trascinarci sopra una cartella dei log
rem Riga di comando:
panos_csv_search.bat "D:\FTP\FW01-TRAFFIC" /from 01-04-2026 /to 05-04-2026 /src 192.0.2.10 /lang it
panos_csv_search.bat "D:\FTP\FW01-TRAFFIC" /from 02-04-2026 /src 192.0.2.10 /dst 198.51.100.7
panos_csv_search.bat "D:\FTP\FW01-TRAFFIC" /from * /user "jdoe asmith"
```

| Criterio | Opzione | Confrontato con |
|---|---|---|
| IP sorgente | `/src` | l'intero campo *Source address* |
| IP destinazione | `/dst` | l'intero campo *Destination address* |
| IP sorgente o destinazione | `/ip` | uno dei due campi |
| Utente | `/user` | *Source User* o *Destination User*, anche parziale, senza distinguere maiuscole |
| Testo libero | `/text` | in qualsiasi punto della riga, senza distinguere maiuscole |

- Più valori in un criterio (separati da spazio) = basta uno; più criteri = devono valere tutti.
- `*` è un jolly: `192.0.2.*`.
- Periodo: date delle cartelle giornaliere (`GG-MM-AAAA`), default ieri; `/from *` = tutto l'archivio. `/unarchived` cerca anche nei CSV non ancora archiviati.
- Risultati in `results\` accanto allo script: `<nome>.csv` con le colonne `Giorno,File,<colonne originali>` e `<nome>_riepilogo.txt` (file con risultati, file illeggibili). In inglese: `Day` e `_summary`.
- Opzioni: `/out NOME`, `/lang en|it`, `/debug`, `/?`.
- Codici di uscita della ricerca: `0` righe trovate, `1` nessuna, `2` alcuni file illeggibili (risultato forse incompleto), `10` input non valido, `14` 7-Zip o orologio di sistema non disponibili.

Le posizioni delle colonne vengono lette dall'intestazione dei CSV (*Source address*, *Destination address*, *Source User*, *Destination User*); se mancano, vengono usate le posizioni standard PAN-OS (8, 9, 13, 14) e lo strumento lo segnala prima di partire.

## Export di configurazione

`panos_config_archiver.bat` archivia gli export di configurazione con le stesse logiche dello script dei CSV (cartelle per data, verifica prima di cancellare l'originale, recupero, controllo dei percorsi, metriche Zabbix), come job indipendente con il suo template.

- **Sorgenti**: Panorama può esportare la propria configurazione (e quelle dei firewall gestiti) in modo pianificato con **Scheduled Config Export** (file `.tgz` su un server FTP/SCP). I firewall non hanno un export pianificato: qualunque file di configurazione copiato in una cartella con altri mezzi (snapshot `.xml`, device state `.tgz`, script via API) può essere archiviato allo stesso modo.
- **Estensione per job**: `FILE_EXT=tgz` all'inizio dello script è il default; `/ext EST` la imposta per il singolo job (`/ext xml`, `/ext zip`). Solo lettere e cifre.
- **Data nel nome del file**: `AAAA_MM_GG`, `AAAA-MM-GG` e le forme compatte `AAAAMMGG`, `AAAAMMGGhhmm`, `AAAAMMGGhhmmss` (es. `Panorama_20261019.tgz` va in `2026\10-2026\19-10-2026`). Senza data viene usata la data di modifica, con un avviso nel log.
- **Nessuna ricompressione**: le estensioni in `STORE_EXTENSIONS` (`tgz gz zip 7z bz2 xz rar`) vengono messe nel `.7z` senza compressione; gli altri formati (es. `.xml`) vengono compressi con `SEVENZIP_OPTIONS`.
- **Nome dell'archivio**: il nome originale più `.7z` (`Panorama_20261019.tgz.7z`), così job con estensioni diverse possono condividere una cartella giorno.
- **Configurazione**: le stesse variabili dello script dei CSV, all'inizio dello script; log `panos_config_archiver_<id>_AAAA-MM.log`, registro `panos_config_archiver.registry`.
- **Zabbix**: template `zabbix/zbx7_template_panos_config_archiver.yaml` (*PAN-OS Config Archiver by Zabbix trapper*), chiavi `panos.cfg.*`, macro `{$PANOS.CFG.*}`. Si può collegare allo stesso host del template dei CSV. Allarme principale: *No new files for `{$PANOS.CFG.NO.FILES.MAX.AGE}`* (default `2d`); niente allarmi di aumento/calo giornaliero (di solito un export al giorno); `{$PANOS.CFG.JOB.MAX.DURATION}` = `1h`.

```bat
panos_config_archiver.bat "D:\FTP\PANORAMA-CONFIG" "panorama-config" /console
panos_config_archiver.bat "D:\Backup\FW01-CONFIG" "fw01-config" /ext xml
```

Task Scheduler: un'attività per job, come per i CSV, pianificata dopo l'export (es. Scheduled Config Export alle 02:00, attività alle 03:00).

## Output a schermo e debug

Le attività pianificate girano in silenzio. Per le esecuzioni manuali:

```bat
panos_csv_archiver.bat "D:\FTP\FW01-TRAFFIC" "fw01-traffic" /console
panos_csv_archiver.bat "D:\FTP\FW01-TRAFFIC" "fw01-traffic" /debug
```

`/console` mostra un'intestazione, ogni riga del log e un riepilogo finale; `/debug` mostra anche valori interni, dati inviati a Zabbix e output di 7-Zip e zabbix_sender. L'output di debug contiene il server Zabbix, il nome dell'host e i nomi dei CSV (nessuna credenziale): rivederlo prima di salvarlo in sistemi condivisi.

Log locale: `<LOG_DIR>\panos_csv_archiver_<INSTANCE_ID>_AAAA-MM.log`, righe `[AAAA-MM-GG HH:MM:SS] LIVELLO (code NN) | messaggio` (sempre in inglese), es. `[2026-10-20 08:31:41] INFO (code 98) | Archive statistics computed in 3 s`.

## Codici di uscita

| Codice | Script di archiviazione |
|---|---|
| 0 | Successo (anche senza file da archiviare) |
| 1 | Tutti i file falliti |
| 2 | Parziale: alcuni file falliti |
| 10 | Errore grave (sorgente mancante o non scrivibile, percorso con caratteri non supportati, ...) o argomento sorgente mancante |
| 11 | Argomento istanza mancante |
| 12 | `INSTANCE_ID` non valido |
| 13 | Percorso rifiutato: non su disco locale, oppure cartella archivio non sul volume della cartella sorgente |
| 14 | Prerequisiti mancanti (7-Zip, programmi di sistema, opzioni 7-Zip rifiutate, orologio di sistema) |
| 15 | Configurazione incompleta o non valida |
| 20 | Un'altra esecuzione della stessa istanza è in corso |

## Prestazioni

Misurate su una macchina di test a 4 core con log sintetici:

- Archiviazione: circa 0,3 s di overhead per file più il tempo di 7-Zip; un CSV da 46 MB ha richiesto circa 8 s con le opzioni predefinite (circa 21 s con `-mx9` semplice). 1.800 file piccoli: circa 8 minuti.
- Ricerca: circa 0,5 s per archivio da 46 MB (la decompressione di 7-Zip ne occupa circa la metà).

I log reali sono più ripetitivi di quelli sintetici e in genere si comprimono e decomprimono più in fretta.

## Limiti

- Le cartelle sorgente, archivio, dei log e dello script (e i percorsi di 7-Zip e zabbix_sender) non devono contenere `!`, `%` o `^`: lo script di archiviazione si ferma (exit 10) senza toccare alcun file, e quello di ricerca rifiuta la cartella (exit 10, o una nuova richiesta in modalità guidata). Spazi, parentesi e `&` sono supportati.
- La cartella archivio (`/archive`) deve stare sul volume della cartella sorgente e il suo percorso non deve contenere link.
- I CSV con `!` nel nome non vengono archiviati (segnalati come falliti e lasciati al loro posto). I nomi degli export PAN-OS non lo contengono mai.
- Le date sono gestite fino al 19-01-2038 (aritmetica a 32 bit di `cmd.exe`).
- Lo strumento di ricerca controlla le colonne utente con una seconda verifica in batch: valori utente molto comuni sono più lenti da cercare degli IP.
- `mountvol` e `fsutil` vanno verificati con l'account delle attività pianificate.

Dettagli: [docs/TECHNICAL_NOTES.it.md](docs/TECHNICAL_NOTES.it.md). Note per chi revisiona il codice e per le revisioni automatiche: [docs/REVIEW_NOTES.it.md](docs/REVIEW_NOTES.it.md).

## Contenuto del repository

```
panos_csv_archiver.bat                    archiviazione e monitoraggio
panos_csv_search.bat                      strumento di ricerca
panos_config_archiver.bat                 archiviazione degli export di configurazione (.tgz, .xml, ...)
zabbix/zbx7_template_panos_csv_archiver.yaml
zabbix/zbx7_template_panos_config_archiver.yaml
docs/TECHNICAL_NOTES.md  (.it.md)         funzionamento interno
docs/REVIEW_NOTES.md     (.it.md)         note per i revisori
README.md / README.it.md
CHANGELOG.md
LICENSE
```

## Note sullo sviluppo

Per sviluppo e revisione sono stati usati strumenti di coding AI. Ogni funzionalità è stata provata su Windows con esecuzioni reali di 7-Zip e su Zabbix 7.0, 7.2 e 7.4.

## Licenza

[MIT](LICENSE) © Nicola Carmelo Gurgone (N1k0droid) – https://github.com/N1k0droid
