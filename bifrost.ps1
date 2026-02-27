[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Config = "C:\Bifrost\config.json",
    
    [Parameter(Mandatory=$false)]
    [bool]$Pure = $false
)

# ==========================================
# STAGE 0: PRE-FLIGHT & BOOTSTRAP
# ==========================================
Write-Host "[Stage 0: Pre-Flight Check]" -ForegroundColor Magenta

# 1. Policy Detection
$Policy = Get-ExecutionPolicy
if ($Policy -in @("Restricted", "AllSigned")) {
    Write-Host "[!] Policy is $Policy. Attempting to elevate to RemoteSigned..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    } catch {
        Write-Host "[FAIL] System Policy prevents script execution. Scoop will fail." -ForegroundColor Red
    }
}

# 2. Admin Detection
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# 3. Directory & Config Initialization
if (-not (Test-Path "C:\Bifrost")) { New-Item -Path "C:\Bifrost" -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $Config)) {
    Write-Host "[*] No config found. Generating default template at $Config" -ForegroundColor Gray
    @{ 
        users = @(@{ username = "dev-user"; fullname = "Developer"; description = "Bifrost Managed" });
        packages = @{ buckets = @("extras"); apps = @("git", "curl"); global_apps = @("7zip") };
        networking = @{ firewall = @{ enabled = $true; allowPing = $true; allowedTCPPorts = @(80, 443) } } 
    } | ConvertTo-Json -Depth 10 | Out-File $Config
}

$Data = Get-Content -Raw $Config | ConvertFrom-Json

# ==========================================
# MODULE 1: USERS (Admin Only)
# ==========================================
if ($Data.users) {
    Write-Host "`n[Module: Users]" -ForegroundColor Cyan
    if (-not $IsAdmin) {
        Write-Host "[SKIP] User management requires Administrator privileges." -ForegroundColor Red
    } else {
        foreach ($U in $Data.users) {
            if (-not (Get-LocalUser -Name $U.username -ErrorAction SilentlyContinue)) {
                Write-Host "[+] Creating User: $($U.username) (Admin must set password)" -ForegroundColor Green
                New-LocalUser -Name $U.username -FullName $U.fullname -Description $U.description -NoPassword
            } else {
                Write-Host "[*] Updating Metadata: $($U.username)" -ForegroundColor Gray
                Set-LocalUser -Name $U.username -FullName $U.fullname -Description $U.description
            }
        }
    }
}

# ==========================================
# MODULE 2: PACKAGES (SCOOP)
# ==========================================
if ($Data.packages) {
    Write-Host "`n[Module: Packages]" -ForegroundColor Cyan
    if ($Policy -eq "Restricted") {
        Write-Host "[SKIP] Scoop requires a non-restricted ExecutionPolicy." -ForegroundColor Red
    } else {
        # Bootstrap Scoop
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Host "[*] Installing Scoop..." -ForegroundColor Yellow
            irm get.scoop.sh | iex
        }

        # Sync Buckets
        foreach ($B in $Data.packages.buckets) {
            if (-not (scoop bucket list | Select-String "^$B\s")) { scoop bucket add $B }
        }

        # Sync User Apps
        foreach ($A in $Data.packages.apps) {
            if (-not (scoop list | Select-String "^$A\s")) { scoop install $A }
        }

        # Sync Global Apps
        if ($Data.packages.global_apps) {
            if ($IsAdmin) {
                foreach ($GA in $Data.packages.global_apps) {
                    if (-not (scoop list | Select-String "^$GA\s.*\[global\]")) { scoop install $GA -g }
                }
            } else {
                Write-Host "[WARN] Skipping Global Apps: Admin privileges required." -ForegroundColor Yellow
            }
        }
    }
}

# ==========================================
# MODULE 3: NETWORKING (FIREWALL)
# ==========================================
if ($Data.networking.firewall) {
    Write-Host "`n[Module: Networking]" -ForegroundColor Cyan
    if (-not $IsAdmin) {
        Write-Host "[SKIP] Firewall management requires Administrator privileges." -ForegroundColor Red
    } else {
        $FW = $Data.networking.firewall
        $Tag = "BifrostManaged"

        # Declarative Reset
        if ($Pure) {
            Write-Host "[!] Pure Mode: Purging Bifrost-managed rules..." -ForegroundColor Yellow
            Remove-NetFirewallRule -Group $Tag -ErrorAction SilentlyContinue
        }

        Set-NetFirewallProfile -All -Enabled ([bool]$FW.enabled)

        if ($FW.enabled) {
            function Add-BifrostRule {
                param($Name, $Proto, $Port, $Remote = "Any")
                $ID = "Bifrost-$Name"
                if (-not (Get-NetFirewallRule -Name $ID -ErrorAction SilentlyContinue)) {
                    New-NetFirewallRule -Name $ID -DisplayName $ID -Group $Tag -Protocol $Proto -LocalPort $Port -RemoteAddress $Remote -Action Allow
                }
            }

            if ($FW.allowPing) { Add-BifrostRule -Name "Ping" -Proto ICMPv4 -Port Any }
            if ($FW.enableRDP) { Add-BifrostRule -Name "RDP" -Proto TCP -Port 3389 }
            
            $Remote = if ($FW.tailscaleOnly) { "100.64.0.0/10" } else { "Any" }

            foreach ($P in $FW.allowedTCPPorts) { Add-BifrostRule -Name "TCP-$P" -Proto TCP -Port $P -Remote $Remote }
            foreach ($P in $FW.allowedUDPPorts) { Add-BifrostRule -Name "UDP-$P" -Proto UDP -Port $P -Remote $Remote }
        }
    }
}

Write-Host "`n[✓] Bifrost: System reconciliation complete." -ForegroundColor Green
