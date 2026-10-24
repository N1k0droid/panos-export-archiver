# PAN-OS Export Archiver

![PAN-OS](https://img.shields.io/badge/PAN--OS-Log%20%26%20Config%20Export-blue)
![Zabbix](https://img.shields.io/badge/Zabbix-7.0%2B-red)
![Windows](https://img.shields.io/badge/Windows-batch%2C%20no%20PowerShell-0078D6)
![License: MIT](https://img.shields.io/badge/License-MIT-lightgrey)

**English** | [Italiano](README.it.md)

Archive, monitor and search the log and configuration exports of Palo Alto Networks firewalls and Panorama on Windows, with plain batch scripts.

PAN-OS can export its logs (traffic, threat, URL, WildFire, ...) as CSV files to an FTP/SCP server with the **Scheduled Log Export** feature. Nothing manages those files afterwards: on a busy firewall thousands of large CSV files pile up every day. This project:

- **archives** every CSV into a dated folder tree (`YYYY\MM-YYYY\DD-MM-YYYY`), compressed with 7-Zip and verified before the original is deleted;
- **monitors** the archiving jobs with Zabbix 7 (optional): job status, file counts, disk space, unusual daily volumes;
- **searches** the archive by source/destination IP, user or free text, telling the day and the file of every result;
- **archives configuration exports** too (Panorama Scheduled Config Export `.tgz`, firewall `.xml`, ...) with a separate script and template.

| Tool | Purpose |
|---|---|
| `panos_csv_archiver.bat` | Archives the CSV log exports, sends the metrics to Zabbix |
| `panos_config_archiver.bat` | Archives configuration exports (`.tgz`, `.xml`, ...) with the same logic |
| `panos_csv_search.bat` | Searches the archived CSV logs by IP, user or text |
| `zabbix/*.yaml` | Two Zabbix 7 templates (CSV logs, configurations) that can share one host |

Everything runs with `cmd.exe`, standard Windows programs, 7-Zip and (optionally) `zabbix_sender`: no PowerShell and no runtime to install.

> Independent project, not affiliated with or endorsed by Palo Alto Networks. PAN-OS and Palo Alto Networks are trademarks of Palo Alto Networks, Inc.

---

## Contents

- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Archive layout and recovery](#archive-layout-and-recovery)
- [Zabbix monitoring](#zabbix-monitoring)
- [Search tool](#search-tool)
- [Configuration exports](#configuration-exports)
- [Console and debug output](#console-and-debug-output)
- [Exit codes](#exit-codes)
- [Performance](#performance)
- [Limitations](#limitations)
- [Repository layout](#repository-layout)
- [Development notes](#development-notes)
- [License](#license)

## Features

**Archiving** (`panos_csv_archiver.bat`)
- One scheduled task per source folder (one per firewall and log type), same script for all.
- Archive tree in the source folder, or in another folder of the same volume (`/archive`).
- Day folder taken from the date in the PAN-OS file name, or from the modification date; optionally shifted to the day of the log records.
- 7-Zip maximum compression with multi-threaded LZMA2 blocks (about 2.7x faster than plain `-mx9` on 40-50 MB files, archives about 0.5% larger).
- Every archive is tested before the CSV is deleted; existing files are never overwritten.
- Files still being uploaded (recently modified) are left for the next run.
- Automatic recovery of runs interrupted after the move: incomplete archives are set aside, never deleted.
- Per-file free space check with a configurable reserve: a nearly full disk does not stop the archiving.
- Guardrail: source and log folders must be on local disks (UNC paths, network drives, SUBST and links to the network are refused before any file is touched).
- One run per instance (file handle lock, released by Windows even if the run is killed).
- Monthly local logs with automatic retention (minimum 6 months); file names can be hidden.
- Silent for scheduled tasks; `/console` and `/debug` modes for manual runs.
- Screen messages in English or Italian.

**Monitoring** (Zabbix 7.0 or later, optional)
- Low-level discovery: every scheduled task appears in Zabbix by itself.
- 34 items and 18 triggers per instance: failed or partial runs, jobs stuck or not running, missing prerequisites, rejected paths, low disk space (in percent), pending files, interrupted runs, unusual daily file counts, archives older than the retention period.
- Thresholds per instance with context macros.
- A missing `zabbix_sender` never blocks the archiving.

**Search** (`panos_csv_search.bat`)
- Guided mode (double click, or drag a log folder onto the script) or command line.
- Field-aware: an IP is matched against the whole *Source address* / *Destination address* field (`192.0.2.1` does not match `192.0.2.10` or NAT columns); users are matched in the user columns.
- Combine criteria (source AND destination, IP AND user), several values per criterion, `*` wildcard, any character in free text.
- Reads every archive once, straight from the `.7z`, without extracting it to disk.
- Results as CSV with the day and the archive name of every line, plus a summary.

## How it works

```
 PAN-OS Scheduled Log Export
          |  FTP / SCP
          v
 D:\FTP\FW01-TRAFFIC\FW01_traffic_2026_04_02_last_calendar_day_0.csv
          |
          |  panos_csv_archiver.bat  (Task Scheduler, one task per folder)
          v
 D:\FTP\FW01-TRAFFIC\2026\04-2026\02-04-2026\FW01_traffic_..._0.7z
          |                                   |
          | zabbix_sender (optional)          | panos_csv_search.bat
          v                                   v
 Zabbix: PAN-OS CSV Archiver template   results\search_....csv
```

For each CSV file the archiver: finds the day folder, moves the file there, compresses it to `.7z`, tests the archive, deletes the CSV, and finally sends the metrics of the run to Zabbix.

## Requirements

- Windows 10 / Windows Server 2016 or later (developed and tested on Windows 11).
- [7-Zip](https://www.7-zip.org/) (`7z.exe`).
- Optional, for monitoring: Zabbix server or proxy 7.0 LTS or later, and `zabbix_sender.exe` (included in the Zabbix agent / agent 2 packages for Windows).
- An account for the scheduled tasks with: read/write access to the source folders, write access to the script folder and to the log folder.
- Standard programs of `%SystemRoot%\System32` (always present): robocopy, findstr, sort, mountvol, net, subst, ping, fsutil.

## Quick start

```bat
rem 1. Copy the scripts to a local folder
rem 2. Edit the "Configuration" section of panos_csv_archiver.bat
rem    (ZABBIX_ENABLED=0 to start without Zabbix, and LOG_DIR)
rem 3. Test on a copy of a source folder:
panos_csv_archiver.bat "D:\Test\FW01-TRAFFIC" "fw01-traffic" /console
rem 4. Search:
panos_csv_search.bat "D:\Test\FW01-TRAFFIC" /from 02-04-2026 /src 192.0.2.10
```

## Installation

1. **7-Zip** – install it (default path `C:\Program Files\7-Zip\7z.exe`).
2. **Scripts** – copy `panos_csv_archiver.bat`, `panos_csv_search.bat` and (for configuration exports) `panos_config_archiver.bat` to a local folder, for example `C:\Scripts\PaloAlto\panos-export-archiver\`. The folder must be writable by the task account (instance registry and lock files are created there).
3. **Configuration** – edit the top of `panos_csv_archiver.bat` (see [Configuration](#configuration)). While a `<placeholder>` is left, the script stops with exit code 15 and says which value is missing.
4. **Zabbix** (optional)
   1. Install `zabbix_sender.exe` (Zabbix agent package) and set `ZABBIX_SENDER_PATH`.
   2. *Data collection > Templates > Import*: `zabbix/zbx7_template_panos_csv_archiver.yaml`.
   3. Link the template *PAN-OS CSV Archiver by Zabbix trapper* to the host named in `ZABBIX_HOST` (if the host is monitored by a proxy, `ZABBIX_SERVER` must be that proxy).
   4. Set the host macro `{$PANOS.CSV.ALLOWED.HOSTS}` to the address of the Windows server. Never leave it empty: an empty value makes Zabbix reject all data.
   5. With several independent destinations in `ZABBIX_SERVER`, repeat steps 2-4 on each of them, with the same host name.
5. **First run** – on a copy of a source folder, with the task account:
   ```bat
   panos_csv_archiver.bat "D:\Test\FW01-TRAFFIC" "fw01-traffic" /console
   ```
   Expected: `Result : SUCCESS - exit code 0`, archives in `YYYY\MM-YYYY\DD-MM-YYYY`, and (with Zabbix) the instance discovered after the first run.
   To keep the archives out of the FTP folder add `/archive "D:\Archive\FW01-TRAFFIC"` (see [Archive folder](#archive-folder)).
6. **Scheduled tasks** – one task per source folder:
   - Program: `C:\Scripts\PaloAlto\panos-export-archiver\panos_csv_archiver.bat`
   - Arguments: `"D:\FTP\FW01-TRAFFIC" "fw01-traffic"` (optionally `/archive "D:\Archive\FW01-TRAFFIC"`)
   - Run whether the user is logged on or not, with the service account.
   - Settings: *If the task is already running: Do not start a new instance*.
   - Schedule after the firewall exports are complete. A large job uses all CPU cores while compressing: stagger the tasks.

`INSTANCE_ID` (second argument): lowercase letters, digits, `_` and `-`, at most 64 characters, unique per source folder.

## Configuration

At the top of `panos_csv_archiver.bat`. `LANGUAGE`, `CONSOLE_OUTPUT` and `DEBUG_OUTPUT` can also be set as environment variables.

| Setting | Default | Description |
|---|---|---|
| `LANGUAGE` | `en` | Screen messages: `en` or `it`. Log and Zabbix data are always in English. |
| `CONSOLE_OUTPUT` | `0` | `1` = progress and summary on screen (same as `/console`). |
| `DEBUG_OUTPUT` | `0` | `1` = also internal values, data sent to Zabbix, 7-Zip and zabbix_sender output (same as `/debug`). |
| `SEVENZIP_PATH` | `C:\Program Files\7-Zip\7z.exe` | 7-Zip executable. |
| `SEVENZIP_OPTIONS` | `-mx9 -m0=LZMA2:c=8m -mmt=on` | Compression options, tested at every start (refused options: exit 14). `-mx9` = single-thread compression. |
| `ZABBIX_ENABLED` | `1` | `0` = archiving only: no metrics, no discovery, Zabbix settings ignored. |
| `ZABBIX_SENDER_PATH` | `C:\Program Files\Zabbix Agent 2\zabbix_sender.exe` | If missing, files are still archived and the log reports it. |
| `ZABBIX_SERVER` / `ZABBIX_PORT` | placeholder / `10051` | Zabbix server, or the proxy monitoring the host. Several destinations: `"zbx-a,zbx-b"` sends the same data in parallel to independent Zabbix installations, `"node1;node2"` lists the nodes of one HA cluster. An entry can have its own port (`host:port`); the others use `ZABBIX_PORT`. |
| `ZABBIX_HOST` | placeholder | Technical host name in Zabbix. |
| `LOG_DIR` | placeholder | Local folder for logs and state. |
| `LOG_DIR_FALLBACK` | `0` | `1` = an empty or unconfigured `LOG_DIR` becomes `<source folder>\Logs`. |
| `ALLOW_REMOTE_PATHS` | `0` | `1` = allow network paths for source and log folders. |
| `DISK_RESERVE_BYTES` | `2147483648` (2 GB) | A file is archived only if free space >= file size + reserve. |
| `DAY_FOLDER_DATE` | `filename` | `filename` = date in the file name (day of the export); `filename_previous_day` = the day before (day of the log records); `modified` / `previous_day` = modification date / the day before. |
| `MONTH_FOLDER_NAME` | `none` | Month folder `09-2026`; `en` = `09-2026 (September)`; `it` = `09-2026 (Settembre)`. |
| `DAY_COUNT_LAG_DAYS` | `auto` | Day measured by the daily file count: yesterday, or the day before yesterday with the `*previous_day` modes. |
| `DAY_COMPLETE_HOUR` | `7` | Before this hour one more day back (the day must be complete). |
| `LOG_FILE_NAMES` | `0` | `1` = CSV names in the local log (never sent to Zabbix). |
| `MIN_FILE_AGE_MINUTES` | `5` | Newer files are left for the next run. Keep it above 0 in production. |
| `LOG_RETENTION_MONTHS` | `6` | Full months of logs kept besides the current month (minimum 6): with 6, on 1 October the logs from April onwards are kept. |
| `INSTANCE_RETENTION_DAYS` | `45` | Instances without runs leave the registry and the discovery. |
| `NEW_INSTANCE_DELAY` | `30` | Seconds to wait for the discovery of a new instance (one retry if Zabbix is not ready). |
| `*_RETRY_COUNT` / `*_RETRY_DELAY` | `3` / `5` | zabbix_sender attempts and pause. |

## Archive folder

```bat
panos_csv_archiver.bat "SOURCE_FOLDER" "INSTANCE_ID" [/archive "ARCHIVE_FOLDER"] [/console or /debug]
```

- Without `/archive` the archive tree is created inside the source folder.
- With `/archive` it is created in `ARCHIVE_FOLDER`, which must be **on the same volume** as the source folder: moving a CSV is then a rename (instant and atomic), never a copy. The folder is created if missing.
- A folder on another volume, a network path, or a path containing a symbolic link or junction is refused (exit 13, trigger *Path rejected*) before any file is touched.
- Use a different archive folder for each instance: the script cannot detect two tasks sharing one.
- Archives already created in the source folder are not moved: move the year folders to the new location (same volume, instant) before switching.
- The search tool works on the archive folder; to search the CSV files not archived yet (`/unarchived`), run it on the source folder.

## Archive layout and recovery

```
D:\FTP\FW01-TRAFFIC\                      source folder (or the /archive folder)
  2026\
    04-2026\
      02-04-2026\
        FW01_traffic_2026_04_02_last_calendar_day_0.7z
        FW01_traffic_2026_04_02_last_calendar_day_1.7z
        report\FAILED-JOB.txt             only if a file of that day failed
```

- A file with the same name already in the day folder is a failure: nothing is overwritten.
- A CSV left in a day folder by an interrupted run is completed at the next run: archived if no archive exists, deleted if a valid archive already contains the same file with the same size; an incomplete or different archive is renamed `*.7z.invalid-<epoch>` and reported.
- Archives are never deleted by the script: rotation is up to you. Zabbix reports the total size, the number of archives and the oldest archived day.

## Zabbix monitoring

Template **PAN-OS CSV Archiver by Zabbix trapper** (`zabbix/zbx7_template_panos_csv_archiver.yaml`, export format 7.0, tested on Zabbix 7.0, 7.2 and 7.4). All items are trapper items keyed `panos.csv.*[<INSTANCE_ID>]`, created by the discovery rule `panos.csv.discovery`. Problems are tagged `instance=<INSTANCE_ID>` and `component=job|storage|health`.

| Trigger | Severity |
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

| Macro | Default | Meaning |
|---|---|---|
| `{$PANOS.CSV.ALLOWED.HOSTS}` | `0.0.0.0/0,::/0` | Addresses allowed to send data. Set it to the Windows server; never empty. |
| `{$PANOS.CSV.JOB.MAX.DURATION}` | `8h` | Maximum duration of a run. |
| `{$PANOS.CSV.JOB.MAX.AGE}` | `26h` | Maximum time without data / without a completed run. |
| `{$PANOS.CSV.JOB.SUCCESS.MAX.AGE}` | `26h` | Maximum age of the last successful run. |
| `{$PANOS.CSV.NO.FILES.MAX.AGE}` | `3d` | Maximum time without any archived CSV while the job keeps running: the export of the firewall does not arrive (maximum `30d`). |
| `{$PANOS.CSV.PENDING.MAX}` | `0` | Files allowed to remain in the source folder on two consecutive runs. |
| `{$PANOS.CSV.DISK.MIN.PFREE}` | `10` | Free space warning, in percent of the volume. |
| `{$PANOS.CSV.DAY.FILES.BASELINE}` | `7d` | Baseline period for the daily file count. |
| `{$PANOS.CSV.DAY.FILES.CHANGE.PCT}` | `50` | Change of the daily file count that raises an alarm. |
| `{$PANOS.CSV.ARCHIVE.ROTATION.AGE}` | `365d` | Age of the oldest archived day after which a rotation is due. |

Every threshold accepts a context per instance, for example `{$PANOS.CSV.JOB.MAX.DURATION:"fw01-traffic"} = 10h`.

## Search tool

```bat
rem Guided: double click panos_csv_search.bat, or drag a log folder onto it
rem Command line:
panos_csv_search.bat "D:\FTP\FW01-TRAFFIC" /from 01-04-2026 /to 05-04-2026 /src 192.0.2.10
panos_csv_search.bat "D:\FTP\FW01-TRAFFIC" /from 02-04-2026 /src 192.0.2.10 /dst 198.51.100.7
panos_csv_search.bat "D:\FTP\FW01-TRAFFIC" /from * /user "jdoe asmith" /lang it
```

| Criterion | Option | Matched against |
|---|---|---|
| Source IP | `/src` | the whole *Source address* field |
| Destination IP | `/dst` | the whole *Destination address* field |
| Source or destination IP | `/ip` | either of the two fields |
| User | `/user` | *Source User* or *Destination User*, partial, case-insensitive |
| Free text | `/text` | anywhere in the line, case-insensitive |

- Several values in one criterion (separated by spaces) = any of them; several criteria = all of them.
- `*` is a wildcard: `192.0.2.*`.
- Period: dates of the day folders (`DD-MM-YYYY`), default yesterday; `/from *` = whole archive. `/unarchived` also searches the CSV files not archived yet.
- Results in `results\` next to the script: `<name>.csv` with the columns `Day,File,<original columns>` and `<name>_summary.txt` (files with results, unreadable files).
- Options: `/out NAME`, `/lang en|it`, `/debug`, `/?`.
- Search exit codes: `0` lines found, `1` none, `2` some files unreadable (result may be incomplete), `10` invalid input, `14` 7-Zip or system clock unavailable.

Column positions are read from the CSV header (*Source address*, *Destination address*, *Source User*, *Destination User*); if they are missing, the standard PAN-OS positions (8, 9, 13, 14) are used and the tool says so before starting.

## Configuration exports

`panos_config_archiver.bat` archives configuration exports with the same logic as the CSV archiver (dated folders, verification before deleting the original, recovery, path guard, Zabbix metrics), as an independent job with its own template.

- **Sources**: Panorama can export its configuration (and the configurations of the managed firewalls) on a schedule with **Scheduled Config Export** (`.tgz` files on an FTP/SCP server). Firewalls have no scheduled export: any configuration file copied into a folder by other means (named snapshots `.xml`, device state `.tgz`, API scripts) can be archived the same way.
- **Extension per job**: `FILE_EXT=tgz` at the top of the script is the default; `/ext EXT` sets it per job (`/ext xml`, `/ext zip`). Letters and digits only.
- **Date in the file name**: `YYYY_MM_DD`, `YYYY-MM-DD` and the compact forms `YYYYMMDD`, `YYYYMMDDhhmm`, `YYYYMMDDhhmmss` (e.g. `Panorama_20261019.tgz` goes to `2026\10-2026\19-10-2026`). Without a date the modification date is used, with a warning in the log.
- **No recompression**: the extensions in `STORE_EXTENSIONS` (`tgz gz zip 7z bz2 xz rar`) are stored in the `.7z` without compression; other formats (e.g. `.xml`) are compressed with `SEVENZIP_OPTIONS`.
- **Archive name**: the original name plus `.7z` (`Panorama_20261019.tgz.7z`), so jobs with different extensions can share a day folder.
- **Configuration**: the same variables as the CSV archiver, at the top of the script; logs `panos_config_archiver_<id>_YYYY-MM.log`, registry `panos_config_archiver.registry`.
- **Zabbix**: template `zabbix/zbx7_template_panos_config_archiver.yaml` (*PAN-OS Config Archiver by Zabbix trapper*), keys `panos.cfg.*`, macros `{$PANOS.CFG.*}`. It can be linked to the same host as the CSV template. Main alarm: *No new files for `{$PANOS.CFG.NO.FILES.MAX.AGE}`* (default `2d`); no daily increase/decrease alarms (usually one export a day); `{$PANOS.CFG.JOB.MAX.DURATION}` = `1h`.

```bat
panos_config_archiver.bat "D:\FTP\PANORAMA-CONFIG" "panorama-config" /console
panos_config_archiver.bat "D:\Backup\FW01-CONFIG" "fw01-config" /ext xml
```

Task Scheduler: one task per job, as for the CSV archiver, scheduled after the export (e.g. Scheduled Config Export at 02:00, task at 03:00).

## Console and debug output

Scheduled tasks run silently. For manual runs:

```bat
panos_csv_archiver.bat "D:\FTP\FW01-TRAFFIC" "fw01-traffic" /console
panos_csv_archiver.bat "D:\FTP\FW01-TRAFFIC" "fw01-traffic" /debug
```

`/console` prints a header, every log line and a final summary; `/debug` also prints internal values, the data sent to Zabbix and the output of 7-Zip and zabbix_sender. The debug output contains the Zabbix server, the host name and the CSV file names (no credentials): review it before storing it in shared systems.

Local log: `<LOG_DIR>\panos_csv_archiver_<INSTANCE_ID>_YYYY-MM.log`, lines `[YYYY-MM-DD HH:MM:SS] LEVEL (code NN) | message`, e.g. `[2026-10-20 08:31:41] INFO (code 98) | Archive statistics computed in 3 s`.

## Exit codes

| Code | Archivers |
|---|---|
| 0 | Success (also with no files to archive) |
| 1 | All files failed |
| 2 | Partial: some files failed |
| 10 | Fatal error (source missing or not writable, path with unsupported characters, ...) or missing source argument |
| 11 | Missing instance argument |
| 12 | Invalid `INSTANCE_ID` |
| 13 | Path rejected: not on a local disk, or archive folder not on the volume of the source folder |
| 14 | Prerequisites missing (7-Zip, system programs, refused 7-Zip options, system clock) |
| 15 | Configuration incomplete or invalid |
| 20 | Another run of the same instance is active |

## Performance

Measured on a 4-core test machine with synthetic logs:

- Archiver: about 0.3 s of overhead per file plus the 7-Zip time; a 46 MB CSV took about 8 s with the default options (about 21 s with `-mx9` alone). 1,800 small files: about 8 minutes.
- Search: about 0.5 s per 46 MB archive (7-Zip decompression is about half of it).

Real logs are more repetitive than synthetic ones and usually compress and decompress faster.

## Limitations

- Source, archive, log and script folders (and the 7-Zip and zabbix_sender paths) must not contain `!`, `%` or `^`: the archiver stops (exit 10) without touching any file, and the search tool refuses the folder (exit 10, or a new prompt in guided mode). Spaces, parentheses and `&` are supported.
- The archive folder (`/archive`) must be on the volume of the source folder and its path must not contain links.
- CSV file names with `!` are not archived (reported as failed, left in place). PAN-OS export names never contain it.
- Dates are handled until 2038-01-19 (32-bit arithmetic of `cmd.exe`).
- The search tool reads the user columns with a second check in batch: very common user values are slower to search than IPs.
- `mountvol` and `fsutil` should be verified with the account of the scheduled tasks.

More details: [docs/TECHNICAL_NOTES.md](docs/TECHNICAL_NOTES.md). Notes for code reviewers and automated reviews: [docs/REVIEW_NOTES.md](docs/REVIEW_NOTES.md).

## Repository layout

```
panos_csv_archiver.bat                    archiving and monitoring
panos_csv_search.bat                      search tool
panos_config_archiver.bat                 archiving of configuration exports (.tgz, .xml, ...)
zabbix/zbx7_template_panos_csv_archiver.yaml
zabbix/zbx7_template_panos_config_archiver.yaml
docs/TECHNICAL_NOTES.md  (.it.md)         internals
docs/REVIEW_NOTES.md     (.it.md)         notes for reviewers
README.md / README.it.md
CHANGELOG.md
LICENSE
```

## Development notes

AI coding tools were used during development and review. Every feature was tested on Windows with real 7-Zip runs and on Zabbix 7.0, 7.2 and 7.4.

## License

[MIT](LICENSE) © Nicola Carmelo Gurgone (N1k0droid) – https://github.com/N1k0droid
