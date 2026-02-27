


[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Config = "C:\Bifrost\config.json",
    
    [Parameter(Mandatory=$false)]
    [bool]$Pure = $false
)

# Force TLS 1.2 for web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==========================================
# STAGE 0: PRE-FLIGHT & BOOTSTRAP
# ==========================================
Write-Host "[Stage 0: Pre-Flight Check]" -ForegroundColor Magenta

$Policy = Get-ExecutionPolicy
if ($Policy -in @("Restricted", "AllSigned")) {
    Write-Host "[!] Policy is $Policy. Elevating to RemoteSigned..." -ForegroundColor Yellow
    try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop } 
    catch { Write-Host "[FAIL] Policy locked by System/Domain." -ForegroundColor Red }
}

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not (Test-Path "C:\Bifrost")) { New-Item -Path "C:\Bifrost" -ItemType Directory -Force | Out-Null }

if (-not (Test-Path $Config)) {
    Write-Host "[*] No config found. Generating sane default template..." -ForegroundColor Gray
    @{ 
        users = @(@{ username = "admin-user"; fullname = "Local Administrator"; description = "Bifrost Managed Admin" });
        packages = @{ 
            buckets = @("extras", "non-portable"); 
            apps = @("git", "curl", "vscode"); 
            global_apps = @("7zip", "powertoys") 
        };
        system = @{
            features = @("Microsoft-Windows-Subsystem-Linux");
            capabilities = @("OpenSSH.Client")
        };
        networking = @{ 
            firewall = @{ 
                enabled = $true; allowPing = $true; enableRDP = $false; tailscaleOnly = $false; 
                allowedTCPPorts = @(80, 443); allowedUDPPorts = @(); 
                allowedTCPPortRanges = @(); allowedUDPPortRanges = @()
            } 
        } 
    } | ConvertTo-Json -Depth 10 | Out-File $Config
}

try {
    $Data = Get-Content -Raw $Config | ConvertFrom-Json
} catch {
    Write-Host "[!] FATAL: Failed to parse config.json. Check for missing quotes or trailing commas!" -ForegroundColor Red
    exit 1
}

# ==========================================
# MODULE 1: USERS (Admin Only)
# ==========================================
if ($Data.users) {
    Write-Host "`n[Module: Users]" -ForegroundColor Cyan
    if (-not $IsAdmin) { Write-Host "[SKIP] Requires Administrator privileges." -ForegroundColor Red } 
    else {
        foreach ($U in @($Data.users)) {
            $Exists = $null -ne (Get-LocalUser -Name $U.username -ErrorAction SilentlyContinue)
            if (-not $Exists) {
                Write-Host "[+] Creating User: $($U.username) (Admin must set password)" -ForegroundColor Green
                New-LocalUser -Name $U.username -FullName $U.fullname -Description $U.description -NoPassword | Out-Null
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
    if ($Policy -eq "Restricted") { Write-Host "[SKIP] Restricted ExecutionPolicy." -ForegroundColor Red } 
    else {
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Host "[*] Installing Scoop (Bypassing Admin Check)..." -ForegroundColor Yellow
            iex "& {$(irm get.scoop.sh)} -RunAsAdmin"
        }

        foreach ($B in @($Data.packages.buckets)) {
            if (-not (scoop bucket list | Select-String "^$B\s")) { scoop bucket add $B }
        }

        foreach ($A in @($Data.packages.apps)) {
            if (-not (scoop list | Select-String "^$A\s")) { scoop install $A }
        }

        if ($Data.packages.global_apps) {
            if ($IsAdmin) {
                foreach ($GA in @($Data.packages.global_apps)) {
                    if (-not (scoop list | Select-String "^$GA\s.*\[global\]")) { scoop install $GA -g }
                }
            } else { Write-Host "[WARN] Skipping Global Apps (Requires Admin)." -ForegroundColor Yellow }
        }
    }
}

# ==========================================
# MODULE 3: SYSTEM FEATURES
# ==========================================
if ($Data.system) {
    Write-Host "`n[Module: System]" -ForegroundColor Cyan
    if (-not $IsAdmin) { Write-Host "[SKIP] System features require Administrator privileges." -ForegroundColor Red } 
    else {
        foreach ($F in @($Data.system.features)) {
            $Feature = Get-WindowsOptionalFeature -Online -FeatureName $F -ErrorAction SilentlyContinue
            if ($null -ne $Feature -and $Feature.State -ne 'Enabled') {
                Write-Host "[+] Enabling Feature: $F" -ForegroundColor Green
                Enable-WindowsOptionalFeature -Online -FeatureName $F -NoRestart | Out-Null
            }
        }

        foreach ($C in @($Data.system.capabilities)) {
            $Cap = Get-WindowsCapability -Online -Name "$C*" -ErrorAction SilentlyContinue | Where-Object State -eq 'NotPresent'
            if ($Cap) {
                Write-Host "[+] Adding Capability: $($Cap.Name)" -ForegroundColor Green
                Add-WindowsCapability -Online -Name $Cap.Name | Out-Null
            }
        }
    }
}

# ==========================================
# MODULE 4: NETWORKING (FIREWALL)
# ==========================================
if ($Data.networking.firewall) {
    Write-Host "`n[Module: Networking]" -ForegroundColor Cyan
    if (-not $IsAdmin) { Write-Host "[SKIP] Requires Administrator privileges." -ForegroundColor Red } 
    else {
        $FW = $Data.networking.firewall
        $Tag = "BifrostManaged"

        if ($Pure) {
            Write-Host "[!] Pure Mode: Purging Bifrost-managed rules..." -ForegroundColor Yellow
            Remove-NetFirewallRule -Group $Tag -ErrorAction SilentlyContinue
        }

            $ProfileState = if ($FW.enabled) { "True" } else { "False" }
            Set-NetFirewallProfile -All -Enabled $ProfileState
        if ($FW.enabled) {
            function Add-BifrostRule {
                param($Name, $Proto, $Port, $Remote = "Any")
                $ID = "Bifrost-$Name"
                if (-not (Get-NetFirewallRule -Name $ID -ErrorAction SilentlyContinue)) {
                    New-NetFirewallRule -Name $ID -DisplayName $ID -Group $Tag -Protocol $Proto -LocalPort $Port -RemoteAddress $Remote -Action Allow | Out-Null
                }
            }

            if ($FW.allowPing) { Add-BifrostRule -Name "Ping" -Proto ICMPv4 -Port Any }
            if ($FW.enableRDP) { Add-BifrostRule -Name "RDP" -Proto TCP -Port 3389 }
            
            $Remote = if ($FW.tailscaleOnly) { "100.64.0.0/10" } else { "Any" }

            foreach ($P in @($FW.allowedTCPPorts)) { Add-BifrostRule -Name "TCP-$P" -Proto TCP -Port $P -Remote $Remote }
            foreach ($P in @($FW.allowedUDPPorts)) { Add-BifrostRule -Name "UDP-$P" -Proto UDP -Port $P -Remote $Remote }
            
            foreach ($R in @($FW.allowedTCPPortRanges)) { Add-BifrostRule -Name "TCP-Range-$R" -Proto TCP -Port $R -Remote $Remote }
            foreach ($R in @($FW.allowedUDPPortRanges)) { Add-BifrostRule -Name "UDP-Range-$R" -Proto UDP -Port $R -Remote $Remote }
        }
    }
}

Write-Host "`n[✓] Bifrost: System reconciliation complete." -ForegroundColor Green
