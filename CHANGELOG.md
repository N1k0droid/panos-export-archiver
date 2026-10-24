# Changelog

All notable changes. Dates in ISO format.

## 1.0.0 – 2026-10-24

First public release.

- `panos_csv_archiver.bat`: archives PAN-OS CSV log exports into `YYYY\MM-YYYY\DD-MM-YYYY` folders with 7-Zip (multi-threaded LZMA2), verifies every archive before deleting the original, recovers interrupted runs, checks free space per file, refuses network paths, one run per instance.
- `panos_config_archiver.bat`: the same logic for configuration exports (Panorama Scheduled Config Export `.tgz`, firewall `.xml`, ...): `/ext` per job, compact dates `YYYYMMDD[hhmm[ss]]`, already compressed formats stored without recompression.
- `panos_csv_search.bat`: guided or command-line search by source/destination IP, user or text over a period, streaming from the archives, results with day and file.
- Zabbix 7.0+ templates for both archivers (trapper items, low-level discovery, per-instance context macros), able to share one host; several Zabbix destinations (independent servers or HA nodes).
- Pure batch: no PowerShell, WMIC or VBScript; locale-independent date, time and disk figures; English and Italian screen messages.

## Pre-release history

- **1.0.0-rc9** – log lines `LEVEL (code NN) | message`; configuration split into sections.
- **1.0.0-rc8** – archive totals from the robocopy summary: with hundreds of thousands of archives the old `dir /s` reading took hours and the final metrics were not sent.
- **1.0.0-rc7** – new `panos_config_archiver.bat` and its Zabbix template.
- **1.0.0-rc6** – trigger *No new files for `{$PANOS.CSV.NO.FILES.MAX.AGE}`*; template signature.
- **1.0.0-rc5** – paths with `!`, `%` or `^` refused before delayed expansion can alter them; log retention documented precisely.
- **1.0.0-rc4** – several Zabbix destinations in `ZABBIX_SERVER`.
- **1.0.0-rc3** – `/archive` folder on the same volume.
- **1.0.0-rc2** – English/Italian screen messages and documentation, MIT license.
- **1.0.0-rc1** – project renamed from its earlier internal names.

## History before the rename

The archiver was developed as `paloalto_csv_archive_monitored.bat` (versions 2.0.0–2.6.1), the search tool as `panos_csv_7z_search.bat` (version 3.0.0).

- **Archiver 2.6.x** – `zabbix_sender` no longer blocking, `ZABBIX_ENABLED=0`; documentation of supported characters.
- **Archiver 2.5.x** – `/console` and `/debug` modes, readable configuration errors, short comments, technical notes.
- **Archiver 2.4.x** – `DAY_FOLDER_DATE=filename_previous_day`, parallel 7-Zip compression tested at start, failure-only reports, per-instance context macros, `LOG_DIR_FALLBACK`, retry of the first send of a new instance.
- **Archiver 2.3.0** – `YYYY\MM-YYYY\DD-MM-YYYY` layout, date from the file name, daily file count alarms, 4x faster loop.
- **Archiver 2.2.0** – free space in percent, compression ratio, oldest pending file, file names hidden in the log.
- **Archiver 2.1.0** – per-file disk space check, recovery of interrupted runs, template fixes.
- **Archiver 2.0.0** – pure batch (no PowerShell), local path guard, monthly log rotation, prerequisite checks with metrics and triggers.
- **Search 3.0.0** – period filter on the day folders, field-aware IP and user search, streaming from the archives, results with day and file.
