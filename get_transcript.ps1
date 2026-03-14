#
# YouTube Transcript Fetcher - Windows
# Auto-discovers Python, manages venv, installs dependencies
#
# Usage: powershell -ExecutionPolicy Bypass -File .\get_transcript.ps1 "https://youtu.be/VIDEO_ID"
#

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir = Join-Path $env:LOCALAPPDATA "get_transcript_venv"
$PythonScript = Join-Path $ScriptDir "get_transcript.py"

# Test if Python executable works
function Test-PythonWorks {
    param([string]$pythonPath)
    try {
        $null = & $pythonPath --version 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

# Find Python executable
function Get-PythonExe {
    # Check Windows Store Python
    $windowsStorePython = "$env:LOCALAPPDATA\Microsoft\WindowsApps\python.exe"
    if ((Test-Path $windowsStorePython) -and (Test-PythonWorks $windowsStorePython)) {
        return $windowsStorePython
    }

    # Check PATH
    $pythonInPath = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonInPath -and (Test-PythonWorks $pythonInPath.Source)) {
        return $pythonInPath.Source
    }

    # Check common installation paths
    $possiblePaths = @(
        "${env:ProgramFiles}\Python313\python.exe",
        "${env:ProgramFiles}\Python312\python.exe",
        "${env:ProgramFiles}\Python311\python.exe",
        "${env:ProgramFiles}\Python310\python.exe",
        "${env:ProgramFiles(x86)}\Python313\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python311\python.exe",
        "${env:ProgramFiles(x86)}\Python310\python.exe"
    )

    foreach ($path in $possiblePaths) {
        if ((Test-Path $path) -and (Test-PythonWorks $path)) {
            return $path
        }
    }

    return $null
}

# Create virtual environment
function New-Venv {
    param([string]$pythonExe, [string]$venvDir)
    try {
        & $pythonExe -m venv $venvDir 2>&1 | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Install packages in venv
function Install-Packages {
    param([string]$venvDir)
    $venvPip = Join-Path $venvDir "Scripts\pip.exe"
    $venvPython = Join-Path $venvDir "Scripts\python.exe"

    try {
        & $venvPip install --upgrade pip --quiet 2>&1 | Out-Null
        & $venvPip install "youtube-transcript-api>=0.6.0" --quiet 2>&1 | Out-Null
        return $venvPython
    } catch {
        Write-Host "Error: Failed to install packages" -ForegroundColor Red
        return $null
    }
}

# Main execution
try {
    # Find Python
    $pythonExe = Get-PythonExe
    if (-not $pythonExe) {
        Write-Host "Error: Python 3 not found" -ForegroundColor Red
        Write-Host "Please install Python 3.10+ from https://www.python.org/downloads/" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Using Python: $pythonExe" -ForegroundColor Gray
    Write-Host "Python version: $(& $pythonExe --version 2>&1)" -ForegroundColor Gray

    # Create/update venv
    if (-not (Test-Path $VenvDir)) {
        Write-Host "Creating virtual environment..." -ForegroundColor Gray
        if (-not (New-Venv -pythonExe $pythonExe -venvDir $VenvDir)) {
            Write-Host "Failed to create virtual environment" -ForegroundColor Red
            exit 1
        }
    }

    # Install packages and get venv Python path
    $venvPython = Install-Packages -venvDir $VenvDir
    if (-not $venvPython) {
        exit 1
    }

    # Check Python script exists
    if (-not (Test-Path $PythonScript)) {
        Write-Host "Error: get_transcript.py not found in $ScriptDir" -ForegroundColor Red
        exit 1
    }

    # Run the Python script
    & $venvPython $PythonScript $args

} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
