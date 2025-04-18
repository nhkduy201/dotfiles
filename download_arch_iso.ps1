$VERSION_PAGE = "https://archlinux.org/download/"
$CHECKSUM_FILE = "sha256sums.txt"
$LOG_FILE = "archlinux_download.log"
$VIETNAM_DOMAINS = @("huongnguyen.dev", "meowsmp.net", "nguyenhoang.cloud", "twilight.fyi")
$WORLDWIDE_DOMAINS = @("pkgbuild.com", "infania.net", "rackspace.com")
$MAX_RETRIES = 3
$USER_AGENT = "ArchLinux-Downloader/1.0"
$SPEED_TEST_TIMEOUT = 5

Start-Transcript -Path $LOG_FILE -Append | Out-Null

# Get latest version
try {
    $versionPage = Invoke-WebRequest -Uri $VERSION_PAGE -UserAgent $USER_AGENT
    $LATEST_VERSION = ($versionPage.Content -split 'Current Release:</strong>\s*')[1].Substring(0,10)
    Write-Host "Detected version: $LATEST_VERSION" -ForegroundColor Green
} catch {
    Write-Error "Version detection failed"
    Stop-Transcript
    exit 1
}

# Function to categorize mirrors
function Get-CategorizedMirrors {
    $mirrors = @{
        Vietnam = @()
        Worldwide = @()
    }

    $versionPage.Links.href | Where-Object {
        $_ -match "/iso/$LATEST_VERSION/" -and
        $_ -match "^https://([^/]+)"
    } | ForEach-Object {
        $domain = $matches[1]
        $mainDomain = ($domain -split '\.' | Select-Object -Last 2) -join '.'
        
        if ($VIETNAM_DOMAINS -contains $mainDomain) {
            $mirrors.Vietnam += $_
        }
        elseif ($WORLDWIDE_DOMAINS -contains $mainDomain) {
            $mirrors.Worldwide += $_
        }
    }

    return $mirrors
}

# Speed test function (Compatible with older PowerShell versions)
function Get-FastestMirror {
    param($mirrors)
    $results = @()
    
    foreach ($url in $mirrors) {
        try {
            Write-Host "  Testing $url" -ForegroundColor Gray
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-WebRequest -Uri "$url$CHECKSUM_FILE" -Method Head `
                -TimeoutSec $SPEED_TEST_TIMEOUT -UseBasicParsing -ErrorAction Stop | Out-Null
            $stopwatch.Stop()
            
            $results += [PSCustomObject]@{
                Url = $url
                Speed = $stopwatch.Elapsed.TotalSeconds
            }
            Write-Host "  Speed: $($stopwatch.Elapsed.TotalSeconds.ToString('0.00')) seconds" -ForegroundColor Gray
        } catch {
            Write-Host "  Failed to test $url" -ForegroundColor Red
        }
    }
    
    if ($results.Count -eq 0) {
        return $null
    }
    
    $fastest = $results | Sort-Object Speed | Select-Object -First 1
    Write-Host "Fastest mirror: $($fastest.Url) ($($fastest.Speed.ToString('0.00')) seconds)" -ForegroundColor Yellow
    return $fastest.Url
}

# Main execution
$categorized = Get-CategorizedMirrors

if (-not $categorized.Vietnam -or $categorized.Vietnam.Count -eq 0) {
    Write-Error "No Vietnam mirrors found"
    Stop-Transcript
    exit 1
}

Write-Host "Testing Vietnam mirrors ($($categorized.Vietnam.Count))..." -ForegroundColor Cyan
$fastestVietnam = Get-FastestMirror -mirrors $categorized.Vietnam

if (-not $fastestVietnam) {
    Write-Error "No responsive Vietnam mirrors found"
    Stop-Transcript
    exit 1
}

Write-Host "Testing Worldwide mirrors ($($categorized.Worldwide.Count))..." -ForegroundColor Cyan
$fastestWorldwide = Get-FastestMirror -mirrors $categorized.Worldwide

if (-not $fastestWorldwide) {
    Write-Error "No responsive Worldwide mirrors found"
    Stop-Transcript
    exit 1
}

# Download functions
function Get-ISO {
    param($baseUrl)
    $isoName = "archlinux-${LATEST_VERSION}-x86_64.iso"
    
    try {
        Write-Host "Downloading ISO from $baseUrl..." -ForegroundColor Green
        Invoke-WebRequest -Uri "$baseUrl$isoName" -OutFile $isoName -UserAgent $USER_AGENT
        return $isoName
    } catch {
        Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item -ErrorAction SilentlyContinue $isoName
        return $null
    }
}

function Verify-ISO {
    param($isoName, $checksumUrl)
    try {
        Write-Host "Downloading checksum from $checksumUrl..." -ForegroundColor Cyan
        $checksumContent = (Invoke-WebRequest -Uri "$checksumUrl$CHECKSUM_FILE" -UseBasicParsing).Content
        $expectedHash = $checksumContent.Split("`n") | Where-Object { $_ -match $isoName } | ForEach-Object { $_.Split(' ')[0] }
        
        if (-not $expectedHash) {
            Write-Host "Could not find checksum for $isoName" -ForegroundColor Red
            return $false
        }
        
        $actualHash = (Get-FileHash $isoName -Algorithm SHA256).Hash.ToLower()
        
        Write-Host "Expected: $expectedHash" -ForegroundColor Gray
        Write-Host "Actual:   $actualHash" -ForegroundColor Gray
        
        return $actualHash -eq $expectedHash.ToLower()
    } catch {
        Write-Host "Verification failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Download and verify
$retryCount = 0
while ($retryCount -lt $MAX_RETRIES) {
    $isoFile = Get-ISO -baseUrl $fastestVietnam
    if ($isoFile) {
        Write-Host "ISO downloaded, verifying checksum..." -ForegroundColor Yellow
        if (Verify-ISO $isoFile $fastestWorldwide) {
            Write-Host "Download verified successfully!" -ForegroundColor Green
            Stop-Transcript
            exit 0
        } else {
            Write-Host "Checksum verification failed" -ForegroundColor Red
        }
    }
    $retryCount++
    Write-Host "Retry $retryCount/$MAX_RETRIES" -ForegroundColor Yellow
}

Write-Error "All download attempts failed"
Stop-Transcript
exit 1