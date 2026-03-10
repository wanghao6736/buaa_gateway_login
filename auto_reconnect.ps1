<#
.SYNOPSIS
    BUAA Gateway auto-reconnect script for Windows.

.DESCRIPTION
    Detects whether the campus network gateway login is needed by checking
    if HTTP requests are redirected to gw.buaa.edu.cn, then calls the
    Python login script when necessary.

.PARAMETER Loop
    Run continuously instead of one-shot.

.PARAMETER Interval
    Seconds between checks in loop mode (default: 600).

.EXAMPLE
    # One-shot check
    .\auto_reconnect.ps1

    # Loop mode with 5-minute interval
    .\auto_reconnect.ps1 -Loop -Interval 300

.NOTES
    Credentials are read from environment variables:
      $env:BUAA_USERNAME = "by1234567"
      $env:BUAA_PASSWORD = "your_password"
    If not set, the Python script will prompt interactively.
#>

param(
    [switch]$Loop,
    [int]$Interval = 600
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonScript = Join-Path $ScriptDir "buaa_gateway_login.py"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Test-NeedsLogin {
    try {
        $response = Invoke-WebRequest -Uri "http://baidu.com" `
            -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 5 `
            -ErrorAction SilentlyContinue
        return $response.Content -match "gw\.buaa\.edu\.cn"
    }
    catch {
        return $true
    }
}

function Invoke-Login {
    Write-Log "Network disconnected - attempting login..."
    try {
        python $PythonScript
        Start-Sleep -Seconds 2
        if (-not (Test-NeedsLogin)) {
            Write-Log "Login successful."
            return $true
        }
    }
    catch {
        Write-Log "Error running login script: $_"
    }
    Write-Log "Login failed, still disconnected."
    return $false
}

function Invoke-Check {
    if (Test-NeedsLogin) {
        Invoke-Login | Out-Null
    }
    else {
        Write-Log "Network is connected."
    }
}

if ($Loop) {
    Write-Log "Starting auto-reconnect loop (interval: ${Interval}s)..."
    while ($true) {
        Invoke-Check
        Start-Sleep -Seconds $Interval
    }
}
else {
    Invoke-Check
}
