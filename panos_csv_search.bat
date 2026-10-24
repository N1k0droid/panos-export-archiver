@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ===========================================================================
rem  PAN-OS CSV Search - search in the archived Palo Alto CSV logs
rem  Version : 1.0.0
rem  Author  : N1k0droid - https://github.com/N1k0droid
rem  Usage   : double click (guided), drag a log folder on the file, or
rem            panos_csv_search.bat "FOLDER" /from DD-MM-YYYY /src IP ...
rem  Docs    : README.md (English), README.it.md (Italiano)
rem ===========================================================================
set "SCRIPT_VERSION=1.0.0"
set "SCRIPT_AUTHOR=N1k0droid"
set "SCRIPT_URL=https://github.com/N1k0droid"
set "SCRIPT_NAME=%~nx0"

rem === Configuration ===

rem ###########################################################################
rem  SCREEN, 7-ZIP AND RESULTS
rem ###########################################################################

rem Language of the screen messages: en or it (also /lang en or /lang it)
if not defined LANGUAGE set "LANGUAGE=en"

set "SEVENZIP_PATH=C:\Program Files\7-Zip\7z.exe"

rem Folder of the result files
set "OUTPUT_DIR=%~dp0results"

rem ###########################################################################
rem  CSV COLUMNS
rem ###########################################################################

rem Column names of the CSV header, and positions used when they are missing
set "COL_SRC_NAME=Source address"
set "COL_DST_NAME=Destination address"
set "COL_SUSER_NAME=Source User"
set "COL_DUSER_NAME=Destination User"
set "COL_SRC=8"
set "COL_DST=9"
set "COL_SUSER=13"
set "COL_DUSER=14"

rem ###########################################################################
rem  END OF CONFIGURATION - nothing to edit below this line
rem ###########################################################################

rem === Regular expression pieces (lines without "!" keep the caret) ===
set "CARET=^"
set "RX_SKIP=[^,]*,"
set "RX_FIELD=[^,]*"
set "RX_TEXT=.*"
set "FINDSTR=%SystemRoot%\System32\findstr.exe"
set "ROBOCOPY=%SystemRoot%\System32\robocopy.exe"
set "FIND=%SystemRoot%\System32\find.exe"

