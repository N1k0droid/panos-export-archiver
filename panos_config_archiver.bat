@echo off
rem Delayed expansion is enabled after the path check below
setlocal EnableExtensions DisableDelayedExpansion

rem ===========================================================================
rem  PAN-OS Config Archiver - archives Panorama / firewall configuration exports with 7-Zip (optional Zabbix monitoring)
rem  Version : 1.0.0
rem  Author  : N1k0droid - https://github.com/N1k0droid
rem  Usage   : panos_config_archiver.bat "SOURCE_DIR" "INSTANCE_ID" [/ext EXT] [/archive "DIR"] [/console or /debug]
rem  Docs    : README.md / README.it.md, docs\TECHNICAL_NOTES.md
rem ===========================================================================
set "SCRIPT_VERSION=1.0.0"
set "SCRIPT_AUTHOR=N1k0droid"
set "SCRIPT_URL=https://github.com/N1k0droid"
set "SCRIPT_NAME=%~nx0"

rem === Configuration (README.md, section Configuration) ===

rem ###########################################################################
rem  SCREEN OUTPUT
rem ###########################################################################

rem Language of the screen messages: en or it (log and Zabbix data are English)
if not defined LANGUAGE set "LANGUAGE=en"

rem 1 = progress on screen; DEBUG_OUTPUT=1 also shows 7-Zip/zabbix_sender output
if not defined CONSOLE_OUTPUT set "CONSOLE_OUTPUT=0"
if not defined DEBUG_OUTPUT set "DEBUG_OUTPUT=0"

rem ###########################################################################
rem  7-ZIP
rem ###########################################################################

set "SEVENZIP_PATH=C:\Program Files\7-Zip\7z.exe"

rem "-mx9" = original single-thread compression
set "SEVENZIP_OPTIONS=-mx9 -m0=LZMA2:c=8m -mmt=on"

rem Extension of the files to archive (default for every job; /ext overrides it)
set "FILE_EXT=tgz"

rem Already compressed formats: stored in the .7z without compression (-mx0)
set "STORE_EXTENSIONS=tgz gz zip 7z bz2 xz rar"

rem ###########################################################################
rem  ZABBIX
rem ###########################################################################

rem 0 = archiving only, no Zabbix (sender and Zabbix settings not needed)
set "ZABBIX_ENABLED=1"

set "ZABBIX_SENDER_PATH=C:\Program Files\Zabbix Agent 2\zabbix_sender.exe"

rem Zabbix server or proxy. Several destinations:
rem "srvA,srvB" = independent servers (each receives all data, in parallel)
rem "node1;node2" = nodes of one HA cluster; host or host:port entries
set "ZABBIX_SERVER=<ZABBIX_SERVER_OR_PROXY>"
set "ZABBIX_PORT=10051"

rem Technical host name of the host in Zabbix
set "ZABBIX_HOST=<ZABBIX_TECHNICAL_HOSTNAME>"

rem ###########################################################################
rem  LOG FOLDER AND PATHS
rem ###########################################################################

rem Local folder for logs and state
set "LOG_DIR=<LOCAL_LOG_DIRECTORY>"

rem 1 = empty/unconfigured LOG_DIR becomes SOURCE_DIR\Logs
set "LOG_DIR_FALLBACK=0"

rem 0 = local disks only, 1 = network paths allowed
set "ALLOW_REMOTE_PATHS=0"

rem Free space that must remain after archiving a file
set "DISK_RESERVE_BYTES=2147483648"

rem ###########################################################################
rem  ARCHIVE LAYOUT
rem ###########################################################################

rem Month folder name: none = "09-2026", en = "09-2026 (September)", it = "09-2026 (Settembre)"
set "MONTH_FOLDER_NAME=none"

rem filename, filename_previous_day, modified or previous_day
set "DAY_FOLDER_DATE=filename"

rem Files modified more recently are left for the next run
set "MIN_FILE_AGE_MINUTES=5"

rem ###########################################################################
rem  DAILY FILE COUNT
rem ###########################################################################

rem Day measured by the daily file count (auto = 1, or 2 for *previous_day)
set "DAY_COUNT_LAG_DAYS=auto"

rem Hour from which the previous day counts as complete
set "DAY_COMPLETE_HOUR=7"

rem ###########################################################################
rem  LOG FILE AND RETENTION
rem ###########################################################################

rem 1 = file names in the local log (never sent to Zabbix)
set "LOG_FILE_NAMES=0"

rem Full months of logs kept besides the current month (minimum 6)
set "LOG_RETENTION_MONTHS=6"

rem Instances without runs leave the registry after these days
set "INSTANCE_RETENTION_DAYS=45"

rem ###########################################################################
rem  ZABBIX RETRIES (seconds)
rem ###########################################################################

set "DISCOVERY_RETRY_COUNT=3"
set "DISCOVERY_RETRY_DELAY=5"
set "METRICS_RETRY_COUNT=3"
set "METRICS_RETRY_DELAY=5"

rem Seconds to wait for the discovery of a new instance
set "NEW_INSTANCE_DELAY=30"

rem ###########################################################################
rem  END OF CONFIGURATION - nothing to edit below this line
rem ###########################################################################

rem === Windows programs (absolute paths, independent of PATH) ===
set "SYS32=%SystemRoot%\System32"
set "ROBOCOPY=%SYS32%\robocopy.exe"
set "FINDSTR=%SYS32%\findstr.exe"
set "SORT=%SYS32%\sort.exe"
set "MOUNTVOL=%SYS32%\mountvol.exe"
set "NET=%SYS32%\net.exe"
set "SUBST=%SYS32%\subst.exe"
set "PING=%SYS32%\PING.EXE"
set "FSUTIL=%SYS32%\fsutil.exe"
set "ID_CHARS=abcdefghijklmnopqrstuvwxyz0123456789"

rem ! % ^ in a path would be altered by delayed expansion (a "!" is dropped and
rem another folder could be archived): arguments, script folder, LOG_DIR and
rem program paths are checked while it is still disabled (exit 10)
set "BAD_CHARS=! %% ^"
set "UNSAFE_PATH="
for %%P in ("%~dp0" "%LOG_DIR%" "%SEVENZIP_PATH%" "%ZABBIX_SENDER_PATH%" %*) do (
    for /f "delims=!^%%" %%Q in ("x%%~fP") do if not "%%Q"=="x%%~fP" set "UNSAFE_PATH=1"
)
setlocal EnableDelayedExpansion

