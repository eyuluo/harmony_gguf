@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 exit /b %ERRORLEVEL%
cd /d "%~dp0\..\test"
cmake -B build -S . -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DCMAKE_BUILD_TYPE=Debug
if errorlevel 1 exit /b %ERRORLEVEL%
cmake --build build --target test-napi-bridge --config Debug 2>&1
exit /b %ERRORLEVEL%
