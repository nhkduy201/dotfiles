# Check if Python is available
$pythonExe = $null

# Check if 'python' is in PATH
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonExe = "python"
} else {
    # Check default Python installation paths
    $possiblePaths = @(
        "${env:ProgramFiles}\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe"
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
        
        Write-Host "Downloading Python installer..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
        
        Write-Host "Installing Python (admin rights required)..."
        Start-Process -FilePath $installerPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=0" -Wait -Verb RunAs
        
        # Verify installation
        if (Test-Path "${env:ProgramFiles}\Python312\python.exe") {
            $pythonExe = "${env:ProgramFiles}\Python312\python.exe"
        } else {
            Write-Host "Failed to install Python. Install it manually."
            exit 1
        }
    }
}

# Run the Python script
& $pythonExe get_transcript.py $args