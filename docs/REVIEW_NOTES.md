# Notes for reviewers

**English** | [Italiano](REVIEW_NOTES.it.md)

For people and automated review tools checking this code. It lists points already verified with real tests, to avoid unnecessary or harmful "fixes".

**Check the real files, not text pasted in a chat.** When code is pasted into a chat, URLs may turn into links and `<` `>` `&` into HTML entities (`&lt;` `&gt;` `&amp;`). The files contain none of them.

## 1. Quick checks on the real files

No HTML entities or links in the scripts (expected: no output, exit code 1):

```bat
findstr /n /i /c:"&gt;" /c:"&lt;" /c:"&amp;" /c:"<a href" panos_csv_archiver.bat panos_csv_search.bat
```

CRLF line endings are required for `.bat` files: with LF only `cmd.exe` can fail to find labels. Do not convert them to LF (see also `.gitattributes`).

Lines that must stay exactly like this:

```bat
set "SCRIPT_URL=https://github.com/N1k0droid"
set "ZABBIX_SERVER=<ZABBIX_SERVER_OR_PROXY>"      & rem placeholder on purpose
set "QUIET=>nul 2>&1"                             & rem redirection in a variable, used as %QUIET%
set "CARET=^"                                     & rem caret kept in a line without "!"
```

## 2. Intentional choices (not bugs)

- **Pure batch**: no PowerShell, WMIC, VBScript or `reg.exe` (often blocked by policies). Date and time come from robocopy, disk figures from `dir` and `fsutil`, independently of the Windows language.
- **`LOG_RETENTION_MONTHS=6` keeps 7 monthly files** (current month + 6 full months): on purpose, so that at least 6 months of history are always available, also on the first day of a month.
- **`SENDER_PREVIOUS=1` at start**: avoids a false "Previous final sender transmission failed" on the first run of an instance.
- **`zabbix_sender` is not a blocking prerequisite**: archiving goes on, the missing sender is logged, `sender_status.txt` goes to 0 and Zabbix reports the missing data with `nodata()`. `ZABBIX_ENABLED=0` disables monitoring completely.
- **SUCCESS with deferred files** (`MIN_FILE_AGE_MINUTES`): a CSV still being uploaded is not an error; files left behind are watched by the pending trigger.
- **`MIN_FILE_AGE_MINUTES=5`** is the production value (0 only in tests).
- **Registry and discovery before the path and prerequisite checks**: Zabbix also receives the failure metrics.
- **Unmeasurable values** (free space with a rejected path, archive totals) are omitted, never sent as 0.
- **zabbix_sender exit code 2** (values rejected) is not retried, except once on the first run of a new instance (asynchronous Zabbix discovery). With several destinations, code 2 also means that one of them was unreachable while the others received the data.
- **Several Zabbix destinations through a temporary `-c` file** (`ServerActive=`): `-z` accepts a single address; a comma sends to independent servers in parallel, a semicolon lists HA cluster nodes (tested with zabbix_sender 7.0).
- **`{$PANOS.CSV.ALLOWED.HOSTS}` defaults to `0.0.0.0/0,::/0`**: an empty value makes Zabbix reject ALL data (verified on Zabbix 7.0, 7.2, 7.4).
- **Template signature**: the `vendor` block (N1k0droid) and the `template`, `class` and `target` tags are intentional.
- **No separate "files failed" trigger**: a failed file already makes the run *Failed* or *Partial* (no duplicate alarms).
- **Archive totals from the robocopy summary, not from `dir /s`**: `for /f` over `dir /s` is linear in the number of archives and too slow with hundreds of thousands of them (measured).
- **Very few `call`s in the archiving loop** (`:ProcessFile`) and cached values: a call costs about 20 ms and files can be thousands per day.
- **Search: user columns checked in batch after `findstr`**: `findstr` regular expressions cannot skip 12-13 columns (complexity limit, measured).
- **Log lines and Zabbix values in English** also when `LANGUAGE=it`: only screen messages are translated.

## 3. Supported characters (tested)

| Case | Result |
|---|---|
| Folder with spaces and parentheses, e.g. `Log PA (prod)` | archived |
| Folder with `&` | archived |
| Folder with `^`, `%` or `!` (source, `/archive`, log, script folder) | exit 10, no file touched, also when a folder with the same name without the character exists |
| CSV name with `&` or `(1)` | archived |
| CSV name with `!` | that file fails and stays in place |

`|`, `<` and `>` are not allowed in Windows file names. Pre-1.0 month folders `MM-YYYY (Month)` (parentheses) are handled.

## 4. Security and privacy

- File names, paths and folder names are never sent to Zabbix.
- CSV names are hidden in the local log by default (`LOG_FILE_NAMES=0`).
- The `/debug` output shows the Zabbix server, the host name, the metrics and the CSV names (no credentials): review it before storing it in shared systems.
- The archiver never deletes archives: rotation is manual. An invalid archive is renamed `*.7z.invalid-<epoch>`, never deleted.
- With `ALLOW_REMOTE_PATHS=0` (default) UNC paths, network drives, SUBST drives and links to the network are refused before any operation.

## 5. How it was verified

- **Scripts**: Windows 11, 7-Zip 24.07 and a fake `zabbix_sender` recording the data. Normal, deferred and colliding files, corrupted archives, interrupted runs, insufficient disk space, missing 7-Zip, refused 7-Zip options, UNC paths, network drives, links, concurrent runs, 1,800 files per day, 46 MB files, both languages, all month folder variants; search: every criterion with exact expected line counts, special characters, wildcards, periods, damaged archives.
- **Template**: imported into Zabbix 7.0.31, 7.2.15 and 7.4.15 (Docker) and fed by the real `zabbix_sender`: discovery, 34 items and 17 triggers per instance, dependencies, context macros, value maps, tags, allowed hosts, time-based triggers with synthetic history.
- **To verify in each environment**: `mountvol` and `fsutil` with the service account, and the timing on real logs.

## 6. Suggested manual check

```bat
panos_csv_archiver.bat "C:\Test\FW01-TRAFFIC" "test-traffic" /console
echo Exit code: %ERRORLEVEL%
```

Expected in the summary: `Result : SUCCESS - exit code 0`, the files found, and `Zabbix : metrics sent` only with Zabbix configured and `zabbix_sender` present. The log path is shown as `Log file` (in `LOG_DIR`, or in `<folder>\Logs` with `LOG_DIR_FALLBACK=1`).
