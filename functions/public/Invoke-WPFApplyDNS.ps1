function Invoke-WPFApplyDNS {
    <#
    .SYNOPSIS
        Applies the DNS provider picked in the "DNS - Set to:" box on the Gaming tab
    #>

    $provider = Invoke-WPFUIThread -PassThru -ScriptBlock { "$($sync['WPFchangedns'].Text)" }
    if ([string]::IsNullOrWhiteSpace($provider)) {
        $provider = "Default"
    }

    if ($provider -eq "Default") {
        Write-Host "Pick a DNS provider in the box first. Default leaves your DNS unchanged." -ForegroundColor Yellow
        return
    }

    Step-WinUtilJob -Status "Setting DNS to $provider" -State "Indeterminate"
    Write-WinUtilLog -Component "DNS" -Message "Setting DNS to $provider"
    $result = @(Set-WinUtilDNS -DNSProvider $provider)
    if ($result[-1] -ne $true) {
        throw "The DNS change to $provider failed."
    }
    ipconfig.exe /flushdns | Out-Null
    Write-Host "DNS set to $provider." -ForegroundColor Green
}
