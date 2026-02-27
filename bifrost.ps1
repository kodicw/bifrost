[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Config = "C:\Bifrost\firewall.json",
    [Parameter(Mandatory=$false)]
    [bool]$Pure = $false
)

# ==========================================
# STAGE 0: POLICY DETECTION & BOOTSTRAP
# ==========================================
Write-Host "[Stage 0: Pre-Flight Check]" -ForegroundColor Magenta

# 1. Execution Policy Check
$Policy = Get-ExecutionPolicy
$CanRunScripts = $Policy -notin @("Restricted", "AllSigned") 

if (-not $CanRunScripts) {
    Write-Host "[!] Policy is $Policy. Attempting to elevate to RemoteSigned..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    } catch {
        Write-Host "[FAIL] System Policy prevents script execution. Parts of this script WILL fail." -ForegroundColor Red
    }
}

# 2. Admin Detection
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# 3. Directory & Config Setup
if (-not (Test-Path "C:\Bifrost")) { New-Item -Path "C:\Bifrost" -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $Config)) {
    Write-Host "[*] Initializing default config..." -ForegroundColor Gray
    @{ packages = @{ buckets = @("extras"); apps = @("git"); global_apps = @() }; 
       networking = @{ firewall = @{ enabled = $true; allowPing = $true; allowedTCPPorts = @(80, 443) } } 
    } | ConvertTo-Json -Depth 10 | Out-File $Config
}

$Data = Get-Content -Raw $Config | ConvertFrom-Json

# ==========================================
# STAGE 1: PACKAGE MANAGEMENT (SCOOP)
# ==========================================
Write-Host "`n[Stage 1: Packages]" -ForegroundColor Cyan
if ($Data.packages) {
    # Check if Scoop is even possible
    if ($Policy -eq "Restricted") {
        Write-Host "[SKIP] Cannot install packages: ExecutionPolicy is Restricted." -ForegroundColor Red
    } else {
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Host "[*] Installing Scoop..." -ForegroundColor Yellow
            irm get.scoop.sh | iex
        }

        # Buckets & User Apps
        $Data.packages.buckets | ForEach-Object { if (-not (scoop bucket list | Select-String $_)) { scoop bucket add $_ } }
        $Data.packages.apps | ForEach-Object { if (-not (scoop list | Select-String "^$_\s")) { scoop install $_ } }

        # Global Apps Check
        if ($Data.packages.global_apps) {
            if ($IsAdmin) {
                $Data.packages.global_apps | ForEach-Object { if (-not (scoop list | Select-String "^$_\s.*\[global\]")) { scoop install $_ -g } }
            } else {
                Write-Host "[WARN] Skipping Global Apps: Admin privileges required." -ForegroundColor Yellow
            }
        }
    }
}

# ==========================================
# STAGE 2: NETWORKING (FIREWALL)
# ==========================================
Write-Host "`n[Stage 2: Networking]" -ForegroundColor Cyan
if ($Data.networking.firewall) {
    if (-not $IsAdmin) {
        Write-Host "[SKIP] Firewall config requires Administrator privileges." -ForegroundColor Red
    } else {
        $FW = $Data.networking.firewall
        $Tag = "BifrostManaged"

        if ($Pure) { Remove-NetFirewallRule -Group $Tag -ErrorAction SilentlyContinue }
        Set-NetFirewallProfile -All -Enabled ([bool]$FW.enabled)

        if ($FW.enabled) {
            function Add-BifrostRule {
                param($Name, $Proto, $Port, $Remote = "Any")
                $FullID = "Bifrost-$Name"
                if (-not (Get-NetFirewallRule -Name $FullID -ErrorAction SilentlyContinue)) {
                    New-NetFirewallRule -Name $FullID -DisplayName $FullID -Group $Tag -Protocol $Proto -LocalPort $Port -RemoteAddress $Remote -Action Allow
                }
            }

            if ($FW.allowPing) { Add-BifrostRule -Name "Ping" -Proto ICMPv4 -Port Any }
            if ($FW.enableRDP) { Add-BifrostRule -Name "RDP" -Proto TCP -Port 3389 }
            $Remote = if ($FW.tailscaleOnly) { "100.64.0.0/10" } else { "Any" }
            $FW.allowedTCPPorts | ForEach-Object { Add-BifrostRule -Name "TCP-$_" -Proto TCP -Port $_ -Remote $Remote }
            $FW.allowedUDPPorts | ForEach-Object { Add-BifrostRule -Name "UDP-$_" -Proto UDP -Port $_ -Remote $Remote }
        }
    }
}

Write-Host "`n[✓] Bifrost reconciliation complete." -ForegroundColor Green
