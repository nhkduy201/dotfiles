function Set-GoogleDNS {
    param (
        [string[]]$IPv4Servers,
        [string[]]$IPv6Servers
    )

    # Get all network adapters
    $networkAdapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

    foreach ($adapter in $networkAdapters) {
        Write-Host "Setting DNS for adapter: $($adapter.Name)"
        
        # Set IPv4 DNS
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $IPv4Servers
        
        # Set IPv6 DNS
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $IPv6Servers
    }

    Write-Host "DNS settings updated successfully."
}
Set-GoogleDNS -IPv4Servers @("8.8.8.8", "8.8.4.4") -IPv6Servers @("2001:4860:4860::8888", "2001:4860:4860::8844")
