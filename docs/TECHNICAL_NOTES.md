# Technical notes

**English** | [Italiano](TECHNICAL_NOTES.it.md)

How and why `panos_csv_archiver.bat` and `panos_csv_search.bat` work as they do. Setup and options are in the [README](../README.md).

## 1. Pure batch

PowerShell, WMIC, VBScript and `reg.exe` are not used: corporate policies often block them. Only `cmd.exe` and System32 programs are called, always with absolute paths (`%SystemRoot%\System32\...`) so that `PATH` cannot change the program that runs. The `.bat` files must keep CRLF line endings: with LF only, `cmd.exe` can fail to find labels.

## 2. Time without locale dependencies

`%DATE%` and `%~t` depend on the regional settings, so they are not used.

- **Local time**: robocopy prints its own error lines with a fixed `yyyy/mm/dd hh:mm:ss` prefix; the scripts run robocopy on an invalid source (`"|"`) with `/L` and read that line (`:Now`).
- **UTC time**: `robocopy /TS` lists file timestamps in UTC with the same format. At start a temporary file is created and listed (`:ClockInit`); local time minus UTC time, rounded to 15 minutes, is the UTC offset.
- **Epoch**: dates are converted with the days-from-civil algorithm in 32-bit `set /a` arithmetic (valid until 2038-01-19).
- **Log timestamps**: `%TIME%` split on any separator (`:` `.` `,` or space) gives hours, minutes and seconds in any locale; the date comes from the last robocopy reading and is read again when the hour goes back (midnight).

## 3. Locale-independent disk figures

- Free bytes: third token of the last line of `dir /-c` (`<n> Dir(s) <bytes> bytes free` in every language).
- Total bytes: second line of `fsutil volume diskfree <path>`, digits only (group separators depend on the locale).
- Archive totals: summary of `robocopy <archive> <void> *.7z /L /S /NFL /NDL /BYTES` (no line per file). After the `-----` line the numeric rows are, in this order, directories, files and bytes (column *Total*), in every language. A `for /f` over `dir /s` was used before: it reads one line per archive and with hundreds of thousands of archives (a year of traffic logs) it took hours, so the final metrics were never sent. Measured on 400,000 archives: robocopy 3 s, whole statistics phase 25 s. The log line `98` reports the duration.
- Numbers above 2^31: comparisons on zero-padded strings (`:BigLess`), sums in two parts of 9 digits (`:BigAdd` and inline counters), percentages on the first 5 significant digits (`:Percent`).

## 4. Locks and registry

- **One run per instance**: the archiver keeps `panos_csv_archiver_<id>.lock` open for writing (`9>"file" call :Main`). A second run cannot open it and exits with code 20. The handle belongs to the process, so Windows releases it even if the run is killed: no stale lock.
- **Instance registry** (`panos_csv_archiver.registry`, created automatically, lines `id|last_seen_epoch`): updated under a second lock file, rewritten to a temporary file, sorted, de-duplicated and moved over the original (atomic replace). Entries older than `INSTANCE_RETENTION_DAYS` are dropped.
- The registry is updated and the discovery sent **before** the path and prerequisite checks, so that Zabbix creates the items and receives the check failures too.

## 5. Path guard (`ALLOW_REMOTE_PATHS=0`)

For the source and the log folder (`:CheckLocalPath`):

