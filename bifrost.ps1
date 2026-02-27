[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Config = "C:\Bifrost\firewall.json",
    [Parameter(Mandatory=$false)]
    [bool]$Pure = $false
)

if (-not (Test-Path $Config)) { Write-Error "Config not found."; exit 1 }
$Data = Get-Content -Raw $Config | ConvertFrom-Json
$Tag = "BifrostManaged"

# --- DECLARATIVE PURGE ---
if ($Pure) {
    Remove-NetFirewallRule -Group $Tag -ErrorAction SilentlyContinue
}

# --- PROFILE STATE ---
Set-NetFirewallProfile -All -Enabled ([bool]$Data.Enabled)
if (-not $Data.Enabled) { return }

# --- HELPERS ---
function Add-BifrostRule {
    param($Name, $Proto, $Port, $Remote = "Any")
    $FullID = "Bifrost-$Name"
    if (-not (Get-NetFirewallRule -Name $FullID -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $FullID -DisplayName $FullID -Group $Tag -Protocol $Proto -LocalPort $Port -RemoteAddress $Remote -Action Allow
    }
}

# --- LOGIC: ICMP (Ping) ---
if ($Data.AllowPing) {
    Add-BifrostRule -Name "ICMPv4" -Proto ICMPv4 -Port Any
}

# --- LOGIC: RDP ---
if ($Data.EnableRDP) {
    Add-BifrostRule -Name "RDP-TCP" -Proto TCP -Port 3389
}

# --- LOGIC: Ports ---
$RemoteFilter = if ($Data.TailscaleOnly) { "100.64.0.0/10" } else { "Any" }

foreach ($Port in $Data.AllowedTCPPorts) {
    Add-BifrostRule -Name "TCP-$Port" -Proto TCP -Port $Port -Remote $RemoteFilter
}
foreach ($Port in $Data.AllowedUDPPorts) {
    Add-BifrostRule -Name "UDP-$Port" -Proto UDP -Port $Port -Remote $RemoteFilter
}

Write-Host "Bifrost: System state synchronized." -ForegroundColor Green
