@echo off
call "%~dp0cpp-build-only.bat"
if errorlevel 1 exit /b %ERRORLEVEL%
ctest --test-dir "%~dp0..\test\build" -R "^m2-napi-bridge$" --output-on-failure --no-tests=error
exit /b %ERRORLEVEL%