- `\\` prefix (UNC, `\\?\` device paths): rejected;
- SUBST drive: the real target is checked instead;
- `net use X:` succeeds: mapped network drive, rejected;
- `mountvol X:\ /L` fails: not a local volume (only local volumes have a volume GUID), rejected;
- every existing component of the path is checked for the reparse attribute; the target of symbolic links and junctions is read from `dir /a:l` and must be local (`Volume{...}`, a local drive, or relative).

Reasons sent to Zabbix never contain folder names.

## 5b. Archive folder (`/archive`)

- `ARCHIVE_DIR` is the source folder, or the `/archive` folder. It must be on the same volume, so that `move` is a rename: instant, atomic, and free space and disk metrics stay those of a single volume.
- Volume of a path (`:VolumeId`): SUBST drives are resolved first; then the path and its parents are walked up until `mountvol "<folder>\\" /L` returns a `\\?\Volume{...}` name (a mount point or the drive root). A link met on the way makes the volume unknown, and the folder is refused: a junction could point to another volume.
- The trailing backslash is doubled in `mountvol "path\\" /L`: with a single one the C runtime reads `\"` as an escaped quote, mountvol prints its help with exit code 0, and the first word of the help would be taken as a volume name. Only values starting with `\\?\Volume{` are accepted.
- Archive tree, recovery, totals, daily count and rotation use `ARCHIVE_DIR`; the list of CSV files to archive and the pending files use the source folder.

## 6. Zabbix

- Monitoring never blocks the archiving: metrics are sent only with `ZABBIX_ENABLED=1` and `zabbix_sender` present. Without the sender the registry is still updated (the discovery will include the instance when the sender is back) and `sender_status.txt` is set to 0. With `ZABBIX_ENABLED=0` there is no registry update, discovery or metric, and `ZABBIX_SERVER` / `ZABBIX_HOST` are not checked.
- LLD: the JSON `[{"{#INSTANCE}":"id"},...]` is written to a zabbix_sender input file with quotes escaped as `\"` (on the command line `cmd.exe` would strip them). An array is always sent, also with a single instance.
- All metrics of a run go in one input file and one zabbix_sender call.
- zabbix_sender exit codes: `0` sent, `1` failure (retried), `2` the server answered but rejected some or all values (not retried, counted as a failure). On the first run of a new instance a code 2 is treated as transient (LLD and configuration cache are asynchronous): the discovery is sent again and the metrics retried once after `NEW_INSTANCE_DELAY`.
- Several destinations (`:SenderTarget`): with `,` or `;` in `ZABBIX_SERVER` the script writes a temporary agent configuration with `ServerActive=...` (entries without a port get `ZABBIX_PORT`) and calls `zabbix_sender -c` instead of `-z`/`-p`, which accept a single address. zabbix_sender sends to comma-separated destinations in parallel, and to semicolon-separated nodes in order until one answers (HA cluster). Measured with zabbix_sender 7.0 against Zabbix 7.0 and 7.4: both servers reachable, exit 0; one rejects the values or is unreachable, exit 2 and the other receives the data; both unreachable, exit 1. Code 2 is therefore not retried (a retry would send the values twice to the server that received them; only the new-instance retry above can do so, harmlessly) and is logged as *At least one Zabbix destination rejected the values or was unreachable*.
- `panos.csv.sender.status` is the result of the **previous** final transmission (the current one cannot report on itself); it starts at 1 so that the first run does not raise a false alarm.
- Values that cannot be measured (free space with a rejected path, archive totals) are omitted, never sent as 0, to avoid false alarms.
- Template: trapper items with `allowed_hosts = {$PANOS.CSV.ALLOWED.HOSTS}` (an empty value rejects everything, hence the default `0.0.0.0/0,::/0`); thresholds use context macros `{$MACRO:"{#INSTANCE}"}`; the daily file alarms compare `last()` with `avg(...,{$PANOS.CSV.DAY.FILES.BASELINE}:now-1d)`. *No new CSV files for …* uses `max(files.processed, period)=0` (the value is sent once per run, in the final report) and is evaluated only when a value older than the period exists, so a new instance with an empty folder raises no alarm; it depends on the failure triggers, and *Daily CSV files decreased* depends on it. There is no separate "files failed" trigger on purpose: a failed file already makes the run *Failed* or *Partial*.

## 7. Archiver loop and performance

- The CSV list comes from `robocopy /L /TS` (size, UTC time, full path) and is read before any file is moved.
- A `call` costs about 20 ms in batch, so the per-file code (`:ProcessFile`) uses very few calls: the days of each date and the day folder are cached in variables (`PC_D...`, `PC_N...`), counters and space checks are inline. Result: about 0.3 s per file plus 7-Zip, instead of about 1 s.
- Space check: free space is handled in MB (32-bit safe) and read from disk every 50 files, or at every file when within 1 GB of the reserve. Archiving never reduces free space by more than the file size, because the CSV is deleted after the archive is verified.
- 7-Zip: with `-mx9` alone, LZMA2 uses one block per 40-50 MB file, so only one core works. `-m0=LZMA2:c=8m -mmt=on` splits the file in 8 MB blocks compressed in parallel: about 2.7x faster on 4 cores, less memory (about 50 MB per thread), archives about 0.5% larger. The options are tested at every start.

## 8. File lifecycle and recovery

```
source\x.csv -> move -> day folder\x.csv -> 7z a -> x.7z -> 7z t -> delete day folder\x.csv
```

- Files modified less than `MIN_FILE_AGE_MINUTES` ago are skipped (upload in progress). Such a run is still a success: pending files are watched by the "pending" trigger.
- An existing archive or CSV with the same name in the day folder is a failure: nothing is overwritten.
- A failed or invalid new archive is deleted (it was created by this run); the CSV stays in the day folder and is recovered at the next run.
- Recovery (`:RecoverOrphans`) for each CSV inside a day folder: archive missing → archive again; archive valid and containing the same file with the same size → delete the CSV; otherwise the archive is renamed `*.7z.invalid-<epoch>` (never deleted) and the CSV archived again.
- Day folder date: first `YYYY MM DD` sequence of the file name (separators `_` or `-`, real date check with a round trip), else modification date; minus one day for the `*previous_day` modes.
- Month folder name (`MONTH_FOLDER_NAME`): none, English or Italian. Folders of every variant, and of the pre-1.0 layout `MM-YYYY (Month)\DD-MM-YYYY` directly in the source folder, are included in totals, recovery, counts and searches.

## 9. Daily file count

The day counted is today minus `DAY_COUNT_LAG_DAYS` (`auto`: 1, or 2 for the `*previous_day` modes, whose folders are completed one day later); before `DAY_COMPLETE_HOUR` one more day back. The setting assumes that the firewall exports are finished before the archiving tasks start (for example exports at night, tasks in the morning). The value is sent at every run, so the average over the baseline period is the average of the daily counts.

## 10. Console, debug and language

- `CONSOLE_OUTPUT=1` (or `/console`): header, every log line and a final summary on screen; the log file is unchanged.
- `DEBUG_OUTPUT=1` (or `/debug`): also internal values (UTC offset, path guard, options), the day folder of each file, free space readings, the data sent to Zabbix, `zabbix_sender -vv` and the 7-Zip output. External program output is controlled by the `QUIET` variable (`>nul 2>&1` or empty), expanded as `%QUIET%`.
- `LANGUAGE` (`en`/`it`, search also `/lang`): only screen messages are translated (labels `L_*` loaded by `:LangLoad`). Log lines, Zabbix values and file contents stay in English so that they can be compared and filtered.
- All three can be set as environment variables before the call, without editing the script.
- Log line format: `[YYYY-MM-DD hh:mm:ss] LEVEL (code NN) | message`. The level is INFO, SUCCESS, WARNING or FAILURE; the code identifies the event (e.g. 10 file archived, 11 file failed, 98 archive statistics, 99 final transmission), not an error number.
- Early exits (configuration, arguments) always print a message on stderr.

## 11. Search tool

- Archives are read once, as a stream: `7z e -so -bso0 -bsp0 archive | findstr ... > matches`. No temporary extraction; anything written by 7-Zip on stderr marks the archive as unreadable.
- The search values are written to files and passed to `findstr /g:`: any character works (`! & % "`), and several values of a criterion are OR-ed. Each criterion is one `findstr` stage of the pipe (AND).
- IP criteria: a regular expression anchored at the start of the line skips the previous columns (`^[^,]*,...` then `"*VALUE"*,`), so the whole field must match. A literal `findstr /l` stage runs first on the plain value, so the column check only sees few lines.
- User criterion: `findstr` cannot skip 12-13 columns (its regular expressions are limited in complexity: about 14 character classes), so the pipe selects the lines containing the value and the script then checks the user columns of those lines only.
- Column positions come from the CSV header of the first archive in the period; standard PAN-OS positions are used if the names are missing.
- Header lines of the CSV files are removed from the results (`findstr /v /x /l` on the header).
- Per day folder the archives are enumerated directly; the period filter works on the folder names, so a short period reads only a few folders.

## 11b. Configuration exports archiver

- `panos_config_archiver.bat` is generated from `panos_csv_archiver.bat` and kept as an independent script on purpose: a change to one job type cannot affect the other. Shared logic (time, locks, path guard, recovery, Zabbix) is identical.
- Differences: extension `FILE_EXT` / `/ext` instead of `.csv` (validated: letters and digits, at most 10); `-mx0` (store) for the extensions in `STORE_EXTENSIONS`, decided once at start and also used by the 7-Zip options test; archive name `<original name>.7z`; compact dates (a token of 8-14 digits is read as `YYYYMMDD[hhmm[ss]]` and goes through the same real-date check and cache); own registry, lock, log and temporary files (`panos_config_archiver*`, `panos_cfg_*`); Zabbix keys `panos.cfg.*`.
- Separate discovery key (`panos.cfg.discovery`): with a shared key each script would send only its own instances and Zabbix would mark the items of the other as lost.

## 12. Limits

- Paths must not contain `!`, `%` or `^`. With delayed expansion a `!` is dropped silently, so `D:\FW!01` would become `D:\FW01` and a different existing folder could be archived (or searched). The archiver therefore starts with delayed expansion disabled, reads the configuration, checks the arguments, the script folder, `LOG_DIR` and the program paths (`for /f "delims=!^%%"` on the full path), and only then enables it: exit 10 before touching any file. The search tool checks the folder (command line or guided input) and its own folder the same way, before the folder is normalised. Spaces, parentheses and `&` are supported (tested).
- Monthly logs: `LOG_RETENTION_MONTHS` counts the full months kept besides the current one, so that at least that many months of history are always available (with 6, on 1 October the logs from April onwards are kept).
- CSV names with `!` fail individually (file left in place, exit 1). `|`, `<` and `>` cannot appear in Windows file names.
- Dates are valid until 2038-01-19 (32-bit epoch).
- `mountvol` and `fsutil` were tested with an administrator account: check them with the account of the scheduled tasks.
