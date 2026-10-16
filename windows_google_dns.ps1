# Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object { Set-DnsClientServerAddress -InterfaceAlias $_.Name -ServerAddresses @("1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001") }
# Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object { Set-DnsClientServerAddress -InterfaceAlias $_.Name -ServerAddresses @("8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844") }
# Requires Administrator privileges
# File: set-secure-dns.ps1

Write-Host "Configuring Cloudflare DNS-over-HTTPS (DoH)..." -ForegroundColor Cyan

# 1. Register Cloudflare DoH templates (IPv4 & IPv6)
$dohServers = @(
    @{ IP = "1.1.1.1"; Template = "https://cloudflare-dns.com/dns-query" },
    @{ IP = "1.0.0.1"; Template = "https://cloudflare-dns.com/dns-query" },
    @{ IP = "2606:4700:4700::1111"; Template = "https://cloudflare-dns.com/dns-query" },
    @{ IP = "2606:4700:4700::1001"; Template = "https://cloudflare-dns.com/dns-query" }
)

foreach ($entry in $dohServers) {
    Set-DnsClientDohServerAddress -ServerAddress $entry.IP -DohTemplate $entry.Template -AllowFallbackToUdp $false -AutoUpgrade $true
}

# 2. Assign DNS addresses to all active (Up) network adapters
$dnsAddresses = @("1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001")

Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
    Write-Host "Applying to: $($_.Name)" -ForegroundColor Green
    Set-DnsClientServerAddress -InterfaceAlias $_.Name -ServerAddresses $dnsAddresses
}

# 3. Flush local resolver cache
Clear-DnsClientCache

Write-Host "Done! Encrypted DNS (DoH) is active across all up interfaces." -ForegroundColor Cyan
