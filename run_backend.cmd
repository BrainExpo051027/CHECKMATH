@echo off
REM CheckMath API — defaults to 127.0.0.1 (avoids WinError 10013 on 0.0.0.0) 
REM Usage: run_backend.cmd [--network] to listen on 0.0.0.0 for LAN testing
set HOST=127.0.0.1
if "%~1"=="--network" (
    set HOST=0.0.0.0
    echo WARNING: Binding to 0.0.0.0. If you get WinError 10013, switch back to 127.0.0.1
)

cd /d "%~dp0backend"
set PORT=8765
echo Starting http://%HOST%:%PORT%  (edit PORT in this file if needed)
py -3 -m uvicorn main:app --host %HOST% --port %PORT%
