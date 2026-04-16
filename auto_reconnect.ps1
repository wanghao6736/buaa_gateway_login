param(
    [string]$PythonExe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    Write-Error "PythonExe parameter is required. Usage: .\auto_reconnect.ps1 -PythonExe 'path\to\python.exe'"
    exit 10
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonScript = Join-Path $ScriptDir "buaa_gateway_login.py"
$LogFile = Join-Path $ScriptDir "auto_reconnect_task.log"
$LockFile = Join-Path $ScriptDir ".auto_reconnect.lock"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$ts] $Message" -Encoding UTF8
}

function Acquire-Lock {
    if (Test-Path $LockFile) {
        $lockTime = (Get-Item $LockFile).LastWriteTime
        $elapsed = (Get-Date) - $lockTime
        if ($elapsed.TotalMinutes -lt 5) {
            Write-Log "Another instance is running"
            return $false
        }
        Remove-Item $LockFile -Force
    }
    
    try {
        $pid | Out-File -FilePath $LockFile -Encoding UTF8 -Force
        return $true
    }
    catch {
        Write-Log "Failed to acquire lock"
        return $false
    }
}

function Release-Lock {
    if (Test-Path $LockFile) {
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-EnvValue {
    param([string]$Name)
    
    $v = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ([string]::IsNullOrWhiteSpace($v)) {
        $v = [Environment]::GetEnvironmentVariable($Name, "User")
    }
    if ([string]::IsNullOrWhiteSpace($v)) {
        $v = [Environment]::GetEnvironmentVariable($Name, "Machine")
    }
    return $v
}

function Needs-Login {
    try {
        $resp = Invoke-WebRequest -Uri "http://baidu.com" -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction SilentlyContinue
        if ($resp.Content -match "gw\.buaa\.edu\.cn") {
            return $true
        }
        return $false
    }
    catch {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "gw\.buaa\.edu\.cn") {
            return $true
        }
        return $false
    }
}

function Do-Login {
    Write-Log "Network disconnected - attempting login..."
    
    if (-not (Test-Path -LiteralPath $PythonExe)) {
        Write-Log "Python not found: $PythonExe"
        return $false
    }
    
    $username = Get-EnvValue "BUAA_USERNAME"
    $password = Get-EnvValue "BUAA_PASSWORD"
    
    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
        Write-Log "Missing credentials"
        return $false
    }
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PythonExe
    $psi.Arguments = "`"$PythonScript`""
    $psi.WorkingDirectory = $ScriptDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.EnvironmentVariables["BUAA_USERNAME"] = $username
    $psi.EnvironmentVariables["BUAA_PASSWORD"] = $password
    
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    
    try {
        [void]$proc.Start()
        $proc.StandardInput.Close()
        
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        
        $proc.WaitForExit()
        
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Add-Content -Path $LogFile -Value $stdout -Encoding UTF8
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Add-Content -Path $LogFile -Value $stderr -Encoding UTF8
        }
        
        Start-Sleep -Seconds 2
        
        if (-not (Needs-Login)) {
            Write-Log "Login successful"
            return $true
        }
    }
    catch {
        Write-Log "Login failed"
    }
    finally {
        if ($null -ne $proc) {
            $proc.Dispose()
        }
    }
    
    Write-Log "Login failed, still disconnected"
    return $false
}

function Run-Once {
    if (Needs-Login) {
        Do-Login
    }
    else {
        Write-Log "Network is connected"
    }
}

if (-not (Acquire-Lock)) {
    [System.Environment]::Exit(15)
}

try {
    Write-Log "Task started"
    Run-Once
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)"
}
finally {
    Write-Log "Task finished"
    Release-Lock
}