rem === Arguments (parsed without delayed expansion: values may contain !) ===
set "P_DIR="
set "P_FROM="
set "P_TO="
set "Q_SRC="
set "Q_DST="
set "Q_IP="
set "Q_USER="
set "Q_TEXT="
set "P_OUT="
set "P_UNARCH=0"
set "P_YES=0"
set "BATCH=0"
set "DEBUG_OUTPUT=0"
:ArgLoop
if "%~1"=="" goto :ArgsDone
set "ARG=%~1"
if /i "%ARG%"=="/?" goto :ArgHelp
if /i "%ARG%"=="/help" goto :ArgHelp
if /i "%ARG%"=="/from" goto :ArgFrom
if /i "%ARG%"=="/to" goto :ArgTo
if /i "%ARG%"=="/src" goto :ArgSrc
if /i "%ARG%"=="/dst" goto :ArgDst
if /i "%ARG%"=="/ip" goto :ArgIp
if /i "%ARG%"=="/user" goto :ArgUser
if /i "%ARG%"=="/text" goto :ArgText
if /i "%ARG%"=="/out" goto :ArgOut
if /i "%ARG%"=="/lang" goto :ArgLang
if /i "%ARG%"=="/unarchived" ( set "P_UNARCH=1" & shift & goto :ArgLoop )
if /i "%ARG%"=="/yes" ( set "P_YES=1" & shift & goto :ArgLoop )
if /i "%ARG%"=="/debug" ( set "DEBUG_OUTPUT=1" & shift & goto :ArgLoop )
if "%ARG:~0,1%"=="/" goto :ArgUnknown
set "P_DIR=%~1"
shift
goto :ArgLoop
:ArgFrom
set "P_FROM=%~2"
shift & shift & goto :ArgLoop
:ArgTo
set "P_TO=%~2"
shift & shift & goto :ArgLoop
:ArgSrc
set "Q_SRC=%~2"
set "BATCH=1"
shift & shift & goto :ArgLoop
:ArgDst
set "Q_DST=%~2"
set "BATCH=1"
shift & shift & goto :ArgLoop
:ArgIp
set "Q_IP=%~2"
set "BATCH=1"
shift & shift & goto :ArgLoop
:ArgUser
set "Q_USER=%~2"
set "BATCH=1"
shift & shift & goto :ArgLoop
:ArgText
set "Q_TEXT=%~2"
set "BATCH=1"
shift & shift & goto :ArgLoop
:ArgOut
set "P_OUT=%~2"
shift & shift & goto :ArgLoop
:ArgLang
set "LANGUAGE=%~2"
shift & shift & goto :ArgLoop
:ArgUnknown
call :LangLoad
echo(
echo  %L_UNKNOWN% %ARG%
call :Usage
exit /b 10
:ArgHelp
call :LangLoad
call :Banner
call :Usage
exit /b 0
:ArgsDone
call :LangLoad

rem Backspace character: keeps the indentation of set /p prompts
for /f %%a in ('"prompt $H & for %%b in (1) do rem"') do set "BS=%%a"
setlocal EnableDelayedExpansion
set "WORK=%TEMP%\panos_csv_search_%RANDOM%%RANDOM%"
set /a EXIT_CODE=0
call :Banner

rem === Prerequisites ===
if not exist "%SEVENZIP_PATH%" (
    echo  !L_ERROR! !L_NO7Z! %SEVENZIP_PATH%
    echo  !L_FIX7Z!
    set /a EXIT_CODE=14
    goto :Finish
)
call :Now
if errorlevel 1 (
    echo  !L_ERROR! !L_NOCLOCK!
    set /a EXIT_CODE=14
    goto :Finish
)
set "START_EPOCH=!NOW_EPOCH!"
call :DaysFromCivil !NOW_DATE:~0,4! 1!NOW_DATE:~5,2!-100 1!NOW_DATE:~8,2!-100 TODAY_DAYS
set /a YDAYS=TODAY_DAYS-1
call :DayText !YDAYS! DEF_DAY
set "STAMP=!NOW_DATE:/=!_!NOW_TIME::=!"

if "!BATCH!"=="1" goto :CheckInput

rem === Guided input ===
:AskDir
if not defined P_DIR (
    echo  !L_ASKDIR! D:\FTP\FW01-TRAFFIC
    set /p "P_DIR=!BS!  !L_P_DIR! : "
    echo(
)
call :UnsafeChars P_DIR
if defined UNSAFE (
    echo  !L_ERROR! !L_E_CHARS!
    echo(
    set "P_DIR="
    goto :AskDir
)
call :CleanDir
if not defined P_DIR goto :AskDir
if not exist "!P_DIR!\" (
    echo  !L_DIRNF! !P_DIR!
    echo(
    set "P_DIR="
    goto :AskDir
)
echo  !L_FOLDER! : !P_DIR!
echo(

:AskPeriod
echo  !L_PERIOD_HELP!
set "P_FROM="
set /p "P_FROM=!BS!  !L_P_FROM! [!DEF_DAY!] : "
if not defined P_FROM set "P_FROM=!DEF_DAY!"
call :ParseRange
if not defined FROM_KEY (
    echo  !L_BADDATE! !P_FROM!
    echo(
    goto :AskPeriod
)
if "!FROM_KEY!"=="00000000" goto :AskPeriodDone
set "P_TO="
set /p "P_TO=!BS!  !L_P_TO! [!P_FROM!] : "
if not defined P_TO set "P_TO=!P_FROM!"
call :ParseRange
if not defined TO_KEY (
    echo  !L_BADEND! !P_TO!
    echo(
    goto :AskPeriod
)
:AskPeriodDone
echo(

:AskWhat
echo  !L_WHAT!
echo    !L_WHAT1!
echo    !L_WHAT2!
echo    !L_WHAT3!
echo(
set "Q_SRC="
set "Q_DST="
set "Q_IP="
set "Q_USER="
set "Q_TEXT="
set /p "Q_SRC=!BS!  !L_P_SRC! : "
set /p "Q_DST=!BS!  !L_P_DST! : "
set /p "Q_IP=!BS!  !L_P_IP! : "
set /p "Q_USER=!BS!  !L_P_USER! : "
set /p "Q_TEXT=!BS!  !L_P_TEXT! : "
echo(
if not defined Q_SRC if not defined Q_DST if not defined Q_IP if not defined Q_USER if not defined Q_TEXT (
    echo  !L_FILLONE!
    echo(
    goto :AskWhat
)

set "ANS="
set /p "ANS=!BS!  !L_P_UNARCH! : "
if /i "!ANS!"=="s" set "P_UNARCH=1"
if /i "!ANS!"=="y" set "P_UNARCH=1"
set "P_OUT="
set /p "P_OUT=!BS!  !L_P_OUT! [search_!STAMP!] : "
echo(
goto :CheckInput

rem === Validation (guided and command line) ===
:CheckInput
call :UnsafeChars P_DIR
if not defined UNSAFE call :UnsafeChars OUTPUT_DIR
if defined UNSAFE ( call :InputError "!L_E_CHARS!" & goto :Finish )
call :CleanDir
if not defined P_DIR ( call :InputError "!L_E_NODIR!" & goto :Finish )
if not exist "!P_DIR!\" ( call :InputError "!L_E_DIRNF! !P_DIR!" & goto :Finish )
if not defined P_FROM set "P_FROM=!DEF_DAY!"
call :ParseRange
if not defined FROM_KEY ( call :InputError "!L_E_FROM! !P_FROM!" & goto :Finish )
if not defined TO_KEY ( call :InputError "!L_E_TO! !P_TO!" & goto :Finish )
if not defined Q_SRC if not defined Q_DST if not defined Q_IP if not defined Q_USER if not defined Q_TEXT ( call :InputError "!L_E_NOCRIT!" & goto :Finish )
if not defined P_OUT set "P_OUT=search_!STAMP!"
set "P_OUT=!P_OUT:"=!"
if /i "!P_OUT:~-4!"==".csv" set "P_OUT=!P_OUT:~0,-4!"
call :CheckName
if not defined NAME_OK ( call :InputError "!L_E_NAME! !P_OUT!" & goto :Finish )
if not exist "%OUTPUT_DIR%\" mkdir "%OUTPUT_DIR%" >nul 2>&1
if not exist "%OUTPUT_DIR%\" ( call :InputError "!L_E_OUTDIR! %OUTPUT_DIR%" & goto :Finish )
set "OUT_FILE=%OUTPUT_DIR%\!P_OUT!.csv"
set "SUM_FILE=%OUTPUT_DIR%\!P_OUT!!L_SUMSUFFIX!.txt"
if exist "!OUT_FILE!" (
    set "P_OUT=!P_OUT!_!STAMP!"
    set "OUT_FILE=%OUTPUT_DIR%\!P_OUT!.csv"
    set "SUM_FILE=%OUTPUT_DIR%\!P_OUT!!L_SUMSUFFIX!.txt"
)

rem === Archives in the period and CSV header ===
mkdir "!WORK!" >nul 2>&1
set /a TOTAL_FILES=0, TOTAL_DAYS=0
set "FIRST_ARCHIVE="
call :ForEachDay CountDay
if "!P_UNARCH!"=="1" call :ForEachRootCsv CountRoot
if !TOTAL_FILES! EQU 0 (
    echo  !L_NOARCH! !FROM_TEXT! - !TO_TEXT!.
    echo(
    set /a EXIT_CODE=1
    goto :Finish
)
set "HDR="
if defined FIRST_ARCHIVE call :ReadHeader "!FIRST_ARCHIVE!"
call :FindColumns
call :BuildPipe

echo  !L_SEARCH!
echo    !L_S_FOLDER! : !P_DIR!
echo    !L_S_PERIOD! : !FROM_TEXT! - !TO_TEXT!   (!L_DAYS! !TOTAL_DAYS!, !L_FILES! !TOTAL_FILES!)
if defined Q_SRC  echo    !L_S_SRC! : !Q_SRC!
if defined Q_DST  echo    !L_S_DST! : !Q_DST!
if defined Q_IP   echo    !L_S_IP! : !Q_IP!
if defined Q_USER echo    !L_S_USER! : !Q_USER!
if defined Q_TEXT echo    !L_S_TEXT! : !Q_TEXT!
if "!P_UNARCH!"=="1" echo    !L_S_INCL! : !L_UNARCH_INC!
echo    !L_S_RESULTS! : !OUT_FILE!
if not defined HDR_FOUND echo    !L_WARN_COLS!
echo(
if "!DEBUG_OUTPUT!"=="1" call :DebugPipe
if "!BATCH!"=="1" goto :Run
if "!P_YES!"=="1" goto :Run
set "ANS="
set /p "ANS=!BS!  !L_P_START! : "
if /i "!ANS!"=="n" (
    echo  !L_CANCEL!
    set /a EXIT_CODE=10
    goto :Finish
)
echo(

rem === Search ===
:Run
set "MATCHF=!WORK!\match.txt"
set "ERRF=!WORK!\err.txt"
set "FILESF=!WORK!\files.txt"
set "BADF=!WORK!\bad.txt"
type nul >"!FILESF!"
type nul >"!BADF!"
if defined HDR (
    >"!OUT_FILE!" echo(!L_COL_DAY!,File,!HDR!
) else (
    >"!OUT_FILE!" echo(!L_COL_DAY!,File,!L_COL_LINE!
)
set /a DONE=0, TOTAL_LINES=0, MATCH_FILES=0, BAD_FILES=0
echo  !L_TABLE!
call :ForEachDay SearchDay
if "!P_UNARCH!"=="1" call :ForEachRootCsv SearchRoot
title PAN-OS CSV Search - !L_TITLE_DONE!
call :Now
set /a DURATION=NOW_EPOCH-START_EPOCH
if !BAD_FILES! GTR 0 (set /a EXIT_CODE=2) else if !TOTAL_LINES! EQU 0 (set /a EXIT_CODE=1) else set /a EXIT_CODE=0
call :WriteSummary
call :Summary
goto :Finish

:Finish
if exist "!WORK!\" rmdir /s /q "!WORK!" >nul 2>&1
if not "!BATCH!"=="1" (
    echo(
    pause
)
endlocal & endlocal & exit /b %EXIT_CODE%

rem ---------------------------------------------------------------------------
rem Day folders in the period: YYYY\MM-YYYY*\DD-MM-YYYY and pre-2.3 layout
:ForEachDay
for /d %%Y in ("!P_DIR!\????") do (
    for /d %%M in ("%%~fY\??-????*") do (
        for /d %%D in ("%%~fM\??-??-????") do call :DayInRange "%%~fD" %1
    )
)
for /d %%M in ("!P_DIR!\??-???? (*)") do (
    for /d %%D in ("%%~fM\??-??-????") do call :DayInRange "%%~fD" %1
)
exit /b 0

:DayInRange
set "DR_NAME=%~nx1"
set "DR_KEY=!DR_NAME:~6,4!!DR_NAME:~3,2!!DR_NAME:~0,2!"
call :IsNumber "!DR_KEY!" DR_OK
if not "!DR_OK!"=="1" exit /b 0
if !DR_KEY! LSS !FROM_KEY! exit /b 0
if !DR_KEY! GTR !TO_KEY! exit /b 0
call :%~2 "%~1" "!DR_NAME!"
exit /b 0

rem Archives (and CSV files with /unarchived) of one day, counted
:CountDay
set /a CD_N=0
for %%A in ("%~1\*.7z") do if /i "%%~xA"==".7z" (
    set /a CD_N+=1
    if not defined FIRST_ARCHIVE set "FIRST_ARCHIVE=%%~fA"
)
if "!P_UNARCH!"=="1" for %%A in ("%~1\*.csv") do if /i "%%~xA"==".csv" set /a CD_N+=1
if !CD_N! GTR 0 set /a TOTAL_FILES+=CD_N, TOTAL_DAYS+=1
exit /b 0

rem Search in the files of one day
:SearchDay
set /a SD_FILES=0, SD_LINES=0
for %%A in ("%~1\*.7z") do if /i "%%~xA"==".7z" call :SearchFile "%%~fA" "%~2" 7z
if "!P_UNARCH!"=="1" for %%A in ("%~1\*.csv") do if /i "%%~xA"==".csv" call :SearchFile "%%~fA" "%~2" csv
if !SD_FILES! GTR 0 (
    set "SD_F=      !SD_FILES!"
    set "SD_L=          !SD_LINES!"
    echo  %~2   !SD_F:~-6!   !SD_L:~-10!
)
exit /b 0

rem CSV files not archived yet in the source directory (date from the name)
:ForEachRootCsv
for %%F in ("!P_DIR!\*.csv") do if /i "%%~xF"==".csv" call :RootInRange "%%~fF" %1
exit /b 0

:RootInRange
call :NameDay "%~n1"
if defined ND_KEY (
    if !ND_KEY! LSS !FROM_KEY! exit /b 0
    if !ND_KEY! GTR !TO_KEY! exit /b 0
)
call :%~2 "%~1" "!ND_TEXT!"
exit /b 0

:CountRoot
set /a TOTAL_FILES+=1
exit /b 0

:SearchRoot
set /a SD_FILES=0, SD_LINES=0
call :SearchFile "%~1" "%~2" csv
if !SD_LINES! GTR 0 echo  %~2   !L_NOT_ARCH!   !SD_LINES!
exit /b 0

rem ---------------------------------------------------------------------------
rem %1 file, %2 day, %3 7z or csv: one pass, matches appended with day and file
:SearchFile
set /a DONE+=1, SD_FILES+=1
title PAN-OS CSV Search - file !DONE! !L_OF! !TOTAL_FILES! - %~2
if /i "%~3"=="csv" goto :SearchFileCsv
"%SEVENZIP_PATH%" e -so -bso0 -bsp0 "%~1" 2>"%ERRF%" %PIPE% >"%MATCHF%"
goto :SearchFileCheck
:SearchFileCsv
type "%~1" 2>"%ERRF%" %PIPE% >"%MATCHF%"
:SearchFileCheck
for %%E in ("%ERRF%") do if %%~zE GTR 0 (
    set /a BAD_FILES+=1
    >>"%BADF%" echo(%~2  %~nx1
    echo  %~2   !L_BAD! %~nx1
)
for %%M in ("%MATCHF%") do if %%~zM EQU 0 exit /b 0
if defined USER_LIST (
    call :UserFilter
    for %%M in ("%MATCHF%") do if %%~zM EQU 0 exit /b 0
)
set "SF_N=0"
for /f %%C in ('type "%MATCHF%" ^| %FIND% /c /v ""') do set "SF_N=%%C"
set /a SD_LINES+=SF_N, TOTAL_LINES+=SF_N, MATCH_FILES+=1
>>"%FILESF%" echo(%~2  %~nx1  !SF_N!
call :AppendMatches "%~2" "%~nx1"
exit /b 0

rem User criterion, second step: the value must be in the user columns.
rem (findstr cannot skip 12 or more columns: its expressions are limited)
:UserFilter
type nul >"%MATCHF%.user"
setlocal DisableDelayedExpansion
for /f "usebackq delims=" %%L in ("%MATCHF%") do (
    set "UF_LINE=%%L"
    call :UserLine
)
endlocal
move /y "%MATCHF%.user" "%MATCHF%" >nul 2>&1
exit /b 0

:UserLine
setlocal EnableDelayedExpansion
set "UL=!UF_LINE:"=!"
set "UL=!UL:,,=, ,!"
set "UL=!UL:,,=, ,!"
set "UL_S="
set "UL_D="
for /f "tokens=%COL_SUSER%,%COL_DUSER% delims=," %%a in ("!UL!") do (
    set "UL_S=%%a"
    set "UL_D=%%b"
)
set "UL_HIT="
for %%v in (!USER_LIST!) do (
    if defined UL_S if /i not "!UL_S:%%v=!"=="!UL_S!" set "UL_HIT=1"
    if defined UL_D if /i not "!UL_D:%%v=!"=="!UL_D!" set "UL_HIT=1"
)
if defined UL_HIT >>"%MATCHF%.user" echo(!UF_LINE!
endlocal
exit /b 0

:AppendMatches
setlocal DisableDelayedExpansion
>>"%OUT_FILE%" (
    for /f "usebackq delims=" %%L in ("%MATCHF%") do echo %~1,%~2,%%L
)
endlocal
exit /b 0

rem ---------------------------------------------------------------------------
rem First line of the first archive: header used for column positions
:ReadHeader
"%SEVENZIP_PATH%" e -so -bso0 -bsp0 "%~1" 2>nul | %FINDSTR% /r /n "." | %FINDSTR% /b /c:"1:" >"%WORK%\hdr_raw.txt"
set "HDR_RAW="
set /p HDR_RAW=<"%WORK%\hdr_raw.txt"
if defined HDR_RAW set "HDR=!HDR_RAW:~2!"
exit /b 0

rem Column numbers of source/destination address and user from the header
:FindColumns
set "HDR_FOUND="
if not defined HDR exit /b 0
>"%WORK%\header.txt" echo(!HDR!
set "FC_REST=!HDR!"
set /a FC_COL=0, FC_HITS=0
:FindColumnsLoop
if not defined FC_REST goto :FindColumnsEnd
set "FC_NAME="
for /f "tokens=1* delims=," %%a in ("!FC_REST!") do (
    set "FC_NAME=%%a"
    set "FC_REST=%%b"
)
if not defined FC_NAME goto :FindColumnsEnd
set /a FC_COL+=1
if /i "!FC_NAME!"=="%COL_SRC_NAME%" set "COL_SRC=!FC_COL!" & set /a FC_HITS+=1
if /i "!FC_NAME!"=="%COL_DST_NAME%" set "COL_DST=!FC_COL!" & set /a FC_HITS+=1
if /i "!FC_NAME!"=="%COL_SUSER_NAME%" set "COL_SUSER=!FC_COL!" & set /a FC_HITS+=1
if /i "!FC_NAME!"=="%COL_DUSER_NAME%" set "COL_DUSER=!FC_COL!" & set /a FC_HITS+=1
goto :FindColumnsLoop
:FindColumnsEnd
if !FC_HITS! GEQ 4 set "HDR_FOUND=1"
exit /b 0

rem ---------------------------------------------------------------------------
rem Filter chain: one findstr per criterion (AND), values of a criterion (OR)
:BuildPipe
set "PIPE="
set "USER_LIST="
set "PF_TYPE="
set "PF_BAD="
set "PF_FILE=%WORK%\prefilter.txt"
set /a STAGE_N=0
for %%Q in (SRC DST IP USER TEXT) do if defined Q_%%Q call :BuildStage %%Q
if defined HDR if defined Q_USER call :AddHeaderStage
if defined HDR if defined Q_TEXT call :AddHeaderStage
rem Fast literal pre-filter on the IP values: the column check runs on few lines
if defined PF_TYPE if not defined PF_BAD set "PIPE= | %FINDSTR% /l /i /g:"!PF_FILE!"!PIPE!"
exit /b 0

:AddHeaderStage
if defined HEADER_STAGE exit /b 0
set "HEADER_STAGE=1"
set "PIPE=!PIPE! | %FINDSTR% /v /x /l /g:"%WORK%\header.txt""
exit /b 0

:BuildStage
set "BS_TYPE=%~1"
set "BS_LIST=!Q_%~1!"
set /a STAGE_N+=1
set "BS_FILE=%WORK%\stage!STAGE_N!.txt"
type nul >"!BS_FILE!"
set "BS_WILD=!RX_FIELD!"
if "!BS_TYPE!"=="TEXT" set "BS_WILD=!RX_TEXT!"
if "!BS_TYPE!"=="USER" set "BS_WILD=!RX_TEXT!"
set "BS_PLAIN="
call :SkipColumns !COL_SRC! SK_SRC
call :SkipColumns !COL_DST! SK_DST
set "BS_TOK="
set "BS_LIT="
set "BS_LITSTOP="
if not defined PF_TYPE for %%t in (SRC DST IP) do if "!BS_TYPE!"=="%%t" (
    set "PF_TYPE=%%t"
    type nul >"!PF_FILE!"
)
:BuildStageLoop
if not defined BS_LIST goto :BuildStageDone
set "BS_C=!BS_LIST:~0,1!"
set "BS_LIST=!BS_LIST:~1!"
if "!BS_C!"==" " (
    call :EmitToken
    goto :BuildStageLoop
)
if "!BS_C!"=="*" (
    set "BS_LITSTOP=1"
    set "BS_TOK=!BS_TOK!!BS_WILD!"
    goto :BuildStageLoop
)
if not "!BS_C!"=="?" if not "!BS_C!"=="=" set "BS_PLAIN=!BS_PLAIN!!BS_C!"
if not defined BS_LITSTOP set "BS_LIT=!BS_LIT!!BS_C!"
if "!BS_C!"=="\" set "BS_C=\\"
if "!BS_C!"=="." set "BS_C=\."
if "!BS_C!"=="[" set "BS_C=\["
if "!BS_C!"=="]" set "BS_C=\]"
if "!BS_C!"=="$" set "BS_C=\$"
if "!BS_C!"=="!CARET!" set "BS_C=\!CARET!"
set "BS_TOK=!BS_TOK!!BS_C!"
goto :BuildStageLoop
:BuildStageDone
call :EmitToken
set "BS_FLAGS=/r"
if "!BS_TYPE!"=="USER" set "BS_FLAGS=/r /i"
if "!BS_TYPE!"=="TEXT" set "BS_FLAGS=/r /i"
set "PIPE=!PIPE! | %FINDSTR% !BS_FLAGS! /g:"!BS_FILE!""
exit /b 0

rem One value of the list as regular expression lines of the stage file
:EmitToken
if not defined BS_TOK exit /b 0
set "ET_V=!BS_TOK!"
set "BS_TOK="
if "!BS_TYPE!"=="USER" if defined BS_PLAIN set "USER_LIST=!USER_LIST! !BS_PLAIN!"
set "BS_PLAIN="
if "!BS_TYPE!"=="!PF_TYPE!" (
    if defined BS_LIT (
        >>"!PF_FILE!" echo(!BS_LIT!
    ) else (
        set "PF_BAD=1"
    )
)
set "BS_LIT="
set "BS_LITSTOP="
if "!BS_TYPE!"=="SRC" (
    >>"!BS_FILE!" echo(!CARET!!SK_SRC!"*!ET_V!"*,
)
if "!BS_TYPE!"=="DST" (
    >>"!BS_FILE!" echo(!CARET!!SK_DST!"*!ET_V!"*,
)
if "!BS_TYPE!"=="IP" (
    >>"!BS_FILE!" echo(!CARET!!SK_SRC!"*!ET_V!"*,
    >>"!BS_FILE!" echo(!CARET!!SK_DST!"*!ET_V!"*,
)
if "!BS_TYPE!"=="USER" (
    >>"!BS_FILE!" echo(!ET_V!
)
if "!BS_TYPE!"=="TEXT" (
    >>"!BS_FILE!" echo(!ET_V!
)
exit /b 0

rem %1 column number, %2 result: regex skipping the columns before it
:SkipColumns
set "SC_R="
set /a SC_N=%~1-1
for /l %%i in (1,1,!SC_N!) do set "SC_R=!SC_R!!RX_SKIP!"
set "%~2=!SC_R!"
exit /b 0

:DebugPipe
echo  [debug] columns: source !COL_SRC!, destination !COL_DST!, user !COL_SUSER!/!COL_DUSER!
echo  [debug] filter :!PIPE!
for %%S in ("!WORK!\stage*.txt") do (
    echo  [debug] %%~nxS:
    type "%%~fS"
)
echo(
exit /b 0

rem ---------------------------------------------------------------------------
rem P_FROM/P_TO -> FROM_KEY/TO_KEY (YYYYMMDD) and texts; "*" = whole archive
:ParseRange
set "FROM_KEY="
set "TO_KEY="
if "!P_FROM!"=="*" (
    set "FROM_KEY=00000000"
    set "TO_KEY=99999999"
    set "FROM_TEXT=!L_BEGIN!"
    set "TO_TEXT=!L_END!"
    exit /b 0
)
call :ParseDate "!P_FROM!" FROM_KEY FROM_TEXT
if not defined FROM_KEY exit /b 0
if not defined P_TO set "P_TO=!P_FROM!"
call :ParseDate "!P_TO!" TO_KEY TO_TEXT
if defined TO_KEY if !TO_KEY! LSS !FROM_KEY! set "TO_KEY="
exit /b 0

rem %1 date (dd-mm-yyyy, dd/mm/yyyy or dd.mm.yyyy), %2 key YYYYMMDD, %3 text
:ParseDate
set "%~2="
set "PD_S=%~1"
set "PD_S=!PD_S:/=-!"
set "PD_S=!PD_S:.=-!"
set "PD_D="
set "PD_M="
set "PD_Y="
for /f "tokens=1-3 delims=-" %%a in ("!PD_S!") do (
    set "PD_D=00%%a"
    set "PD_M=00%%b"
    set "PD_Y=%%c"
)
if not defined PD_Y exit /b 0
set "PD_D=!PD_D:~-2!"
set "PD_M=!PD_M:~-2!"
call :IsNumber "!PD_Y!!PD_M!!PD_D!" PD_OK
if not "!PD_OK!"=="1" exit /b 0
if not "!PD_Y:~3,1!"=="" if "!PD_Y:~4!"=="" (
    call :DaysFromCivil !PD_Y! 1!PD_M!-100 1!PD_D!-100 PD_X
    call :CivilFromDays !PD_X! PD_RY PD_RM PD_RD
    if "!PD_RY!!PD_RM!!PD_RD!"=="!PD_Y!!PD_M!!PD_D!" (
        set "%~2=!PD_Y!!PD_M!!PD_D!"
        set "%~3=!PD_D!-!PD_M!-!PD_Y!"
    )
)
exit /b 0

rem Date written in a file name (first YYYY MM DD between _ or -)
:NameDay
set "ND_KEY="
set "ND_TEXT=!L_NODATE!"
set "ND_S=%~1"
set "ND_S=!ND_S:_= !"
set "ND_S=!ND_S:-= !"
set "ND_A="
set "ND_B="
set "ND_C="
:NameDayLoop
if not defined ND_S goto :NameDayEnd
set "ND_T="
for /f "tokens=1*" %%a in ("!ND_S!") do (
    set "ND_T=%%a"
    set "ND_S=%%b"
)
if not defined ND_T goto :NameDayEnd
set "ND_A=!ND_B!"
set "ND_B=!ND_C!"
set "ND_C=!ND_T!"
if defined ND_A if not "!ND_A:~3,1!"=="" call :ParseDate "!ND_C!-!ND_B!-!ND_A!" ND_KEY ND_TEXT
if not defined ND_KEY goto :NameDayLoop
:NameDayEnd
if not defined ND_KEY set "ND_TEXT=!L_NODATE!"
exit /b 0

:DayText
call :CivilFromDays %~1 DT_Y DT_M DT_D
set "%~2=!DT_D!-!DT_M!-!DT_Y!"
exit /b 0

rem ---------------------------------------------------------------------------
:CleanDir
if not defined P_DIR exit /b 0
set "P_DIR=!P_DIR:"=!"
if not defined P_DIR exit /b 0
if "!P_DIR:~-1!"=="\" if not "!P_DIR:~-2,1!"==":" set "P_DIR=!P_DIR:~0,-1!"
for %%I in ("!P_DIR!") do set "P_DIR=%%~fI"
exit /b 0

rem NAME_OK=1 if P_OUT has no character forbidden in file names
:CheckName
set "NAME_OK=1"
set "CN_S=!P_OUT!"
:CheckNameLoop
if not defined CN_S exit /b 0
set "CN_C=!CN_S:~0,1!"
set "CN_S=!CN_S:~1!"
for %%x in ("\" "/" ":" "<" ">" "|") do if "!CN_C!"==%%x set "NAME_OK="
if "!CN_C!"=="*" set "NAME_OK="
if "!CN_C!"=="?" set "NAME_OK="
goto :CheckNameLoop

rem %1 variable name: UNSAFE=1 when its value contains ! % or ^ (delayed
rem expansion would alter it, e.g. "D:\FW!01" would become "D:\FW01")
:UnsafeChars
setlocal DisableDelayedExpansion
set "UC_BAD="
for /f "tokens=1* delims==" %%A in ('set %~1 2^>nul') do if /i "%%A"=="%~1" (
    for /f "delims=!^%%" %%C in ("x%%B") do if not "%%C"=="x%%B" set "UC_BAD=1"
)
endlocal & set "UNSAFE=%UC_BAD%"
exit /b 0

:InputError
echo(
echo  !L_ERROR! %~1
echo(
if "!BATCH!"=="1" call :Usage
set /a EXIT_CODE=10
exit /b 0

rem ---------------------------------------------------------------------------
:WriteSummary
>"!SUM_FILE!" (
    echo PAN-OS CSV Search %SCRIPT_VERSION% - %SCRIPT_AUTHOR% - %SCRIPT_URL%
    echo(
    echo !L_S_FOLDER! : !P_DIR!
    echo !L_S_PERIOD! : !FROM_TEXT! - !TO_TEXT!
    if defined Q_SRC  echo !L_S_SRC! : !Q_SRC!
    if defined Q_DST  echo !L_S_DST! : !Q_DST!
    if defined Q_IP   echo !L_S_IP! : !Q_IP!
    if defined Q_USER echo !L_S_USER! : !Q_USER!
    if defined Q_TEXT echo !L_S_TEXT! : !Q_TEXT!
    echo !L_S_RESULTS! : !OUT_FILE!
    echo(
    echo !L_SUM_READ! !DONE!   !L_SUM_MATCHF! !MATCH_FILES!   !L_SUM_LINES! !TOTAL_LINES!   !L_DUR! !DURATION! s
    echo(
    echo !L_SUM_LIST!
    type "!FILESF!"
    if !BAD_FILES! GTR 0 (
        echo(
        echo !L_SUM_BAD!
        type "!BADF!"
    )
)
exit /b 0

:Summary
echo(
echo ------------------------------------------------------------
if !TOTAL_LINES! GTR 0 (
    echo  !L_SUM_LINES! !TOTAL_LINES!   !L_SUM_MATCHF! !MATCH_FILES!
) else (
    echo  !L_NOLINES!
)
echo(
echo  !L_READ! : !DONE! !L_OF! !TOTAL_FILES!   !L_DUR! !DURATION! s
if !BAD_FILES! GTR 0 echo  !L_BADN! !BAD_FILES! !L_INSUM!
echo(
echo  !L_RESULTS! : !OUT_FILE!
echo  !L_SUMMARY! : !SUM_FILE!
echo ------------------------------------------------------------
exit /b 0

:Banner
echo(
echo ============================================================
echo  PAN-OS CSV Search %SCRIPT_VERSION% - %SCRIPT_AUTHOR% - %SCRIPT_URL%
echo ============================================================
echo(
exit /b 0

:Usage
if /i "%LANGUAGE%"=="it" goto :UsageIt
echo(
echo  Guided use: double click the file, or drag the log folder onto it.
echo(
echo  Command line:
echo    %SCRIPT_NAME% "FOLDER" [/from DD-MM-YYYY] [/to DD-MM-YYYY]
echo        [/src "IP ..."] [/dst "IP ..."] [/ip "IP ..."] [/user "USER ..."]
echo        [/text "TEXT ..."] [/unarchived] [/out NAME] [/lang en or it] [/debug]
echo(
echo  Example:
echo    %SCRIPT_NAME% "D:\FTP\FW01-TRAFFIC" /from 25-09-2026 /to 29-09-2026 /src 192.0.2.10
echo(
exit /b 0
:UsageIt
echo(
echo  Uso guidato : doppio clic sul file, oppure trascina la cartella dei log sul file.
echo(
echo  Riga di comando:
echo    %SCRIPT_NAME% "CARTELLA" [/from GG-MM-AAAA] [/to GG-MM-AAAA]
echo        [/src "IP ..."] [/dst "IP ..."] [/ip "IP ..."] [/user "UTENTE ..."]
echo        [/text "TESTO ..."] [/unarchived] [/out NOME] [/lang en o it] [/debug]
echo(
echo  Esempio:
echo    %SCRIPT_NAME% "D:\FTP\FW01-TRAFFIC" /from 25-09-2026 /to 29-09-2026 /src 192.0.2.10
echo(
exit /b 0

rem Screen messages in English (default) or Italian
:LangLoad
if /i not "%LANGUAGE%"=="it" set "LANGUAGE=en"
if /i "%LANGUAGE%"=="it" goto :LangIt
set "L_UNKNOWN=Unknown option:"
set "L_ERROR=ERROR:"
set "L_NO7Z=7-Zip not found in"
set "L_FIX7Z=Set SEVENZIP_PATH at the top of the script."
set "L_NOCLOCK=unable to read the system date and time."
set "L_ASKDIR=Log folder, for example"
set "L_P_DIR=(you can drag it here)"
set "L_DIRNF=Folder not found:"
set "L_FOLDER=Folder"
set "L_PERIOD_HELP=Period (date of the day folders, dd-mm-yyyy, * = whole archive)"
set "L_P_FROM=From"
set "L_P_TO=To  "
set "L_BADDATE=Invalid date:"
set "L_BADEND=Invalid date, or earlier than the start:"
set "L_WHAT=What to search (leave a field empty to skip it)"
set "L_WHAT1=- several values separated by spaces: any of them"
set "L_WHAT2=- several fields filled in: all of them"
set "L_WHAT3=- * as wildcard, for example 192.0.2.*"
set "L_P_SRC=Source IP               "
set "L_P_DST=Destination IP          "
set "L_P_IP=Source or destination IP"
set "L_P_USER=User (also partial)     "
set "L_P_TEXT=Free text               "
set "L_FILLONE=Fill in at least one field."
set "L_P_UNARCH=Search also the CSV files not archived yet? (y/N)"
set "L_P_OUT=Name of the result file"
set "L_E_NODIR=log folder not specified"
set "L_E_CHARS=the log folder or the script folder contains an unsupported character (exclamation mark, percent sign or caret)"
set "L_E_DIRNF=folder not found:"
set "L_E_FROM=invalid start date:"
set "L_E_TO=invalid end date, or earlier than the start:"
set "L_E_NOCRIT=no search criteria"
set "L_E_NAME=invalid file name:"
set "L_E_OUTDIR=unable to create"
set "L_NOARCH=No archive found in the period"
set "L_SEARCH=Search"
set "L_S_FOLDER=Folder   "
set "L_S_PERIOD=Period   "
set "L_S_SRC=Src IP   "
set "L_S_DST=Dst IP   "
set "L_S_IP=Src/Dst  "
set "L_S_USER=User     "
set "L_S_TEXT=Text     "
set "L_S_INCL=Included "
set "L_S_RESULTS=Results  "
set "L_DAYS=days:"
set "L_FILES=files:"
set "L_UNARCH_INC=CSV files not archived yet"
set "L_WARN_COLS=Warning: columns not found in the header, standard positions used"
set "L_P_START=Start the search? (Y/n)"
set "L_CANCEL=Search cancelled."
set "L_COL_DAY=Day"
set "L_COL_LINE=Line"
set "L_TABLE=Day              Files  Lines found"
set "L_TITLE_DONE=completed"
set "L_NOT_ARCH=not archived"
set "L_OF=of"
set "L_BAD=WARNING: unreadable or damaged file:"
set "L_BEGIN=start"
set "L_END=end of archive"
set "L_NODATE=no date"
set "L_SUMSUFFIX=_summary"
set "L_SUM_READ=Files read:"
set "L_SUM_MATCHF=Files with results:"
set "L_SUM_LINES=Lines found:"
set "L_DUR=Duration:"
set "L_SUM_LIST=Files with results (day, file, lines):"
set "L_SUM_BAD=Unreadable or damaged files:"
set "L_NOLINES=No lines found"
set "L_READ=Files read"
set "L_BADN=Unreadable files:"
set "L_INSUM=(list in the summary)"
set "L_RESULTS=Results"
set "L_SUMMARY=Summary"
exit /b 0
:LangIt
set "L_UNKNOWN=Opzione sconosciuta:"
set "L_ERROR=ERRORE:"
set "L_NO7Z=7-Zip non trovato in"
set "L_FIX7Z=Modifica SEVENZIP_PATH in cima allo script."
set "L_NOCLOCK=impossibile leggere data e ora di sistema."
set "L_ASKDIR=Cartella dei log, ad esempio"
set "L_P_DIR=(puoi trascinarla qui)"
set "L_DIRNF=Cartella non trovata:"
set "L_FOLDER=Cartella"
set "L_PERIOD_HELP=Periodo (data delle cartelle giornaliere, gg-mm-aaaa, * = tutto)"
set "L_P_FROM=Dal "
set "L_P_TO=Al  "
set "L_BADDATE=Data non valida:"
set "L_BADEND=Data non valida o precedente all'inizio:"
set "L_WHAT=Cosa cercare (lascia vuoto un campo per non usarlo)"
set "L_WHAT1=- piu' valori separati da spazio: basta che ne compaia uno"
set "L_WHAT2=- piu' campi compilati: devono valere tutti insieme"
set "L_WHAT3=- * come jolly, ad esempio 192.0.2.*"
set "L_P_SRC=IP sorgente               "
set "L_P_DST=IP destinazione           "
set "L_P_IP=IP sorgente o destinazione"
set "L_P_USER=Utente (anche parziale)   "
set "L_P_TEXT=Testo libero              "
set "L_FILLONE=Compila almeno un campo."
set "L_P_UNARCH=Cercare anche nei CSV non ancora archiviati? (s/N)"
set "L_P_OUT=Nome del file risultati"
set "L_E_NODIR=cartella dei log non indicata"
set "L_E_CHARS=la cartella dei log o quella dello script contiene un carattere non supportato (punto esclamativo, percentuale o accento circonflesso)"
set "L_E_DIRNF=cartella non trovata:"
set "L_E_FROM=data di inizio non valida:"
set "L_E_TO=data di fine non valida o precedente all'inizio:"
set "L_E_NOCRIT=nessun criterio di ricerca"
set "L_E_NAME=nome file non valido:"
set "L_E_OUTDIR=impossibile creare"
set "L_NOARCH=Nessun archivio trovato nel periodo"
set "L_SEARCH=Ricerca"
set "L_S_FOLDER=Cartella "
set "L_S_PERIOD=Periodo  "
set "L_S_SRC=IP sorg. "
set "L_S_DST=IP dest. "
set "L_S_IP=IP s/d   "
set "L_S_USER=Utente   "
set "L_S_TEXT=Testo    "
set "L_S_INCL=Inclusi  "
set "L_S_RESULTS=Risultati"
set "L_DAYS=giorni:"
set "L_FILES=file:"
set "L_UNARCH_INC=CSV non ancora archiviati"
set "L_WARN_COLS=Attenzione: colonne non trovate nell'intestazione, uso le posizioni standard"
set "L_P_START=Avviare la ricerca? (S/n)"
set "L_CANCEL=Ricerca annullata."
set "L_COL_DAY=Giorno"
set "L_COL_LINE=Riga"
set "L_TABLE=Giorno           File   Righe trovate"
set "L_TITLE_DONE=completata"
set "L_NOT_ARCH=non archiviato"
set "L_OF=di"
set "L_BAD=ATTENZIONE: file illeggibile o danneggiato:"
set "L_BEGIN=inizio"
set "L_END=fine archivio"
set "L_NODATE=senza data"
set "L_SUMSUFFIX=_riepilogo"
set "L_SUM_READ=File letti:"
set "L_SUM_MATCHF=File con risultati:"
set "L_SUM_LINES=Righe trovate:"
set "L_DUR=Durata:"
set "L_SUM_LIST=File con risultati (giorno, file, righe):"
set "L_SUM_BAD=File illeggibili o danneggiati:"
set "L_NOLINES=Nessuna riga trovata"
set "L_READ=File letti"
set "L_BADN=File illeggibili:"
set "L_INSUM=(elenco nel riepilogo)"
set "L_RESULTS=Risultati"
set "L_SUMMARY=Riepilogo"
exit /b 0

rem ---------------------------------------------------------------------------
rem Time: robocopy prints the local time in its error lines (any language)
:Now
set "NOW_DATE="
for /f "tokens=1,2" %%A in ('%ROBOCOPY% "|" . /L /NJH /R:0 /W:0 2^>nul ^| %FINDSTR% /r /b /c:"[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9] "') do (
    if not defined NOW_DATE (
        set "NOW_DATE=%%A"
        set "NOW_TIME=%%B"
    )
)
if not defined NOW_DATE exit /b 1
call :DaysFromCivil !NOW_DATE:~0,4! 1!NOW_DATE:~5,2!-100 1!NOW_DATE:~8,2!-100 NOW_DAYS
set /a NOW_EPOCH=NOW_DAYS*86400+(1!NOW_TIME:~0,2!-100)*3600+(1!NOW_TIME:~3,2!-100)*60+(1!NOW_TIME:~6,2!-100)
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

rem %2=1 if %1 contains digits only
:IsNumber
set "%~2=0"
if "%~1"=="" exit /b 0
for /f "delims=0123456789" %%X in ("%~1x") do if "%%X"=="x" set "%~2=1"
exit /b 0
