# powershell -ExecutionPolicy Bypass -File .\get_transcript.ps1 "https://www.youtube.com/watch?v=0jci98uOrWQ"

# Check if Python is available
$pythonExe = $null

# Test if a Python executable actually works
function Test-PythonWorks($pythonPath) {
    try {
        $version = & $pythonPath --version 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

# First check Windows Store Python
$windowsStorePython = "$env:LOCALAPPDATA\Microsoft\WindowsApps\python.exe"
if ((Test-Path $windowsStorePython) -and (Test-PythonWorks $windowsStorePython)) {
    $pythonExe = $windowsStorePython
} 
# Then check traditional Python installations
elseif ((Get-Command python.exe -ErrorAction SilentlyContinue) -and (Test-PythonWorks "python.exe")) {
    $pythonExe = "python.exe"
} else {
    # Check default Python installation paths
    $possiblePaths = @(
        "${env:ProgramFiles}\Python312\python.exe",
        "${env:ProgramFiles}\Python311\python.exe",
        "${env:ProgramFiles}\Python310\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python311\python.exe",
        "${env:ProgramFiles(x86)}\Python310\python.exe"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $pythonExe = $path
            break
        }
    }
    
    # If Python not found, download and install it
    if (-not $pythonExe) {
        $installerUrl = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
        $installerPath = "$env:TEMP\python_installer.exe"
        
        Write-Host "Python not found. Downloading Python installer..."
        try {
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
            
            Write-Host "Installing Python (admin rights required)..."
            Start-Process -FilePath $installerPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=0" -Wait -Verb RunAs
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            # Verify installation
            if (Test-Path "${env:ProgramFiles}\Python312\python.exe") {
                $pythonExe = "${env:ProgramFiles}\Python312\python.exe"
            } else {
                throw "Python installation failed"
            }
        }
        catch {
            Write-Host "Error: Failed to install Python automatically. Please install Python 3.12 manually from https://www.python.org/downloads/"
            exit 1
        }
    }
}

if ($pythonExe) {
    Write-Host "Using Python at: $pythonExe"
    Write-Host "Python version: $((& $pythonExe --version 2>&1))"
    $scriptPath = Join-Path $PSScriptRoot "get_transcript.py"
    & $pythonExe $scriptPath $args
} else {
    Write-Host "Error: Could not find or install Python."
    exit 1
}