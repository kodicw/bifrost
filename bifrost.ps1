[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Config = "C:\Bifrost\firewall.json",

    [Parameter(Mandatory=$false)]
    [bool]$Pure = $false # Now defaults to Impure (Additive)
)

# --- RAW DATA: Load Config ---
if (-not (Test-Path $Config)) {
    Write-Host "[!] Error: Configuration not found at $Config" -ForegroundColor Red
    exit 1
}

$Data = Get-Content -Raw $Config | ConvertFrom-Json
$Tag = "BifrostManaged"

# --- LOGIC: The Sync ---

if ($Pure) {
    Write-Host "[i] Running in PURE mode. Purging existing Bifrost rules..." -ForegroundColor Yellow
    Remove-NetFirewallRule -Group $Tag -ErrorAction SilentlyContinue
} else {
    Write-Host "[i] Running in IMPURE mode (Default). Adding/Updating rules only..." -ForegroundColor Gray
}

# Set Profile State
Set-NetFirewallProfile -All -Enabled ([bool]$Data.Enabled)

if ($Data.Enabled) {
    # Apply TCP
    foreach ($Port in $Data.AllowedTCPPorts) {
        $RuleName = "Bifrost-TCP-$Port"
        if (-not (Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name $RuleName -DisplayName $RuleName -Group $Tag -Protocol TCP -LocalPort $Port -Action Allow
        }
    }

    # Apply UDP
    foreach ($Port in $Data.AllowedUDPPorts) {
        $RuleName = "Bifrost-UDP-$Port"
        if (-not (Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name $RuleName -DisplayName $RuleName -Group $Tag -Protocol UDP -LocalPort $Port -Action Allow
        }
    }
}

Write-Host "Success: Sync Complete." -ForegroundColor Green
