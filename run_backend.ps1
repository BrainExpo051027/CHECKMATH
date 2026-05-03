param (
    [switch]$Network
)

# If scripts are blocked: powershell -ExecutionPolicy Bypass -File .\run_backend.ps1
# Prefer: .\run_backend.cmd
Set-Location $PSScriptRoot\backend
$env:PORT = if ($env:PORT) { $env:PORT } else { "8765" }
$hostIp = if ($Network) { "0.0.0.0" } else { "127.0.0.1" }

if ($Network) {
    Write-Host "WARNING: Binding to 0.0.0.0. If you get WinError 10013, switch back to 127.0.0.1" -ForegroundColor Yellow
}

Write-Host "Starting http://${hostIp}:$($env:PORT)"
py -3 -m uvicorn main:app --host $hostIp --port $env:PORT