call :LangLoad
if defined UNSAFE_PATH (
    >&2 echo(
    >&2 echo [PAN-OS Config Archiver] !L_ERRCFG! !L_E_CHARS! !BAD_CHARS!
    >&2 echo(
    exit /b 10
)

rem === Arguments and options ===
if "%~1"=="" ( call :Usage & exit /b 10 )
if "%~2"=="" ( call :Usage & exit /b 11 )
set "SOURCE_DIR=%~f1"
set "INSTANCE_ID=%~2"
set "ARCHIVE_ARG="
set "ARCHIVE_GIVEN=0"
set "EXT_ARG="
set "EXT_GIVEN=0"
rem Options after the two arguments, in any order
:OptLoop
if "%~3"=="" goto :OptDone
if /i "%~3"=="/console" goto :OptConsole
if /i "%~3"=="/debug" goto :OptDebug
if /i "%~3"=="/archive" goto :OptArchive
if /i "%~3"=="/ext" goto :OptExt
call :Usage
exit /b 15
:OptConsole
set "CONSOLE_OUTPUT=1"
shift /3
goto :OptLoop
:OptDebug
set "CONSOLE_OUTPUT=1"
set "DEBUG_OUTPUT=1"
shift /3
goto :OptLoop
:OptArchive
set "ARCHIVE_GIVEN=1"
set "ARCHIVE_ARG=%~4"
shift /3
shift /3
goto :OptLoop
:OptExt
set "EXT_GIVEN=1"
set "EXT_ARG=%~4"
shift /3
shift /3
goto :OptLoop
:OptDone
if "!ARCHIVE_GIVEN!"=="1" if not defined ARCHIVE_ARG ( call :Usage & exit /b 15 )
if "!EXT_GIVEN!"=="1" if not defined EXT_ARG ( call :Usage & exit /b 15 )
if defined EXT_ARG set "FILE_EXT=!EXT_ARG!"
if defined FILE_EXT if "!FILE_EXT:~0,1!"=="." set "FILE_EXT=!FILE_EXT:~1!"
if not "%CONSOLE_OUTPUT%"=="0" if not "%CONSOLE_OUTPUT%"=="1" ( call :ConfigError "CONSOLE_OUTPUT !L_E_01!" & exit /b 15 )
if not "%DEBUG_OUTPUT%"=="0" if not "%DEBUG_OUTPUT%"=="1" ( call :ConfigError "DEBUG_OUTPUT !L_E_01!" & exit /b 15 )
if "%DEBUG_OUTPUT%"=="1" set "CONSOLE_OUTPUT=1"
set "QUIET=>nul 2>&1"
set "LOCK_QUIET=2>nul"
set "SENDER_VERBOSE="
if "%DEBUG_OUTPUT%"=="1" (
    set "QUIET="
    set "LOCK_QUIET="
    set "SENDER_VERBOSE=-vv"
)
if "!SOURCE_DIR:~-1!"=="\" set "SOURCE_DIR=!SOURCE_DIR:~0,-1!"
rem Archive folder: the source folder, or /archive on the same volume
set "ARCHIVE_DIR=!SOURCE_DIR!"
set "ARCHIVE_SEPARATE=0"
if defined ARCHIVE_ARG (
    for %%I in ("!ARCHIVE_ARG!") do set "ARCHIVE_DIR=%%~fI"
    if "!ARCHIVE_DIR:~-1!"=="\" set "ARCHIVE_DIR=!ARCHIVE_DIR:~0,-1!"
    if /i not "!ARCHIVE_DIR!"=="!SOURCE_DIR!" set "ARCHIVE_SEPARATE=1"
)
set "SCRIPT_DIR=%~dp0"
set "INSTANCE_REGISTRY=%SCRIPT_DIR%panos_config_archiver.registry"
set "INSTANCE_LOCK=%SCRIPT_DIR%panos_config_archiver_%INSTANCE_ID%.lock"

rem === Configuration checks (exit 15) ===
if not "%LOG_DIR_FALLBACK%"=="0" if not "%LOG_DIR_FALLBACK%"=="1" ( call :ConfigError "LOG_DIR_FALLBACK !L_E_01!" & exit /b 15 )
if "%LOG_DIR_FALLBACK%"=="1" (
    if not defined LOG_DIR set "LOG_DIR=%SOURCE_DIR%\Logs"
    if not "!LOG_DIR:<=!"=="!LOG_DIR!" set "LOG_DIR=%SOURCE_DIR%\Logs"
)
if not defined LOG_DIR ( call :ConfigError "!L_E_LOGDIR!" & exit /b 15 )
if "!LOG_DIR:~-1!"=="\" set "LOG_DIR=!LOG_DIR:~0,-1!"
if not "%ZABBIX_ENABLED%"=="0" if not "%ZABBIX_ENABLED%"=="1" ( call :ConfigError "ZABBIX_ENABLED !L_E_01!" & exit /b 15 )
set "CFG_REQUIRED=LOG_DIR"
if "%ZABBIX_ENABLED%"=="1" set "CFG_REQUIRED=ZABBIX_SERVER ZABBIX_HOST LOG_DIR"
for %%V in (%CFG_REQUIRED%) do if not "!%%V:<=!"=="!%%V!" ( call :ConfigError "%%V !L_E_PH!" & exit /b 15 )
set "DATE_FROM_NAME="
set "DATE_SHIFT="
if /i "%DAY_FOLDER_DATE%"=="filename" set "DATE_FROM_NAME=1" & set "DATE_SHIFT=0"
if /i "%DAY_FOLDER_DATE%"=="filename_previous_day" set "DATE_FROM_NAME=1" & set "DATE_SHIFT=1"
if /i "%DAY_FOLDER_DATE%"=="modified" set "DATE_FROM_NAME=0" & set "DATE_SHIFT=0"
if /i "%DAY_FOLDER_DATE%"=="previous_day" set "DATE_FROM_NAME=0" & set "DATE_SHIFT=1"
if not defined DATE_SHIFT ( call :ConfigError "!L_E_INVALID! DAY_FOLDER_DATE" & exit /b 15 )
if /i "%DAY_COUNT_LAG_DAYS%"=="auto" set /a DAY_COUNT_LAG_DAYS=1+DATE_SHIFT
call :IsNumber "%DAY_COUNT_LAG_DAYS%" CFG_OK
if not "!CFG_OK!"=="1" ( call :ConfigError "!L_E_INVALID! DAY_COUNT_LAG_DAYS" & exit /b 15 )
call :IsNumber "%DAY_COMPLETE_HOUR%" CFG_OK
if not "!CFG_OK!"=="1" ( call :ConfigError "!L_E_INVALID! DAY_COMPLETE_HOUR" & exit /b 15 )
if "%MONTH_FOLDER_NAME%"=="0" set "MONTH_FOLDER_NAME=none"
if "%MONTH_FOLDER_NAME%"=="1" set "MONTH_FOLDER_NAME=it"
set "MF_OK="
for %%m in (none en it) do if /i "%MONTH_FOLDER_NAME%"=="%%m" set "MONTH_FOLDER_NAME=%%m" & set "MF_OK=1"
if not defined MF_OK ( call :ConfigError "!L_E_MONTH!" & exit /b 15 )
if not "%LOG_FILE_NAMES%"=="0" if not "%LOG_FILE_NAMES%"=="1" ( call :ConfigError "LOG_FILE_NAMES !L_E_01!" & exit /b 15 )

rem Instance id: lowercase letters, digits, _ and - (findstr lists, not ranges)
if not "!INSTANCE_ID:~64!"=="" ( call :ConfigError "!L_E_IDLEN!" & exit /b 12 )
set "ID_CHECK_FILE=%TEMP%\panos_cfg_id_%RANDOM%%RANDOM%.tmp"
>"%ID_CHECK_FILE%" echo(!INSTANCE_ID!
%FINDSTR% /r /x /c:"[%ID_CHARS%][%ID_CHARS%_-]*" "%ID_CHECK_FILE%" >nul 2>&1
set "ID_RC=!errorlevel!"
del /q "%ID_CHECK_FILE%" >nul 2>&1
if not "!ID_RC!"=="0" ( call :ConfigError "!L_E_IDCHR!" & exit /b 12 )
rem File extension: letters and digits only, at most 10
set "EXT_RC=1"
if defined FILE_EXT if "!FILE_EXT:~10!"=="" (
    >"%ID_CHECK_FILE%" echo(!FILE_EXT!
    %FINDSTR% /r /x /i /c:"[%ID_CHARS%]*" "%ID_CHECK_FILE%" >nul 2>&1
    set "EXT_RC=!errorlevel!"
    del /q "%ID_CHECK_FILE%" >nul 2>&1
)
if not "!EXT_RC!"=="0" ( call :ConfigError "!L_E_EXT! !FILE_EXT!" & exit /b 15 )
set "ARCHIVE_OPTIONS=%SEVENZIP_OPTIONS%"
for %%E in (%STORE_EXTENSIONS%) do if /i "!FILE_EXT!"=="%%E" set "ARCHIVE_OPTIONS=-mx0"

rem === Run state ===
set "STATE_ROOT=%LOG_DIR%\state"
set "INSTANCE_STATE_DIR=%STATE_ROOT%\%INSTANCE_ID%"
set "LAST_SUCCESS_FILE=%INSTANCE_STATE_DIR%\last_success.txt"
set "SENDER_STATE_FILE=%INSTANCE_STATE_DIR%\sender_status.txt"
set "RUN_TAG=%INSTANCE_ID%_%RANDOM%%RANDOM%"
set "METRICS_FILE=%TEMP%\panos_cfg_metrics_%RUN_TAG%.txt"
set "DISCOVERY_FILE=%TEMP%\panos_cfg_discovery_%RUN_TAG%.txt"
set "LIST_FILE=%TEMP%\panos_cfg_list_%RUN_TAG%.txt"
set "CLOCK_FILE=%TEMP%\panos_cfg_clock_%RUN_TAG%.tmp"
set "SENDER_CONF=%TEMP%\panos_cfg_sender_%RUN_TAG%.conf"
rem SENDER_PREVIOUS=1 by default: no false sender alarm on the first run
set /a JOB_STATUS=0,JOB_EXIT=10,FILES_FOUND=0,FILES_PROCESSED=0,FILES_FAILED=0,FILES_PENDING=0,FILES_DEFERRED=0,FILES_RECOVERED=0,FILE_SEQ=0,ARCHIVE_COUNT=0,SENDER_PREVIOUS=1,UTC_OFFSET=0,JOB_START=0,NOW_EPOCH=0
set "LAST_ARCHIVE_SIZE=0"
set "BYTES_PROCESSED=0"
set "ARCHIVE_BYTES=0"
set "COMPRESSION_RATIO=-"
set "JOB_DURATION=0"
set "SENDER_NOW=0"
rem Byte counters in two 32-bit parts (units and billions)
set /a BP_HI=0,BP_LO=0,AB_HI=0,AB_LO=0,FREE_MB=-1,CS_CHECKS=0
set "LAST_SUCCESS=0"
set "LAST_ERROR=None"
set "LOG_READY=0"
set "RUN_ENTERED=0"
set "INSTANCE_NEW=0"
set "CHECK_PREREQ=1"
set "PREREQ_DETAIL="
set "CHECK_PATH=1"
set "PATH_DETAIL=Local paths only"
if "%ALLOW_REMOTE_PATHS%"=="1" set "PATH_DETAIL=Remote paths allowed"

rem === Prerequisites and clock ===
call :CheckPrerequisites
if "%ZABBIX_ENABLED%"=="1" call :SenderTarget
if not defined PREREQ_DETAIL set "PREREQ_DETAIL=OK"
rem Metrics are sent only with Zabbix enabled and zabbix_sender present
set "SEND_ACTIVE=0"
if "%ZABBIX_ENABLED%"=="1" if exist "%ZABBIX_SENDER_PATH%" set "SEND_ACTIVE=1"
if "!CLOCK_OK!"=="1" (
    call :Now
    set "JOB_START=!NOW_EPOCH!"
    set "RUN_YEAR=!NOW_DATE:~0,4!"
    set "RUN_MONTH=!NOW_DATE:~5,2!"
)

rem === Path guard: local disks only ===
set "LOG_PATH_OK=1"
if not "%ALLOW_REMOTE_PATHS%"=="1" (
    call :CheckLocalPath "%SOURCE_DIR%" SRC_LOCAL SRC_WHY 0
    call :CheckLocalPath "%LOG_DIR%" LOG_LOCAL LOG_WHY 0
    if "!ARCHIVE_SEPARATE!"=="1" call :CheckLocalPath "!ARCHIVE_DIR!" ARC_LOCAL ARC_WHY 0
    if "!SRC_LOCAL!"=="0" (
        set "CHECK_PATH=0"
        set "PATH_DETAIL=Source rejected: !SRC_WHY!"
    )
    if "!LOG_LOCAL!"=="0" (
        set "CHECK_PATH=0"
        set "LOG_PATH_OK=0"
        set "PATH_DETAIL=Log directory rejected: !LOG_WHY!"
    )
    if "!ARC_LOCAL!"=="0" (
        set "CHECK_PATH=0"
        set "PATH_DETAIL=Archive folder rejected: !ARC_WHY!"
    )
)
rem The archive folder must be on the volume of the source folder: moving a
rem file is then a rename (instant and atomic), never a copy.
if "!ARCHIVE_SEPARATE!"=="1" if "!CHECK_PATH!"=="1" (
    call :VolumeId "!SOURCE_DIR!" VOL_SRC
    call :VolumeId "!ARCHIVE_DIR!" VOL_ARC
    if not defined VOL_SRC (
        set "CHECK_PATH=0"
        set "PATH_DETAIL=Archive folder rejected: volume of the source folder not determined (link or SUBST in the path)"
    ) else if not defined VOL_ARC (
        set "CHECK_PATH=0"
        set "PATH_DETAIL=Archive folder rejected: volume not determined (link or SUBST in the path)"
    ) else if /i not "!VOL_SRC!"=="!VOL_ARC!" (
        set "CHECK_PATH=0"
        set "PATH_DETAIL=Archive folder rejected: not on the same volume as the source folder"
    )
)

rem === Console header and debug values ===
if "%CONSOLE_OUTPUT%"=="1" (
    echo(
    echo ============================================================
    echo  PAN-OS Config Archiver %SCRIPT_VERSION% - %SCRIPT_AUTHOR% - %SCRIPT_URL%
    echo(
    echo  !L_H_INSTANCE! : !INSTANCE_ID!
    echo  !L_H_SOURCE! : !SOURCE_DIR!
    if "!ARCHIVE_SEPARATE!"=="1" echo  !L_H_ARCHIVE! : !ARCHIVE_DIR!
    echo  !L_H_LOGDIR! : !LOG_DIR!
    echo ============================================================
    echo(
)
if "%DEBUG_OUTPUT%"=="1" (
    call :Debug "UTC offset !UTC_OFFSET! s, clock ok !CLOCK_OK!, run start epoch !JOB_START!"
    call :Debug "Prerequisites: !CHECK_PREREQ! !PREREQ_DETAIL!"
    call :Debug "Path guard: !CHECK_PATH! - !PATH_DETAIL!"
    if "!ARCHIVE_SEPARATE!"=="1" call :Debug "Archive folder: !ARCHIVE_DIR! - volumes !VOL_SRC! !VOL_ARC!"
    call :Debug "DAY_FOLDER_DATE=%DAY_FOLDER_DATE% shift !DATE_SHIFT!, day count lag !DAY_COUNT_LAG_DAYS! from %DAY_COMPLETE_HOUR%:00"
    call :Debug "Extension: !FILE_EXT!, 7-Zip options: !ARCHIVE_OPTIONS!"
    call :Debug "Zabbix: enabled %ZABBIX_ENABLED%, sender active !SEND_ACTIVE!, host %ZABBIX_HOST%, destinations !SENDER_DEST!"
    echo(
)

rem === Local log and state ===
if "!LOG_PATH_OK!"=="1" if "!CLOCK_OK!"=="1" (
    if not exist "%LOG_DIR%\" mkdir "%LOG_DIR%" >nul 2>&1
    if not exist "%INSTANCE_STATE_DIR%\" mkdir "%INSTANCE_STATE_DIR%" >nul 2>&1
    if exist "%INSTANCE_STATE_DIR%\" (
        set "LOG_FILE=%LOG_DIR%\panos_config_archiver_%INSTANCE_ID%_!RUN_YEAR!-!RUN_MONTH!.log"
        set "LOG_READY=1"
        rem Lock directory of version 1.x
        if exist "%INSTANCE_STATE_DIR%\running.lock\" rmdir "%INSTANCE_STATE_DIR%\running.lock" >nul 2>&1
        if exist "%SENDER_STATE_FILE%" set /p SENDER_PREVIOUS=<"%SENDER_STATE_FILE%"
        if exist "%LAST_SUCCESS_FILE%" set /p LAST_SUCCESS=<"%LAST_SUCCESS_FILE%"
    )
)

rem === One run per instance: the lock handle is released even if the run is killed ===
%LOCK_QUIET% ( 9>"%INSTANCE_LOCK%" call :Main )
if not "!RUN_ENTERED!"=="1" (
    set "JOB_EXIT=20"
    call :Log 00 FAILURE "Another run of this instance is active"
)
if "%CONSOLE_OUTPUT%"=="1" call :Summary
for %%F in ("%METRICS_FILE%" "%DISCOVERY_FILE%" "%LIST_FILE%" "%CLOCK_FILE%" "%SENDER_CONF%") do del /q "%%~F" >nul 2>&1
endlocal & exit /b %JOB_EXIT%

rem ---------------------------------------------------------------------------
:Main
set "RUN_ENTERED=1"
call :Log 01 INFO "Job started, version %SCRIPT_VERSION%"
if "!LOG_READY!"=="1" call :PurgeOldLogs

rem Registry and discovery first, so that Zabbix also receives check failures
if not "!CLOCK_OK!"=="1" ( set "LAST_ERROR=Unable to read system clock" & set /a JOB_EXIT=14 & goto :MainFatal )
if not "%ZABBIX_ENABLED%"=="1" (
    call :Log 07 INFO "Zabbix monitoring disabled (ZABBIX_ENABLED=0)"
    goto :MainChecks
)
if not "!SEND_ACTIVE!"=="1" call :Log 07 WARNING "zabbix_sender not found: files are archived, metrics are not sent"
call :UpdateRegistry
if errorlevel 1 ( set "LAST_ERROR=Instance registry update failed" & goto :MainFatal )
if not "!SEND_ACTIVE!"=="1" goto :MainChecks
call :SendDiscovery
if errorlevel 1 call :Log 02 WARNING "LLD discovery transmission failed"
if "!INSTANCE_NEW!"=="1" (
    call :Log 05 INFO "New instance registered, waiting %NEW_INSTANCE_DELAY% s for the Zabbix discovery"
    call :Sleep %NEW_INSTANCE_DELAY%
)

:MainChecks

if "!CHECK_PATH!"=="0" ( set "LAST_ERROR=!PATH_DETAIL!" & set /a JOB_EXIT=13 & goto :MainFatal )
if "!CHECK_PREREQ!"=="0" ( set "LAST_ERROR=Missing prerequisites: !PREREQ_DETAIL!" & set /a JOB_EXIT=14 & goto :MainFatal )
if not "!LOG_READY!"=="1" ( set "LAST_ERROR=Log directory unavailable" & goto :MainFatal )
if not exist "%SOURCE_DIR%\" ( set "LAST_ERROR=Source directory unavailable" & goto :MainFatal )

rem Source writable, free space readable, RUNNING status
set "WRITE_TEST=%SOURCE_DIR%\.panos_cfg_write_%RANDOM%.tmp"
>"%WRITE_TEST%" echo test
if errorlevel 1 ( set "LAST_ERROR=Source directory is not writable" & goto :MainFatal )
del /q "%WRITE_TEST%" >nul 2>&1
if "!ARCHIVE_SEPARATE!"=="1" (
    if not exist "!ARCHIVE_DIR!\" mkdir "!ARCHIVE_DIR!" >nul 2>&1
    if not exist "!ARCHIVE_DIR!\" ( set "LAST_ERROR=Archive folder unavailable" & goto :MainFatal )
    set "WRITE_TEST=!ARCHIVE_DIR!\.panos_cfg_write_%RANDOM%.tmp"
    >"!WRITE_TEST!" echo test
    if not exist "!WRITE_TEST!" ( set "LAST_ERROR=Archive folder is not writable" & goto :MainFatal )
    del /q "!WRITE_TEST!" >nul 2>&1
)
call :DiskFree "%SOURCE_DIR%" DISK_FREE
if not defined DISK_FREE ( set "LAST_ERROR=Unable to determine free disk space" & goto :MainFatal )

if "!SEND_ACTIVE!"=="1" (
    >"%METRICS_FILE%" (
        echo "%ZABBIX_HOST%" panos.cfg.job.status[%INSTANCE_ID%] 3
        echo "%ZABBIX_HOST%" panos.cfg.job.start[%INSTANCE_ID%] !JOB_START!
    )
    call :SendMetrics "%METRICS_FILE%"
    set "SENDER_NOW=1"
    if errorlevel 1 set "SENDER_NOW=0"
    >"%SENDER_STATE_FILE%" echo !SENDER_NOW!
)

rem Reserve in MB for the per-file space check
set "RS_MB=%DISK_RESERVE_BYTES:~0,-6%"
if not defined RS_MB set "RS_MB=0"
set /a RESERVE_MB=RS_MB+1

rem Complete files left in day folders by an interrupted run
call :RecoverOrphans

call :Now
set "SCAN_EPOCH=!NOW_EPOCH!"
rem File list with size and UTC time (robocopy /TS)
%ROBOCOPY% "%SOURCE_DIR%\." "%TEMP%\panos_cfg_void_%RUN_TAG%" *.%FILE_EXT% /L /LEV:1 /NJH /NJS /NDL /NC /BYTES /TS /FP /R:0 /W:0 >"%LIST_FILE%" 2>nul
if errorlevel 8 ( set "LAST_ERROR=Unable to list source directory" & goto :MainFatal )
for /f "usebackq tokens=1-3*" %%A in ("%LIST_FILE%") do (
    if /i "%%~xD"==".%FILE_EXT%" set /a FILES_FOUND+=1
)
call :Log 06 INFO "Files found in the source directory (*.!FILE_EXT!): !FILES_FOUND!"
for /f "usebackq tokens=1-3*" %%A in ("%LIST_FILE%") do (
    if /i "%%~xD"==".%FILE_EXT%" call :ProcessFile "%%D" "%%A" "%%B" "%%C"
)

rem Status: 1 success, 2 partial, 0 failed
set /a JOB_STATUS=1,JOB_EXIT=0
if !FILES_FAILED! GTR 0 (
    if !FILES_PROCESSED! GTR 0 (set /a JOB_STATUS=2,JOB_EXIT=2) else (set /a JOB_STATUS=0,JOB_EXIT=1)
) else if !FILES_FOUND! EQU 0 if !FILES_RECOVERED! EQU 0 (
    call :Log 20 SUCCESS "No files found; valid empty execution"
)
goto :MainEnd

:MainFatal
call :Log 90 FAILURE "!LAST_ERROR!"
set /a JOB_STATUS=0
if !JOB_EXIT! LSS 10 set /a JOB_EXIT=10

:MainEnd
call :SendFinal
exit /b 0

rem ---------------------------------------------------------------------------
rem %1 path, %2 size, %3 UTC date, %4 UTC time. Hot path: few calls, cached values
:ProcessFile
set "FILE_SIZE=%~2"
set /a FILE_SEQ+=1
if "%LOG_FILE_NAMES%"=="1" (set "FILE_LABEL=%~nx1") else set "FILE_LABEL=file #!FILE_SEQ! (!FILE_SIZE! B)"
set "FILE_ERROR=None"
set "REPORT_DIR="
set "FD=%~3"
set "FT=%~4"
set "FD_KEY=PC_D!FD:/=!"
if not defined !FD_KEY! (
    call :DaysFromCivil !FD:~0,4! 1!FD:~5,2!-100 1!FD:~8,2!-100 FD_DAYS
    set "!FD_KEY!=!FD_DAYS!"
)
for %%K in (!FD_KEY!) do set /a "FILE_EPOCH=%%K*86400+(1!FT:~0,2!-100)*3600+(1!FT:~3,2!-100)*60+(1!FT:~6,2!-100)"
set /a FILE_AGE=SCAN_EPOCH-FILE_EPOCH, MIN_AGE=MIN_FILE_AGE_MINUTES*60
if !FILE_AGE! LSS !MIN_AGE! if !FILE_AGE! GTR -3600 (
    set /a FILES_DEFERRED+=1
    call :Log 12 SKIPPED "Deferred, modified !FILE_AGE! s ago: !FILE_LABEL!"
    exit /b 0
)
rem Day folder: date in the file name (YYYY_MM_DD, YYYY-MM-DD, YYYYMMDD[hhmm[ss]]),
rem else modification date; minus DATE_SHIFT
set "FOLDER_DAYS="
if "%DATE_FROM_NAME%"=="1" (
    set "DN_S=%~n1"
    set "DN_S=!DN_S:_= !"
    set "DN_S=!DN_S:-= !"
    set "DN_A="
    set "DN_B="
    set "DN_C="
    for %%T in (!DN_S!) do if not defined FOLDER_DAYS (
        set "DN_A=!DN_B!"
        set "DN_B=!DN_C!"
        set "DN_C=%%T"
        set "DN_T=%%T"
        if not "!DN_T:~7,1!"=="" if "!DN_T:~14!"=="" (
            set "DN_A=!DN_T:~0,4!"
            set "DN_B=!DN_T:~4,2!"
            set "DN_C=!DN_T:~6,2!"
        )
        if defined DN_A if "!DN_A:~4!!DN_B:~2!!DN_C:~2!"=="" if not "!DN_A:~3,1!"=="" if not "!DN_B:~1,1!"=="" if not "!DN_C:~1,1!"=="" (
            for /f "delims=0123456789" %%X in ("!DN_A!!DN_B!!DN_C!x") do if "%%X"=="x" (
                if not defined PC_N!DN_A!!DN_B!!DN_C! call :NameDateDays
                for %%K in (PC_N!DN_A!!DN_B!!DN_C!) do if not "!%%K!"=="x" set "FOLDER_DAYS=!%%K!"
            )
        )
    )
    if not defined FOLDER_DAYS call :Log 15 WARNING "No date in the file name, modification date used: !FILE_LABEL!"
)
if not defined FOLDER_DAYS set /a "FOLDER_DAYS=(FILE_EPOCH+UTC_OFFSET)/86400"
set /a FOLDER_DAYS-=DATE_SHIFT
if not "!FOLDER_DAYS!"=="!LAST_FOLDER_DAYS!" (
    call :DayDirOf !FOLDER_DAYS!
    for %%D in ("!YEAR_DIR!" "!MONTH_DIR!" "!DAY_DIR!") do (
        if not exist "%%~D\" mkdir "%%~D" >nul 2>&1
        if not exist "%%~D\" ( set "FILE_ERROR=Unable to create destination directory" & goto :FileFailed )
    )
    set "LAST_FOLDER_DAYS=!FOLDER_DAYS!"
)
set "REPORT_DIR=!DAY_DIR!\report"
if "%DEBUG_OUTPUT%"=="1" call :Debug "%~nx1 to !DAY_DIR!"
set "DEST_FILE=!DAY_DIR!\%~nx1"
set "ARCHIVE_FILE=!DAY_DIR!\%~nx1.7z"
if exist "!DEST_FILE!" ( set "FILE_ERROR=Destination file already exists" & goto :FileFailed )
if exist "!ARCHIVE_FILE!" ( set "FILE_ERROR=Destination archive already exists" & goto :FileFailed )
rem Space check in MB; real free space re-read every 50 files or near the reserve
set "CS_MB=!FILE_SIZE:~0,-6!"
if not defined CS_MB set "CS_MB=0"
set /a CS_MB+=1, CS_CHECKS+=1
set /a CS_LEFT=FREE_MB-CS_MB-RESERVE_MB
if !FREE_MB! LSS 0 set /a CS_CHECKS=50
if !CS_LEFT! LSS 1024 set /a CS_CHECKS=50
if !CS_CHECKS! GEQ 50 (
    call :RefreshFreeMB
    set /a CS_CHECKS=0, CS_LEFT=FREE_MB-CS_MB-RESERVE_MB
    if "%DEBUG_OUTPUT%"=="1" call :Debug "Free space read: !FREE_MB! MB, reserve !RESERVE_MB! MB"
)
if !FREE_MB! LSS 0 ( set "FILE_ERROR=Unable to determine free disk space" & goto :FileFailed )
if !CS_LEFT! LSS 0 ( set "FILE_ERROR=Insufficient free disk space to archive safely" & goto :FileFailed )
set /a FREE_MB-=1
move "%~f1" "!DEST_FILE!" >nul 2>&1
if errorlevel 1 ( set "FILE_ERROR=File move failed" & goto :FileFailed )
call :ArchiveInPlace "!DEST_FILE!" "!ARCHIVE_FILE!"
if errorlevel 1 goto :FileFailed
call :Log 10 SUCCESS "File archived and verified: !FILE_LABEL!"
exit /b 0

:FileFailed
set /a FILES_FAILED+=1
set "LAST_ERROR=!FILE_ERROR!"
call :Log 11 FAILURE "!FILE_ERROR!: !FILE_LABEL!"
if defined REPORT_DIR call :ReportFailure "%~nx1"
exit /b 1

rem One report\FAILED-JOB.txt per day folder, written only on failure
:ReportFailure
if not exist "!REPORT_DIR!\" mkdir "!REPORT_DIR!" >nul 2>&1
>>"!REPORT_DIR!\FAILED-JOB.txt" echo [!LOG_TS!] %~1: !FILE_ERROR!
exit /b 0

:RefreshFreeMB
set /a FREE_MB=-1
call :DiskFree "%SOURCE_DIR%" RF_FREE
if not defined RF_FREE exit /b 0
set "RF_MB=!RF_FREE:~0,-6!"
if not defined RF_MB set "RF_MB=0"
set /a FREE_MB=RF_MB
exit /b 0

rem %1 size: fails if DISK_RESERVE_BYTES would not remain (recovery path)
:CheckSpace
set "CS_FREE="
call :DiskFree "%SOURCE_DIR%" CS_FREE
if not defined CS_FREE ( set "FILE_ERROR=Unable to determine free disk space" & exit /b 1 )
set "CS_NEED=%DISK_RESERVE_BYTES%"
call :BigAdd CS_NEED "%~1"
call :BigLess "!CS_FREE!" "!CS_NEED!"
if "!BIG_LESS!"=="1" ( set "FILE_ERROR=Insufficient free disk space to archive safely" & exit /b 1 )
exit /b 0

rem %1 file, %2 archive: compress, test, delete the file, update counters
:ArchiveInPlace
"%SEVENZIP_PATH%" a -t7z %ARCHIVE_OPTIONS% -bd -y "%~2" "%~1" %QUIET%
if errorlevel 1 (
    del /q "%~2" >nul 2>&1
    set "FILE_ERROR=Archive creation failed"
    exit /b 1
)
"%SEVENZIP_PATH%" t "%~2" %QUIET%
if errorlevel 1 (
    del /q "%~2" >nul 2>&1
    set "FILE_ERROR=Archive integrity test failed"
    exit /b 1
)
del /q "%~1" >nul 2>&1
if exist "%~1" ( set "FILE_ERROR=Source file deletion failed" & exit /b 1 )
for %%S in ("%~2") do set "LAST_ARCHIVE_SIZE=%%~zS"
set /a FILES_PROCESSED+=1,ARCHIVE_COUNT+=1
for %%P in ("BP:!FILE_SIZE!" "AB:!LAST_ARCHIVE_SIZE!") do for /f "tokens=1,2 delims=:" %%a in (%%P) do (
    set "ACC_V=000000000%%b"
    set "ACC_H=%%b"
    set "ACC_H=!ACC_H:~0,-9!"
    set /a "%%a_LO+=1!ACC_V:~-9!-1000000000"
    if defined ACC_H set /a "%%a_HI+=ACC_H"
    if !%%a_LO! GEQ 1000000000 set /a "%%a_HI+=1, %%a_LO-=1000000000"
)
exit /b 0

rem %1 days since 1970-01-01: YEAR, MONTH, DAY and folder paths
:DayDirOf
call :CivilFromDays %~1 YEAR MONTH DAY
set "YEAR_DIR=!ARCHIVE_DIR!\!YEAR!"
set "MONTH_DIR=!YEAR_DIR!\!MONTH!-!YEAR!"
if not "%MONTH_FOLDER_NAME%"=="none" (
    call :MonthName !MONTH! MONTH_NAME
    set "MONTH_DIR=!MONTH_DIR! (!MONTH_NAME!)"
)
set "DAY_DIR=!MONTH_DIR!\!DAY!-!MONTH!-!YEAR!"
exit /b 0

rem Caches the days of DN_A DN_B DN_C in PC_N+YYYYMMDD (x = not a date)
:NameDateDays
set "DN_DAYS="
call :CheckYMD
if not defined DN_DAYS set "DN_DAYS=x"
set "PC_N!DN_A!!DN_B!!DN_C!=!DN_DAYS!"
exit /b 0

rem Real date check; the round trip rejects dates such as 31-02
:CheckYMD
if not defined DN_A exit /b 0
if "!DN_A:~3,1!"=="" exit /b 0
if not "!DN_A:~4!"=="" exit /b 0
if "!DN_B:~1,1!"=="" exit /b 0
if not "!DN_B:~2!"=="" exit /b 0
if "!DN_C:~1,1!"=="" exit /b 0
if not "!DN_C:~2!"=="" exit /b 0
call :IsNumber "!DN_A!!DN_B!!DN_C!" DN_OK
if not "!DN_OK!"=="1" exit /b 0
set /a DN_Y=1!DN_A!-10000, DN_M=1!DN_B!-100, DN_D=1!DN_C!-100
if !DN_Y! LSS 2000 exit /b 0
if !DN_Y! GTR 2099 exit /b 0
if !DN_M! LSS 1 exit /b 0
if !DN_M! GTR 12 exit /b 0
if !DN_D! LSS 1 exit /b 0
call :DaysFromCivil !DN_Y! !DN_M! !DN_D! DN_X
call :CivilFromDays !DN_X! DN_RY DN_RM DN_RD
if not "!DN_RY!!DN_RM!!DN_RD!"=="!DN_A!!DN_B!!DN_C!" exit /b 0
set "DN_DAYS=!DN_X!"
exit /b 0

rem Calls label %1 for each day folder (current and pre-2.3 layout)
:ForEachDayDir
for /d %%Y in ("!ARCHIVE_DIR!\????") do (
    for /d %%M in ("%%~fY\??-????*") do (
        for /d %%D in ("%%~fM\??-??-????") do call :%~1 "%%~fD"
    )
)
for /d %%M in ("!ARCHIVE_DIR!\??-???? (*)") do (
    for /d %%D in ("%%~fM\??-??-????") do call :%~1 "%%~fD"
)
exit /b 0

rem File name or "file #N (size B)" for the log
:FileLabel
set /a FILE_SEQ+=1
if "%LOG_FILE_NAMES%"=="1" (set "FILE_LABEL=%~1") else set "FILE_LABEL=file #!FILE_SEQ! (!FILE_SIZE! B)"
exit /b 0

rem ---------------------------------------------------------------------------
rem Interrupted runs: files still inside day folders
:RecoverOrphans
call :ForEachDayDir RecoverOrphansIn
exit /b 0

:RecoverOrphansIn
for %%F in ("%~1\*.%FILE_EXT%") do if /i "%%~xF"==".%FILE_EXT%" call :RecoverOrphan "%%~fF"
exit /b 0

rem Valid archive: delete the file; invalid archive: rename it, archive again
:RecoverOrphan
set "FILE_SIZE=%~z1"
call :FileLabel "%~nx1"
set "FILE_ERROR=None"
set "REPORT_DIR=%~dp1report"
set "ARCHIVE_FILE=%~f1.7z"
if not exist "!ARCHIVE_FILE!" goto :RecoverOrphanArchive
call :ArchiveContains "!ARCHIVE_FILE!" "%~nx1" "%~z1"
if "!ARCHIVE_MATCH!"=="1" (
    del /q "%~f1" >nul 2>&1
    if exist "%~f1" ( set "FILE_ERROR=Orphan file deletion failed" & goto :OrphanFailed )
    set /a FILES_RECOVERED+=1
    call :Log 13 SUCCESS "Orphan file removed, archive already complete: !FILE_LABEL!"
    exit /b 0
)
call :Now
move "!ARCHIVE_FILE!" "!ARCHIVE_FILE!.invalid-!NOW_EPOCH!" >nul 2>&1
if exist "!ARCHIVE_FILE!" ( set "FILE_ERROR=Unable to set aside invalid archive" & goto :OrphanFailed )
call :Log 14 WARNING "Invalid archive renamed to *.7z.invalid-!NOW_EPOCH!: !FILE_LABEL!"
:RecoverOrphanArchive
call :CheckSpace "!FILE_SIZE!"
if errorlevel 1 goto :OrphanFailed
call :ArchiveInPlace "%~f1" "!ARCHIVE_FILE!"
if errorlevel 1 goto :OrphanFailed
set /a FILES_RECOVERED+=1
call :Log 13 SUCCESS "Orphan file archived and verified: !FILE_LABEL!"
exit /b 0

:OrphanFailed
set /a FILES_FAILED+=1
set "LAST_ERROR=!FILE_ERROR!"
call :Log 11 FAILURE "!FILE_ERROR!: !FILE_LABEL!"
call :ReportFailure "%~nx1"
exit /b 1

rem ARCHIVE_MATCH=1 if archive %1 is valid and contains %2 with size %3
:ArchiveContains
set "ARCHIVE_MATCH=0"
"%SEVENZIP_PATH%" t "%~1" %QUIET%
if errorlevel 1 exit /b 0
set "AC_STATE=0"
set "AC_LIST=%TEMP%\panos_cfg_7zlist_%RUN_TAG%.txt"
"%SEVENZIP_PATH%" l -slt "%~1" >"%AC_LIST%" 2>nul
for /f "usebackq tokens=1,* delims==" %%A in ("%AC_LIST%") do (
    set "AC_KEY=%%A"
    set "AC_VAL=%%B"
    if "!AC_STATE!"=="1" if "!AC_KEY!"=="Size " (
        if "!AC_VAL!"==" %~3" set "ARCHIVE_MATCH=1"
        set "AC_STATE=2"
    )
    if "!AC_KEY!"=="Path " if /i "!AC_VAL!"==" %~2" set "AC_STATE=1"
)
del /q "%AC_LIST%" >nul 2>&1
exit /b 0

rem ---------------------------------------------------------------------------
rem Final metrics; unknown values are omitted, never sent as 0
:SendFinal
call :Now
set "JOB_END=!NOW_EPOCH!"
set /a JOB_DURATION=JOB_END-JOB_START
if !JOB_DURATION! LSS 0 set /a JOB_DURATION=0
if !JOB_STATUS! EQU 1 (
    set "LAST_SUCCESS=!JOB_END!"
    if "!LOG_READY!"=="1" >"%LAST_SUCCESS_FILE%" echo !LAST_SUCCESS!
)
if not defined PREREQ_DETAIL set "PREREQ_DETAIL=OK"
set "DISK_FREE="
set "DISK_TOTAL="
set "DISK_PFREE="
set "COMPRESSION_RATIO="
set "ARCH_STATS=0"
if "!CHECK_PATH!"=="1" if exist "%SOURCE_DIR%\" (
    call :DiskFree "%SOURCE_DIR%" DISK_FREE
    call :DiskTotal "%SOURCE_DIR%" DISK_TOTAL
    if defined DISK_FREE if defined DISK_TOTAL call :Percent "!DISK_FREE!" "!DISK_TOTAL!" DISK_PFREE
    call :ScanPending
    if exist "!ARCHIVE_DIR!\" call :ArchiveStats
)
for %%a in (BP AB) do (
    if !%%a_HI! GTR 0 (
        set "ACC_V=000000000!%%a_LO!"
        set "%%a_STR=!%%a_HI!!ACC_V:~-9!"
    ) else (
        set "%%a_STR=!%%a_LO!"
    )
)
set "BYTES_PROCESSED=!BP_STR!"
set "ARCHIVE_BYTES=!AB_STR!"
if !FILES_PROCESSED! GTR 0 call :Percent "!ARCHIVE_BYTES!" "!BYTES_PROCESSED!" COMPRESSION_RATIO
if not "%ZABBIX_ENABLED%"=="1" exit /b 0
if not "!SEND_ACTIVE!"=="1" (
    if "!LOG_READY!"=="1" >"%SENDER_STATE_FILE%" echo 0
    call :Log 99 WARNING "Metrics not sent: zabbix_sender not found, exit code !JOB_EXIT!"
    exit /b 0
)
>"%METRICS_FILE%" (
    echo "%ZABBIX_HOST%" panos.cfg.job.status[%INSTANCE_ID%] !JOB_STATUS!
    echo "%ZABBIX_HOST%" panos.cfg.job.start[%INSTANCE_ID%] !JOB_START!
    echo "%ZABBIX_HOST%" panos.cfg.job.last.run[%INSTANCE_ID%] !JOB_END!
    if not "!LAST_SUCCESS!"=="0" echo "%ZABBIX_HOST%" panos.cfg.job.last.success[%INSTANCE_ID%] !LAST_SUCCESS!
    echo "%ZABBIX_HOST%" panos.cfg.job.duration[%INSTANCE_ID%] !JOB_DURATION!
    echo "%ZABBIX_HOST%" panos.cfg.job.exitcode[%INSTANCE_ID%] !JOB_EXIT!
    echo "%ZABBIX_HOST%" panos.cfg.files.found[%INSTANCE_ID%] !FILES_FOUND!
    echo "%ZABBIX_HOST%" panos.cfg.files.processed[%INSTANCE_ID%] !FILES_PROCESSED!
    echo "%ZABBIX_HOST%" panos.cfg.files.failed[%INSTANCE_ID%] !FILES_FAILED!
    echo "%ZABBIX_HOST%" panos.cfg.files.deferred[%INSTANCE_ID%] !FILES_DEFERRED!
    echo "%ZABBIX_HOST%" panos.cfg.files.recovered[%INSTANCE_ID%] !FILES_RECOVERED!
    echo "%ZABBIX_HOST%" panos.cfg.bytes.processed[%INSTANCE_ID%] !BYTES_PROCESSED!
    echo "%ZABBIX_HOST%" panos.cfg.archive.count[%INSTANCE_ID%] !ARCHIVE_COUNT!
    echo "%ZABBIX_HOST%" panos.cfg.archive.last.size[%INSTANCE_ID%] !LAST_ARCHIVE_SIZE!
    if defined COMPRESSION_RATIO echo "%ZABBIX_HOST%" panos.cfg.compression.ratio[%INSTANCE_ID%] !COMPRESSION_RATIO!
    if "!ARCH_STATS!"=="1" (
        echo "%ZABBIX_HOST%" panos.cfg.files.pending[%INSTANCE_ID%] !FILES_PENDING!
        echo "%ZABBIX_HOST%" panos.cfg.source.oldest.age[%INSTANCE_ID%] !SOURCE_OLDEST_AGE!
        if defined ARCH_TOTAL_SIZE echo "%ZABBIX_HOST%" panos.cfg.archive.total.size[%INSTANCE_ID%] !ARCH_TOTAL_SIZE!
        if defined ARCH_TOTAL_FILES echo "%ZABBIX_HOST%" panos.cfg.archive.total.files[%INSTANCE_ID%] !ARCH_TOTAL_FILES!
        echo "%ZABBIX_HOST%" panos.cfg.archive.oldest[%INSTANCE_ID%] !ARCH_OLDEST!
        echo "%ZABBIX_HOST%" panos.cfg.files.orphaned[%INSTANCE_ID%] !FILES_ORPHANED!
        echo "%ZABBIX_HOST%" panos.cfg.archive.invalid[%INSTANCE_ID%] !ARCH_INVALID!
        echo "%ZABBIX_HOST%" panos.cfg.day.files[%INSTANCE_ID%] !DAY_FILES!
        echo "%ZABBIX_HOST%" panos.cfg.day.date[%INSTANCE_ID%] !DAY_FILES_DATE!
    )
    if defined DISK_FREE echo "%ZABBIX_HOST%" panos.cfg.disk.free[%INSTANCE_ID%] !DISK_FREE!
    if defined DISK_TOTAL echo "%ZABBIX_HOST%" panos.cfg.disk.total[%INSTANCE_ID%] !DISK_TOTAL!
    if defined DISK_PFREE echo "%ZABBIX_HOST%" panos.cfg.disk.pfree[%INSTANCE_ID%] !DISK_PFREE!
    echo "%ZABBIX_HOST%" panos.cfg.last.error[%INSTANCE_ID%] "!LAST_ERROR!"
    echo "%ZABBIX_HOST%" panos.cfg.sender.status[%INSTANCE_ID%] !SENDER_PREVIOUS!
    echo "%ZABBIX_HOST%" panos.cfg.check.prereq[%INSTANCE_ID%] !CHECK_PREREQ!
    echo "%ZABBIX_HOST%" panos.cfg.check.prereq.detail[%INSTANCE_ID%] "!PREREQ_DETAIL!"
    echo "%ZABBIX_HOST%" panos.cfg.check.path[%INSTANCE_ID%] !CHECK_PATH!
    echo "%ZABBIX_HOST%" panos.cfg.check.path.detail[%INSTANCE_ID%] "!PATH_DETAIL!"
    echo "%ZABBIX_HOST%" panos.cfg.script.version[%INSTANCE_ID%] "%SCRIPT_VERSION%"
)
call :SendMetrics "%METRICS_FILE%"
set "SENDER_NOW=1"
if errorlevel 1 set "SENDER_NOW=0"
if "!LOG_READY!"=="1" >"%SENDER_STATE_FILE%" echo !SENDER_NOW!
if "!SENDER_NOW!"=="1" (
    call :Log 99 SUCCESS "Final metrics transmitted, exit code !JOB_EXIT!"
) else (
    call :Log 99 WARNING "Final Zabbix transmission failed"
)
exit /b 0

rem ---------------------------------------------------------------------------
rem Sets CHECK_PREREQ and PREREQ_DETAIL
:CheckPrerequisites
set "CLOCK_OK=0"
for %%T in ("%ROBOCOPY%" "%FINDSTR%" "%SORT%" "%MOUNTVOL%" "%NET%" "%SUBST%" "%PING%") do (
    if not exist "%%~T" call :AddMissing "%%~nxT not found"
)
if not exist "%SEVENZIP_PATH%" (
    call :AddMissing "7-Zip not found"
) else (
    "%SEVENZIP_PATH%" i >nul 2>&1
    if errorlevel 1 (call :AddMissing "7-Zip not executable") else call :CheckSevenZipOptions
)
if exist "%ROBOCOPY%" call :ClockInit
if not "!CLOCK_OK!"=="1" call :AddMissing "System clock not readable"
exit /b 0

rem Test compression with the options of this job
:CheckSevenZipOptions
set "SZ_TEST=%TEMP%\panos_cfg_7ztest_%RUN_TAG%"
>"%SZ_TEST%.txt" echo 7-Zip options test
"%SEVENZIP_PATH%" a -t7z %ARCHIVE_OPTIONS% -bd -y "%SZ_TEST%.7z" "%SZ_TEST%.txt" >nul 2>&1
if errorlevel 1 call :AddMissing "7-Zip rejects the archive options"
del /q "%SZ_TEST%.txt" "%SZ_TEST%.7z" >nul 2>&1
exit /b 0

:AddMissing
set "CHECK_PREREQ=0"
if defined PREREQ_DETAIL (set "PREREQ_DETAIL=!PREREQ_DETAIL!; %~1") else set "PREREQ_DETAIL=%~1"
exit /b 0

rem ---------------------------------------------------------------------------
rem %1 path, %2 result (1 local), %3 reason, %4 depth: UNC, network, SUBST, links
:CheckLocalPath
setlocal
set "CLP_PATH=%~f1"
set "CLP_RES=1"
set "CLP_WHY=Local path"
set /a CLP_DEPTH=%~4+1
if !CLP_DEPTH! GTR 8 ( set "CLP_RES=0" & set "CLP_WHY=Path resolution too deep" & goto :CLP_End )
if "!CLP_PATH:~0,2!"=="\\" ( set "CLP_RES=0" & set "CLP_WHY=UNC or device path" & goto :CLP_End )
if not "!CLP_PATH:~1,1!"==":" ( set "CLP_RES=0" & set "CLP_WHY=Unsupported path format" & goto :CLP_End )
set "CLP_DRV=!CLP_PATH:~0,2!"
set "CLP_SUBST="
for /f "tokens=1,* delims=>" %%A in ('%SUBST% 2^>nul') do (
    set "CLP_LINE=%%A"
    if /i "!CLP_LINE:~0,3!"=="!CLP_DRV!\" set "CLP_SUBST=%%B"
)
if defined CLP_SUBST (
    call :CheckLocalPath "!CLP_SUBST:~1!!CLP_PATH:~2!" CLP_RES CLP_WHY !CLP_DEPTH!
    goto :CLP_End
)
%NET% use !CLP_DRV! >nul 2>&1
if not errorlevel 1 ( set "CLP_RES=0" & set "CLP_WHY=Network drive !CLP_DRV!" & goto :CLP_End )
%MOUNTVOL% !CLP_DRV!\ /L >nul 2>&1
if errorlevel 1 ( set "CLP_RES=0" & set "CLP_WHY=Drive !CLP_DRV! is not a local volume" & goto :CLP_End )
set "CLP_CUR=!CLP_PATH!"
:CLP_Walk
if "!CLP_CUR:~-1!"=="\" set "CLP_CUR=!CLP_CUR:~0,-1!"
if "!CLP_CUR:~2!"=="" goto :CLP_End
set "CLP_ATTR="
for %%I in ("!CLP_CUR!") do (
    set "CLP_PARENT=%%~dpI"
    set "CLP_LEAF=%%~nxI"
    if exist "%%~I" set "CLP_ATTR=%%~aI"
)
if defined CLP_ATTR if not "!CLP_ATTR:l=!"=="!CLP_ATTR!" (
    call :CheckLinkTarget
    if "!CLP_RES!"=="0" goto :CLP_End
)
set "CLP_CUR=!CLP_PARENT!"
goto :CLP_Walk
:CLP_End
endlocal & set "%~2=%CLP_RES%" & set "%~3=%CLP_WHY%"
exit /b 0

rem %1 path, %2 result: volume GUID of the path (first mount point or drive
rem root above it); empty when a link or an unresolved SUBST drive is met
:VolumeId
setlocal
set "VI_P=%~f1"
call :ResolveSubst "!VI_P!" VI_P
set "VI_R="
:VolumeIdWalk
if "!VI_P:~-1!"=="\" set "VI_P=!VI_P:~0,-1!"
if exist "!VI_P!\" (
    rem Doubled backslash: mountvol must not see a quote escaped by the last backslash
    for /f %%G in ('%MOUNTVOL% "!VI_P!\\" /L 2^>nul') do (
        set "VI_T=%%G"
        if not defined VI_R if "!VI_T:~0,11!"=="\\?\Volume{" set "VI_R=%%G"
    )
    if defined VI_R goto :VolumeIdEnd
    set "VI_A="
    for %%I in ("!VI_P!") do set "VI_A=%%~aI"
    if defined VI_A if not "!VI_A:l=!"=="!VI_A!" goto :VolumeIdEnd
)
if "!VI_P:~2!"=="" goto :VolumeIdEnd
for %%I in ("!VI_P!") do set "VI_P=%%~dpI"
goto :VolumeIdWalk
:VolumeIdEnd
endlocal & set "%~2=%VI_R%"
exit /b 0

rem %1 path, %2 result: the path with SUBST drives replaced by their target
:ResolveSubst
setlocal
set "RS_P=%~1"
set /a RS_N=0
:ResolveSubstLoop
set "RS_T="
set "RS_DRV=!RS_P:~0,2!"
for /f "tokens=1,* delims=>" %%A in ('%SUBST% 2^>nul') do (
    set "RS_L=%%A"
    if /i "!RS_L:~0,3!"=="!RS_DRV!\" set "RS_T=%%B"
)
if defined RS_T if !RS_N! LSS 5 (
    set "RS_P=!RS_T:~1!!RS_P:~2!"
    set /a RS_N+=1
    goto :ResolveSubstLoop
)
endlocal & set "%~2=%RS_P%"
exit /b 0

rem The target of link CLP_LEAF in CLP_PARENT must be local
:CheckLinkTarget
set "CLP_TGT="
for /f "tokens=1,* delims=[" %%A in ('dir /a:l "!CLP_PARENT!" 2^>nul ^| %FINDSTR% /l /c:" !CLP_LEAF! ["') do set "CLP_TGT=%%B"
if not defined CLP_TGT ( set "CLP_RES=0" & set "CLP_WHY=Unable to resolve a link in the path" & exit /b 0 )
set "CLP_TGT=!CLP_TGT:~0,-1!"
if "!CLP_TGT:~0,4!"=="\??\" set "CLP_TGT=!CLP_TGT:~4!"
if /i "!CLP_TGT:~0,4!"=="UNC\" ( set "CLP_RES=0" & set "CLP_WHY=A link in the path points to a network path" & exit /b 0 )
if "!CLP_TGT:~0,2!"=="\\" ( set "CLP_RES=0" & set "CLP_WHY=A link in the path points to a network path" & exit /b 0 )
if /i "!CLP_TGT:~0,7!"=="Volume{" exit /b 0
if "!CLP_TGT:~1,1!"==":" (
    call :CheckLocalPath "!CLP_TGT!" CLP_RES CLP_WHY !CLP_DEPTH!
) else (
    call :CheckLocalPath "!CLP_PARENT!!CLP_TGT!" CLP_RES CLP_WHY !CLP_DEPTH!
)
exit /b 0

rem ---------------------------------------------------------------------------
rem Instance registry, serialized by a lock file (30 attempts)
:UpdateRegistry
set "REG_DONE=0"
set /a REG_TRY=0
:UpdateRegistryRetry
set /a REG_TRY+=1
2>nul ( 8>"%INSTANCE_REGISTRY%.lock" call :UpdateRegistryLocked )
if "!REG_DONE!"=="1" exit /b 0
if "!REG_DONE!"=="2" exit /b 1
if !REG_TRY! GEQ 30 exit /b 1
call :Sleep 1
goto :UpdateRegistryRetry

:UpdateRegistryLocked
set "REG_DONE=2"
set "INSTANCE_NEW=1"
set "REG_TMP1=%INSTANCE_REGISTRY%.tmp1"
set "REG_TMP2=%INSTANCE_REGISTRY%.tmp2"
set "REG_TMP3=%INSTANCE_REGISTRY%.tmp3"
set /a REG_CUTOFF=NOW_EPOCH-INSTANCE_RETENTION_DAYS*86400
if not exist "%INSTANCE_REGISTRY%" type nul >"%INSTANCE_REGISTRY%"
>"%REG_TMP1%" (
    for /f "tokens=1,2 delims=|" %%A in ('%FINDSTR% /r /x /c:"[%ID_CHARS%][%ID_CHARS%_-]*|[0123456789][0123456789]*" "%INSTANCE_REGISTRY%"') do (
        if "%%A"=="%INSTANCE_ID%" (
            set "INSTANCE_NEW=0"
        ) else if %%B GEQ !REG_CUTOFF! (
            echo %%A^|%%B
        )
    )
    echo %INSTANCE_ID%^|!NOW_EPOCH!
)
if not exist "%REG_TMP1%" exit /b 1
%SORT% "%REG_TMP1%" /o "%REG_TMP2%" >nul 2>&1
if not exist "%REG_TMP2%" exit /b 1
set "REG_PREV="
>"%REG_TMP3%" (
    for /f "usebackq tokens=1,2 delims=|" %%A in ("%REG_TMP2%") do (
        if not "%%A"=="!REG_PREV!" echo %%A^|%%B
        set "REG_PREV=%%A"
    )
)
move /y "%REG_TMP3%" "%INSTANCE_REGISTRY%" >nul 2>&1
if errorlevel 1 exit /b 1
del /q "%REG_TMP1%" "%REG_TMP2%" >nul 2>&1
set "REG_DONE=1"
exit /b 0

rem LLD JSON through an input file (escaped quotes)
:SendDiscovery
set "LLD_JSON="
for /f "usebackq tokens=1 delims=|" %%I in ("%INSTANCE_REGISTRY%") do (
    if defined LLD_JSON set "LLD_JSON=!LLD_JSON!,"
    set "LLD_JSON=!LLD_JSON!{\"{#INSTANCE}\":\"%%I\"}"
)
>"%DISCOVERY_FILE%" echo "%ZABBIX_HOST%" panos.cfg.discovery "[!LLD_JSON!]"
call :SendFile "%DISCOVERY_FILE%" %DISCOVERY_RETRY_COUNT% %DISCOVERY_RETRY_DELAY%
exit /b

rem New instance: a rejected send is retried once after a new discovery
:SendMetrics
call :SendFile "%~1" %METRICS_RETRY_COUNT% %METRICS_RETRY_DELAY%
set "SM_RC=!errorlevel!"
if not "!SM_RC!"=="2" exit /b !SM_RC!
if not "!INSTANCE_NEW!"=="1" exit /b 2
call :Log 04 WARNING "New instance: items not ready in Zabbix yet, discovery sent again and metrics retried"
call :SendDiscovery
call :Sleep %NEW_INSTANCE_DELAY%
call :SendFile "%~1" %METRICS_RETRY_COUNT% %METRICS_RETRY_DELAY%
exit /b

rem zabbix_sender destination: -z/-p for one server, or a temporary agent
rem configuration with ServerActive for several (comma = independent servers,
rem semicolon = nodes of one HA cluster); entries without port get ZABBIX_PORT
:SenderTarget
set "SENDER_TARGET=-z "!ZABBIX_SERVER!" -p "!ZABBIX_PORT!""
set "SENDER_DEST=!ZABBIX_SERVER!:!ZABBIX_PORT!"
set "SENDER_MULTI=0"
set "ST_ALL=!ZABBIX_SERVER: =!"
if "!ST_ALL:,=!!ST_ALL:;=!"=="!ST_ALL!!ST_ALL!" exit /b 0
set "ST_OUT="
:SenderTargetGroup
if not defined ST_ALL goto :SenderTargetWrite
set "ST_GROUP="
for /f "tokens=1* delims=," %%a in ("!ST_ALL!") do (
    set "ST_GROUP=%%a"
    set "ST_ALL=%%b"
)
if not defined ST_GROUP goto :SenderTargetWrite
set "ST_NODES="
:SenderTargetNode
if not defined ST_GROUP goto :SenderTargetNodeDone
set "ST_NODE="
for /f "tokens=1* delims=;" %%a in ("!ST_GROUP!") do (
    set "ST_NODE=%%a"
    set "ST_GROUP=%%b"
)
if not defined ST_NODE goto :SenderTargetNodeDone
if "!ST_NODE::=!"=="!ST_NODE!" set "ST_NODE=!ST_NODE!:%ZABBIX_PORT%"
if defined ST_NODES (set "ST_NODES=!ST_NODES!;!ST_NODE!") else set "ST_NODES=!ST_NODE!"
goto :SenderTargetNode
:SenderTargetNodeDone
if defined ST_NODES if defined ST_OUT (set "ST_OUT=!ST_OUT!,!ST_NODES!") else if defined ST_NODES set "ST_OUT=!ST_NODES!"
goto :SenderTargetGroup
:SenderTargetWrite
>"%SENDER_CONF%" echo ServerActive=!ST_OUT!
set "SENDER_TARGET=-c "%SENDER_CONF%""
set "SENDER_DEST=!ST_OUT!"
if not "!ST_OUT:,=!"=="!ST_OUT!" set "SENDER_MULTI=1"
exit /b 0

rem %1 file, %2 attempts, %3 delay; exit 2 = rejected by Zabbix, not retried
rem (with several servers also: one unreachable, the others received the data)
:SendFile
if not exist "%ZABBIX_SENDER_PATH%" exit /b 1
set /a SEND_TRY=0
:SendFileRetry
set /a SEND_TRY+=1
if "%DEBUG_OUTPUT%"=="1" (
    call :Debug "zabbix_sender attempt !SEND_TRY!, data:"
    type "%~1"
    echo(
)
"%ZABBIX_SENDER_PATH%" %SENDER_VERBOSE% %SENDER_TARGET% -i "%~1" %QUIET%
set "SEND_RC=!errorlevel!"
if "%DEBUG_OUTPUT%"=="1" call :Debug "zabbix_sender exit code !SEND_RC!"
if "!SEND_RC!"=="0" exit /b 0
if "!SEND_RC!"=="2" (
    if "!SENDER_MULTI!"=="1" (
        call :Log 03 WARNING "At least one Zabbix destination rejected the values or was unreachable"
    ) else call :Log 03 WARNING "Zabbix rejected some or all values"
    exit /b 2
)
if !SEND_TRY! GEQ %~2 exit /b 1
call :Sleep %~3
goto :SendFileRetry

rem ---------------------------------------------------------------------------
rem Delete monthly logs older than LOG_RETENTION_MONTHS
:PurgeOldLogs
set /a PL_KEEP=LOG_RETENTION_MONTHS
if !PL_KEEP! LSS 6 set /a PL_KEEP=6
set /a PL_LIMIT=(1!RUN_YEAR!-10000)*12+(1!RUN_MONTH!-100)-1-PL_KEEP-1
for %%F in ("%LOG_DIR%\panos_config_archiver_%INSTANCE_ID%_????-??.log") do call :PurgeLogFile "%%~fF"
exit /b 0

:PurgeLogFile
set "PL_NAME=%~n1"
set "PL_YM=!PL_NAME:~-7!"
if /i not "!PL_NAME!"=="panos_config_archiver_%INSTANCE_ID%_!PL_YM!" exit /b 0
if not "!PL_YM:~4,1!"=="-" exit /b 0
set "PL_DIGITS=!PL_YM:-=!x"
for /f "delims=0123456789" %%X in ("!PL_DIGITS!") do if not "%%X"=="x" exit /b 0
set /a PL_IDX=(1!PL_YM:~0,4!-10000)*12+(1!PL_YM:~5,2!-100)-1
if !PL_IDX! GTR !PL_LIMIT! exit /b 0
del /q "%~1" >nul 2>&1
if exist "%~1" (
    call :Log 31 WARNING "Unable to delete expired log file %~nx1"
) else (
    call :Log 30 INFO "Expired log file deleted: %~nx1"
)
exit /b 0

rem ---------------------------------------------------------------------------
rem Archive totals, oldest day, orphans, invalid archives, daily count
:ArchiveStats
set "ARCH_TOTAL_SIZE="
set "ARCH_TOTAL_FILES="
set "ARCH_OLDEST=0"
set /a FILES_ORPHANED=0,ARCH_INVALID=0
call :Now
set "AS_T0=!NOW_EPOCH!"
rem Totals from the robocopy summary only (/NFL /NDL): a "for /f" over "dir /s"
rem would read one line per archive, hours with hundreds of thousands of them.
rem After the "-----" line the numeric rows are Dirs, Files, Bytes (any language).
set /a AS_SUM=0,AS_ROW=0
for /f "tokens=1,* delims=:" %%A in ('%ROBOCOPY% "!ARCHIVE_DIR!" "%TEMP%\panos_cfg_void_%RUN_TAG%" *.7z /L /S /XJ /NJH /NFL /NDL /NC /BYTES /R:0 /W:0 2^>nul') do (
    set "AS_LINE=%%A"
    if "!AS_LINE:~0,5!"=="-----" set /a AS_SUM=1
    if !AS_SUM! EQU 1 for /f "tokens=1" %%V in ("%%B") do (
        set "AS_V=%%V"
        set "AS_D=!AS_V!x"
        for /f "delims=0123456789" %%X in ("!AS_D!") do if "%%X"=="x" (
            set /a AS_ROW+=1
            if !AS_ROW! EQU 2 set "ARCH_TOTAL_FILES=!AS_V!"
            if !AS_ROW! EQU 3 set "ARCH_TOTAL_SIZE=!AS_V!"
        )
    )
)
if not defined ARCH_TOTAL_SIZE set "ARCH_TOTAL_FILES="
set "AS_OLDEST="
call :ForEachDayDir ArchiveStatsDay
if defined AS_OLDEST (
    call :DaysFromCivil !AS_OLDEST:~0,4! 1!AS_OLDEST:~4,2!-100 1!AS_OLDEST:~6,2!-100 AS_DAYS
    set /a ARCH_OLDEST=AS_DAYS*86400-UTC_OFFSET
)
call :DayFileCount
set "ARCH_STATS=1"
call :Now
set /a AS_SECONDS=NOW_EPOCH-AS_T0
call :Log 98 INFO "Archive statistics computed in !AS_SECONDS! s (archives: !ARCH_TOTAL_FILES!)"
exit /b 0

:ArchiveStatsDay
set "AS_DN=%~nx1"
set "AS_KEY=!AS_DN:~6,4!!AS_DN:~3,2!!AS_DN:~0,2!"
call :IsNumber "!AS_KEY!" AS_OK
if "!AS_OK!"=="1" if exist "%~1\*.7z" (
    if not defined AS_OLDEST (set "AS_OLDEST=!AS_KEY!") else if !AS_KEY! LSS !AS_OLDEST! set "AS_OLDEST=!AS_KEY!"
)
for %%F in ("%~1\*.%FILE_EXT%") do if /i "%%~xF"==".%FILE_EXT%" set /a FILES_ORPHANED+=1
for %%F in ("%~1\*.7z.invalid-*") do set /a ARCH_INVALID+=1
exit /b 0

rem Archives of the last complete day
:DayFileCount
call :Now
set /a DC_DAYS=(NOW_EPOCH+UTC_OFFSET)/86400-DAY_COUNT_LAG_DAYS
set /a DC_HOUR=1!NOW_TIME:~0,2!-100
if !DC_HOUR! LSS %DAY_COMPLETE_HOUR% set /a DC_DAYS-=1
call :CivilFromDays !DC_DAYS! DC_Y DC_M DC_D
set /a DAY_FILES=0
set /a DAY_FILES_DATE=DC_DAYS*86400-UTC_OFFSET
for /d %%M in ("!ARCHIVE_DIR!\!DC_Y!\!DC_M!-!DC_Y!*" "!ARCHIVE_DIR!\!DC_M!-!DC_Y! (*)") do (
    for %%F in ("%%~fM\!DC_D!-!DC_M!-!DC_Y!\*.7z") do if /i "%%~xF"==".7z" set /a DAY_FILES+=1
)
exit /b 0

rem Files still in the source directory, age of the oldest
:ScanPending
set /a FILES_PENDING=0,SOURCE_OLDEST_AGE=0
call :Now
%ROBOCOPY% "%SOURCE_DIR%\." "%TEMP%\panos_cfg_void_%RUN_TAG%" *.%FILE_EXT% /L /LEV:1 /NJH /NJS /NDL /NC /BYTES /TS /FP /R:0 /W:0 >"%LIST_FILE%" 2>nul
for /f "usebackq tokens=1-3*" %%A in ("%LIST_FILE%") do (
    if /i "%%~xD"==".%FILE_EXT%" (
        set /a FILES_PENDING+=1
        call :DateTimeToEpoch "%%B" "%%C" SP_EPOCH
        set /a SP_AGE=NOW_EPOCH-SP_EPOCH
        if !SP_AGE! GTR !SOURCE_OLDEST_AGE! set /a SOURCE_OLDEST_AGE=SP_AGE
    )
)
exit /b 0

rem Volume size from fsutil (second line, any language)
:DiskTotal
set "%~2="
set "DT_LINE="
set /a DT_N=0
if not exist "%FSUTIL%" exit /b 0
for /f "tokens=1,* delims=:" %%A in ('%FSUTIL% volume diskfree "%~1" 2^>nul') do (
    set /a DT_N+=1
    if !DT_N! EQU 2 set "DT_LINE=%%B"
)
if not defined DT_LINE exit /b 0
for /f "tokens=1 delims=(" %%X in ("!DT_LINE!") do set "DT_LINE=%%X"
call :DigitsOnly "!DT_LINE!" DT_VALUE
if defined DT_VALUE if not "!DT_VALUE!"=="0" set "%~2=!DT_VALUE!"
exit /b 0

rem Digits of %1, without leading zeros
:DigitsOnly
setlocal
set "DO_IN=%~1"
set "DO_OUT="
:DigitsOnlyLoop
if not defined DO_IN goto :DigitsOnlyEnd
set "DO_C=!DO_IN:~0,1!"
set "DO_IN=!DO_IN:~1!"
for %%D in (0 1 2 3 4 5 6 7 8 9) do if "!DO_C!"=="%%D" (
    if not "!DO_OUT!!DO_C!"=="0" set "DO_OUT=!DO_OUT!!DO_C!"
)
goto :DigitsOnlyLoop
:DigitsOnlyEnd
endlocal & set "%~2=%DO_OUT%"
exit /b 0

rem 100*%1/%2 with two decimals, numbers of any size
:Percent
setlocal
set "PC_A=%~1"
set "PC_B=%~2"
call :StrLen "!PC_B!" PC_LB
set /a PC_SHIFT=PC_LB-5
if !PC_SHIFT! GTR 0 (
    call :StrLen "!PC_A!" PC_LA
    set "PC_B=!PC_B:~0,5!"
    set /a PC_KEEP=PC_LA-PC_SHIFT
    if !PC_KEEP! LEQ 0 (set "PC_A=0") else for %%K in (!PC_KEEP!) do set "PC_A=!PC_A:~0,%%K!"
)
call :DigitsOnly "!PC_A!" PC_A
call :DigitsOnly "!PC_B!" PC_B
if not defined PC_A set "PC_A=0"
if not defined PC_B (endlocal & set "%~3=" & exit /b 0)
call :StrLen "!PC_A!" PC_LA
if !PC_LA! GTR 5 (endlocal & set "%~3=9999.99" & exit /b 0)
set /a PC_V=PC_A*10000/PC_B
if !PC_V! GTR 999999 set /a PC_V=999999
set /a PC_I=PC_V/100, PC_F=PC_V%%100
set "PC_F=0!PC_F!"
set "PC_R=!PC_I!.!PC_F:~-2!"
endlocal & set "%~3=%PC_R%"
exit /b 0

rem Length of %1 (max 64)
:StrLen
setlocal
set "SL_S=%~1"
set /a SL_N=0
:StrLenLoop
if defined SL_S (
    set "SL_S=!SL_S:~1!"
    set /a SL_N+=1
    if !SL_N! LSS 64 goto :StrLenLoop
)
endlocal & set "%~2=%SL_N%"
exit /b 0

rem %2=1 if %1 contains digits only
:IsNumber
set "%~2=0"
if "%~1"=="" exit /b 0
for /f "delims=0123456789" %%X in ("%~1x") do if "%%X"=="x" set "%~2=1"
exit /b 0

rem Free bytes: last line of dir /-c (any language)
:DiskFree
set "%~2="
set "DF_VALUE="
for /f "tokens=3" %%F in ('dir /-c /a:d "%~1\" 2^>nul') do set "DF_VALUE=%%F"
call :IsNumber "!DF_VALUE!" DF_OK
if "!DF_OK!"=="1" set "%~2=!DF_VALUE!"
exit /b 0

rem ---------------------------------------------------------------------------
rem Time: robocopy shows the local time (errors) and UTC (/TS)
rem UTC offset, rounded to 15 minutes
:ClockInit
set "CLOCK_OK=0"
type nul >"%CLOCK_FILE%" 2>nul
if not exist "%CLOCK_FILE%" exit /b 1
set /a UTC_OFFSET=0
call :Now
if errorlevel 1 exit /b 1
set "CK_LOCAL=!NOW_LOCAL_EPOCH!"
set "CK_UTC="
for %%F in ("%CLOCK_FILE%") do (
    for /f "tokens=1-3*" %%A in ('%ROBOCOPY% "%%~dpF." "%TEMP%\panos_cfg_void_%RUN_TAG%" "%%~nxF" /L /LEV:1 /NJH /NJS /NDL /NC /BYTES /TS /FP /R:0 /W:0 2^>nul') do (
        if /i "%%~nxD"=="%%~nxF" call :DateTimeToEpoch "%%B" "%%C" CK_UTC
    )
)
del /q "%CLOCK_FILE%" >nul 2>&1
if not defined CK_UTC exit /b 1
set /a CK_DIFF=CK_LOCAL-CK_UTC
set /a CK_ROUND=450
if !CK_DIFF! LSS 0 set /a CK_ROUND=-450
set /a "UTC_OFFSET=(CK_DIFF+CK_ROUND)/900*900"
set "CLOCK_OK=1"
exit /b 0

rem NOW_DATE, NOW_TIME, NOW_TS, NOW_EPOCH (UTC)
:Now
set "NOW_DATE="
for /f "tokens=1,2" %%A in ('%ROBOCOPY% "|" . /L /NJH /R:0 /W:0 2^>nul ^| %FINDSTR% /r /b /c:"[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9] "') do (
    if not defined NOW_DATE (
        set "NOW_DATE=%%A"
        set "NOW_TIME=%%B"
    )
)
if not defined NOW_DATE exit /b 1
call :DateTimeToEpoch "!NOW_DATE!" "!NOW_TIME!" NOW_LOCAL_EPOCH
set /a NOW_EPOCH=NOW_LOCAL_EPOCH-UTC_OFFSET
set "NOW_TS=!NOW_DATE:/=-! !NOW_TIME!"
set "LOG_DAY=!NOW_DATE:/=-!"
set "LOG_HOUR=!NOW_TIME:~0,2!"
exit /b 0

rem yyyy/mm/dd hh:mm:ss to seconds since 1970-01-01
:DateTimeToEpoch
setlocal
set "DT=%~1"
set "TM=%~2"
call :DaysFromCivil !DT:~0,4! 1!DT:~5,2!-100 1!DT:~8,2!-100 DT_DAYS
set /a DT_EPOCH=DT_DAYS*86400+(1!TM:~0,2!-100)*3600+(1!TM:~3,2!-100)*60+(1!TM:~6,2!-100)
endlocal & set "%~3=%DT_EPOCH%"
exit /b 0

rem Date to days since 1970-01-01
:DaysFromCivil
setlocal
set /a Y=%~1, M=%~2, D=%~3
set /a Y-=(14-M)/12
set /a ERA=Y/400, YOE=Y-ERA*400, MP=(M+9)%%12
set /a DOY=(153*MP+2)/5+D-1
set /a DOE=YOE*365+YOE/4-YOE/100+DOY
set /a DAYS=ERA*146097+DOE-719468
endlocal & set "%~4=%DAYS%"
exit /b 0

rem Days since 1970-01-01 to date
:CivilFromDays
setlocal
set /a Z=%~1+719468
set /a ERA=Z/146097, DOE=Z-ERA*146097
set /a YOE=(DOE-DOE/1460+DOE/36524-DOE/146096)/365
set /a Y=YOE+ERA*400, DOY=DOE-(365*YOE+YOE/4-YOE/100)
set /a MP=(5*DOY+2)/153
set /a D=DOY-(153*MP+2)/5+1, M=MP+3-12*(MP/10)
set /a Y+=(14-M)/12
set "M=0!M!"
set "D=0!D!"
endlocal & set "%~2=%Y%" & set "%~3=%M:~-2%" & set "%~4=%D:~-2%"
exit /b 0

rem ---------------------------------------------------------------------------
rem BIG_LESS=1 if arg1 is lower than arg2 (no 32-bit limit)
:BigLess
set "BL_A=00000000000000000000%~1"
set "BL_B=00000000000000000000%~2"
set "BIG_LESS=0"
if "x!BL_A:~-20!" LSS "x!BL_B:~-20!" set "BIG_LESS=1"
exit /b 0

rem Adds %2 to variable %1 (up to 18 digits)
:BigAdd
setlocal
set "BA_A=000000000000000000!%~1!"
set "BA_B=000000000000000000%~2"
set "BA_A=!BA_A:~-18!"
set "BA_B=!BA_B:~-18!"
set /a BA_LO=1!BA_A:~9!-1000000000+1!BA_B:~9!-1000000000
set /a BA_HI=1!BA_A:~0,9!-1000000000+1!BA_B:~0,9!-1000000000
if !BA_LO! GEQ 1000000000 set /a BA_LO-=1000000000, BA_HI+=1
if !BA_HI! GTR 0 (
    set "BA_LO=000000000!BA_LO!"
    set "BA_R=!BA_HI!!BA_LO:~-9!"
) else (
    set "BA_R=!BA_LO!"
)
endlocal & set "%~1=%BA_R%"
exit /b 0

rem Wait %1 seconds
:Sleep
set /a SLEEP_COUNT=%~1+1
%PING% -n !SLEEP_COUNT! 127.0.0.1 >nul 2>&1
exit /b 0

rem Month name (MONTH_FOLDER_NAME en or it)
:MonthName
if "%MONTH_FOLDER_NAME%"=="it" (
    set "MN_01=Gennaio"& set "MN_02=Febbraio"& set "MN_03=Marzo"& set "MN_04=Aprile"& set "MN_05=Maggio"& set "MN_06=Giugno"
    set "MN_07=Luglio"& set "MN_08=Agosto"& set "MN_09=Settembre"& set "MN_10=Ottobre"& set "MN_11=Novembre"& set "MN_12=Dicembre"
) else (
    set "MN_01=January"& set "MN_02=February"& set "MN_03=March"& set "MN_04=April"& set "MN_05=May"& set "MN_06=June"
    set "MN_07=July"& set "MN_08=August"& set "MN_09=September"& set "MN_10=October"& set "MN_11=November"& set "MN_12=December"
)
for %%M in (%~1) do set "%~2=!MN_%%M!"
exit /b 0

:Log
if not "!LOG_READY!"=="1" if not "%CONSOLE_OUTPUT%"=="1" exit /b 0
set "LG_T=%TIME%"
set "LG_S="
for /f "tokens=1-3 delims=:., " %%a in ("!LG_T!") do (
    set "LG_H=0%%a"
    set "LG_M=%%b"
    set "LG_S=%%c"
)
set "LG_H=!LG_H:~-2!"
if not defined LG_S (
    call :Now
    set "LOG_TS=!NOW_TS!"
) else (
    if not defined LOG_DAY call :Now
    if "!LG_H!" LSS "!LOG_HOUR!" call :Now
    if not defined LOG_DAY set "LOG_DAY=----------"
    set "LOG_TS=!LOG_DAY! !LG_H!:!LG_M!:!LG_S!"
    set "LOG_HOUR=!LG_H!"
)
set "LG_MSG=%~3"
if "!LOG_READY!"=="1" >>"%LOG_FILE%" echo [!LOG_TS!] %~2 (code %~1^) ^| !LG_MSG!
if "%CONSOLE_OUTPUT%"=="1" echo [!LOG_TS!] %~2 (code %~1^) ^| !LG_MSG!
exit /b 0

rem Screen messages in English (default) or Italian
:LangLoad
if /i not "%LANGUAGE%"=="it" set "LANGUAGE=en"
if /i "%LANGUAGE%"=="it" goto :LangIt
set "L_ERRCFG=Configuration error:"
set "L_SEEDOC=See README.md, section Configuration."
set "L_E_01=must be 0 or 1"
set "L_E_LOGDIR=LOG_DIR is empty (or set LOG_DIR_FALLBACK=1)"
set "L_E_PH=still contains its placeholder"
set "L_E_INVALID=invalid value:"
set "L_E_MONTH=MONTH_FOLDER_NAME must be none, en or it"
set "L_E_IDLEN=INSTANCE_ID longer than 64 characters"
set "L_E_IDCHR=INSTANCE_ID: lowercase letters, digits, _ and - only"
set "L_E_EXT=FILE_EXT or /ext: letters and digits only (max 10):"
set "L_E_CHARS=a path, argument or program path contains an unsupported character:"
set "L_H_INSTANCE=Instance"
set "L_H_SOURCE=Source  "
set "L_H_LOGDIR=Log dir "
set "L_H_ARCHIVE=Archive "
set "L_NOTSTARTED=NOT STARTED (another run is active)"
set "L_R_RESULT=Result     "
set "L_R_FILES=Files      "
set "L_R_DATA=Data       "
set "L_R_DUR=Duration   "
set "L_R_ERR=Last error "
set "L_R_ZBX=Zabbix     "
set "L_R_LOG=Log file   "
set "L_F_FOUND=found"
set "L_F_ARCH=archived"
set "L_F_FAIL=failed"
set "L_F_DEF=deferred"
set "L_F_REC=recovered"
set "L_F_PEND=pending"
set "L_D_BYTES=bytes archived, compression ratio"
set "L_Z_NOTSENT=metrics NOT sent, see the log"
set "L_Z_SENT=metrics sent"
set "L_Z_NOSENDER=metrics not sent, zabbix_sender not found"
set "L_Z_DISABLED=disabled (ZABBIX_ENABLED=0)"
exit /b 0
:LangIt
set "L_ERRCFG=Errore di configurazione:"
set "L_SEEDOC=Vedi README.it.md, sezione Configurazione."
set "L_E_01=deve valere 0 o 1"
set "L_E_LOGDIR=LOG_DIR e' vuota (oppure imposta LOG_DIR_FALLBACK=1)"
set "L_E_PH=contiene ancora il segnaposto"
set "L_E_INVALID=valore non valido:"
set "L_E_MONTH=MONTH_FOLDER_NAME deve valere none, en o it"
set "L_E_IDLEN=INSTANCE_ID piu' lungo di 64 caratteri"
set "L_E_IDCHR=INSTANCE_ID: solo lettere minuscole, cifre, _ e -"
set "L_E_EXT=FILE_EXT o /ext: solo lettere e cifre (max 10):"
set "L_E_CHARS=un percorso, un argomento o il percorso di un programma contiene un carattere non supportato:"
set "L_H_INSTANCE=Istanza "
set "L_H_SOURCE=Sorgente"
set "L_H_LOGDIR=Log     "
set "L_H_ARCHIVE=Archivio"
set "L_NOTSTARTED=NON AVVIATO (altra esecuzione in corso)"
set "L_R_RESULT=Esito      "
set "L_R_FILES=File       "
set "L_R_DATA=Dati       "
set "L_R_DUR=Durata     "
set "L_R_ERR=Ult. errore"
set "L_R_ZBX=Zabbix     "
set "L_R_LOG=File di log"
set "L_F_FOUND=trovati"
set "L_F_ARCH=archiviati"
set "L_F_FAIL=falliti"
set "L_F_DEF=rimandati"
set "L_F_REC=recuperati"
set "L_F_PEND=in attesa"
set "L_D_BYTES=byte archiviati, rapporto di compressione"
set "L_Z_NOTSENT=metriche NON inviate, vedi il log"
set "L_Z_SENT=metriche inviate"
set "L_Z_NOSENDER=metriche non inviate, zabbix_sender non trovato"
set "L_Z_DISABLED=disattivato (ZABBIX_ENABLED=0)"
exit /b 0

rem Console only
:Debug
set "DBG_MSG=%~1"
echo   [debug] !DBG_MSG!
exit /b 0

rem Message on stderr for early exits
:ConfigError
>&2 echo(
>&2 echo [PAN-OS Config Archiver] !L_ERRCFG! %~1
>&2 echo(
>&2 echo !L_SEEDOC!
>&2 echo(
exit /b 0

:Usage
echo(
echo PAN-OS Config Archiver %SCRIPT_VERSION% - %SCRIPT_AUTHOR% - %SCRIPT_URL%
echo(
if /i "%LANGUAGE%"=="it" goto :UsageIt
echo Usage: %SCRIPT_NAME% "SOURCE_DIRECTORY" "INSTANCE_ID" [/ext EXT] [/archive "FOLDER"] [/console or /debug]
echo(
echo   /ext      extension of the files to archive (default: %FILE_EXT%)
echo   /archive  archive folder on the same volume (default: the source folder)
echo   /console  show progress on screen (same as CONSOLE_OUTPUT=1)
echo   /debug    also show 7-Zip and zabbix_sender output (DEBUG_OUTPUT=1)
echo(
echo Example: %SCRIPT_NAME% "D:\FTP\PANORAMA-CONFIG" "panorama-config" /console
echo(
exit /b 0
:UsageIt
echo Uso: %SCRIPT_NAME% "CARTELLA_SORGENTE" "ID_ISTANZA" [/ext EST] [/archive "CARTELLA"] [/console o /debug]
echo(
echo   /ext      estensione dei file da archiviare (default: %FILE_EXT%)
echo   /archive  cartella archivio sullo stesso volume (default: la cartella sorgente)
echo   /console  mostra l'avanzamento a schermo (come CONSOLE_OUTPUT=1)
echo   /debug    mostra anche l'output di 7-Zip e zabbix_sender (DEBUG_OUTPUT=1)
echo(
echo Esempio: %SCRIPT_NAME% "D:\FTP\PANORAMA-CONFIG" "panorama-config" /console
echo(
exit /b 0

:Summary
set "SU_TEXT=FAILED"
if not defined COMPRESSION_RATIO set "COMPRESSION_RATIO=-"
if !JOB_STATUS! EQU 1 set "SU_TEXT=SUCCESS"
if !JOB_STATUS! EQU 2 set "SU_TEXT=PARTIAL"
if "!JOB_EXIT!"=="20" set "SU_TEXT=!L_NOTSTARTED!"
echo(
echo ------------------------------------------------------------
echo  !L_R_RESULT! : !SU_TEXT! - exit code !JOB_EXIT!
echo(
echo  !L_R_FILES! : !L_F_FOUND! !FILES_FOUND!, !L_F_ARCH! !FILES_PROCESSED!, !L_F_FAIL! !FILES_FAILED!, !L_F_DEF! !FILES_DEFERRED!, !L_F_REC! !FILES_RECOVERED!, !L_F_PEND! !FILES_PENDING!
echo  !L_R_DATA! : !BYTES_PROCESSED! !L_D_BYTES! !COMPRESSION_RATIO!%%
echo  !L_R_DUR! : !JOB_DURATION! s
echo(
echo  !L_R_ERR! : !LAST_ERROR!
set "SU_ZBX=!L_Z_NOTSENT!"
if "!SENDER_NOW!"=="1" set "SU_ZBX=!L_Z_SENT!"
if not "!SEND_ACTIVE!"=="1" set "SU_ZBX=!L_Z_NOSENDER!"
if not "%ZABBIX_ENABLED%"=="1" set "SU_ZBX=!L_Z_DISABLED!"
echo  !L_R_ZBX! : !SU_ZBX!
if "!LOG_READY!"=="1" echo  !L_R_LOG! : !LOG_FILE!
echo ------------------------------------------------------------
echo(
exit /b 0
