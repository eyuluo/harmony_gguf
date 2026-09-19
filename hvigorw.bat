@echo off
rem Usage:
rem   1. Set DEVECO_HOME to your DevEco Studio installation directory, for example:
rem        set "DEVECO_HOME=D:\Programs\DevEco Studio"
rem   2. Alternatively, set HVIGOR_HOME to the Hvigor directory or HVIGORW to the
rem      full path of a specific hvigorw.bat file.
rem   3. Run Hvigor tasks through this wrapper, for example:
rem        hvigorw.bat codeLinter --mode module -p product=default
rem        hvigorw.bat assembleHap --mode module -p product=default
setlocal EnableExtensions DisableDelayedExpansion

set "HVIGOR_WRAPPER_SELF=%~f0"
set "HVIGOR_WRAPPER_TARGET="

if defined HVIGORW call :select_target "%HVIGORW%"
if defined HVIGOR_WRAPPER_TARGET goto execute

if defined HVIGOR_HOME call :select_target "%HVIGOR_HOME%\bin\hvigorw.bat"
if defined HVIGOR_WRAPPER_TARGET goto execute
if defined HVIGOR_HOME call :select_target "%HVIGOR_HOME%\hvigorw.bat"
if defined HVIGOR_WRAPPER_TARGET goto execute

if defined DEVECO_HOME call :select_target "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat"
if defined HVIGOR_WRAPPER_TARGET goto execute

for /f "usebackq delims=" %%I in (`where.exe hvigorw.bat 2^>nul`) do (
  call :select_target "%%~fI"
  if defined HVIGOR_WRAPPER_TARGET goto execute
)

echo [ERROR] DevEco Studio hvigorw.bat was not found. 1>&2
echo [HINT] Set DEVECO_HOME, HVIGOR_HOME, or HVIGORW to the full path. 1>&2
exit /b 1

:execute
call "%HVIGOR_WRAPPER_TARGET%" %*
exit /b %ERRORLEVEL%

:select_target
if not exist "%~1" exit /b 0
for %%I in ("%~1") do set "HVIGOR_WRAPPER_CANDIDATE=%%~fI"
if /i "%HVIGOR_WRAPPER_CANDIDATE%"=="%HVIGOR_WRAPPER_SELF%" exit /b 0
set "HVIGOR_WRAPPER_TARGET=%HVIGOR_WRAPPER_CANDIDATE%"
exit /b 0
