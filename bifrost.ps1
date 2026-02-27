function Invoke-Bifrost {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$Config = "C:\Bifrost\config.json",
        
        [Parameter(Mandatory=$false)]
        [switch]$Pure
    )

    process {
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
                users = @(@{ username = "bifrost-user"; fullname = "Local Administrator"; description = "Bifrost Managed Admin" });
                packages = @{ 
                    apps = @("git", "edit"); 
                };
                networking = @{ 
                    firewall = @{ 
                        enabled = $true; allowPing = $true; enableRDP = $false; tailscaleOnly = $false; 
                        allowedTCPPorts = @(22); allowedUDPPorts = @(); 
                        allowedTCPPortRanges = @(); allowedUDPPortRanges = @()
                    } 
                };
            } | ConvertTo-Json -Depth 10 | Out-File $Config
        }

        try {
            $Data = Get-Content -Raw $Config | ConvertFrom-Json
        } catch {
            throw "[!] FATAL: Failed to parse config.json. Check for missing quotes or trailing commas!"
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
                    if ($IsAdmin) {
                        Write-Host "[!] Cannot install Scoop as Administrator. Please run this script in a non-admin prompt first to install Scoop." -ForegroundColor Red
                    } else {
                        Write-Host "[*] Installing Scoop..." -ForegroundColor Yellow
                        irm get.scoop.sh | iex
                    }
                }

                if (Get-Command scoop -ErrorAction SilentlyContinue) {
                    
                    [string[]]$ConfigBuckets = @($Data.packages.buckets) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { "$_".Trim().ToLower() }
                    [string[]]$ConfigUser = @($Data.packages.apps) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { "$_".Trim().ToLower() }
                    [string[]]$ConfigGlobal = @($Data.packages.global_apps) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { "$_".Trim().ToLower() }

                    if ($Pure.IsPresent) {
                        Write-Host "[!] Pure Mode: Purging unmanaged Scoop packages..." -ForegroundColor Yellow
                        
                        if (Test-Path "$env:USERPROFILE\scoop\apps") {
                            $InstalledUser = Get-ChildItem "$env:USERPROFILE\scoop\apps" -Directory | Select-Object -ExpandProperty Name | ForEach-Object { $_.ToLower() }
                            foreach ($App in $InstalledUser) {
                                if ($App -ne 'scoop' -and $ConfigUser -notcontains $App) {
                                    Write-Host "  [-] Uninstalling orphaned user app: $App" -ForegroundColor Red
                                    scoop uninstall $App | Out-Null
                                }
                            }
                        }

                        if ($IsAdmin -and (Test-Path "$env:ProgramData\scoop\apps")) {
                            $InstalledGlobal = Get-ChildItem "$env:ProgramData\scoop\apps" -Directory | Select-Object -ExpandProperty Name | ForEach-Object { $_.ToLower() }
                            foreach ($App in $InstalledGlobal) {
                                if ($App -ne 'scoop' -and $ConfigGlobal -notcontains $App) {
                                    Write-Host "  [-] Uninstalling orphaned global app: $App" -ForegroundColor Red
                                    scoop uninstall $App -g | Out-Null
                                }
                            }
                        }
                    }

                    foreach ($B in $ConfigBuckets) {
                        if (-not (scoop bucket list | Select-String "^$B\s")) { scoop bucket add $B }
                    }

                    foreach ($A in $ConfigUser) {
                        if (-not (scoop list | Select-String "^$A\s")) { scoop install $A }
                    }

                    if ($IsAdmin) {
                        foreach ($GA in $ConfigGlobal) {
                            if (-not (scoop list | Select-String "^$GA\s.*\[global\]")) { scoop install $GA -g }
                        }
                    } elseif ($ConfigGlobal.Count -gt 0) { 
                        Write-Host "[WARN] Skipping Global Apps (Requires Admin)." -ForegroundColor Yellow 
                    }
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

                if ($Pure.IsPresent) {
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
                            Write-Host "  -> [+] Creating Rule: $ID ($Proto $Port -> $Remote)" -ForegroundColor Green
                            New-NetFirewallRule -Name $ID -DisplayName $ID -Group $Tag -Protocol $Proto -LocalPort $Port -RemoteAddress $Remote -Action Allow | Out-Null
                        } else {
                            Write-Host "  -> [~] Rule Exists: $ID" -ForegroundColor DarkGray
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

        # ==========================================
        # MODULE 5: FILES (Declarative State)
        # ==========================================
        if ($Data.files) {
            Write-Host "`n[Module: Files]" -ForegroundColor Cyan
            foreach ($F in @($Data.files)) {
                $TargetPath = $F.path
                $ParentDir = Split-Path $TargetPath -Parent
                
                if (-not (Test-Path $ParentDir)) {
                    Write-Host "  [+] Creating Directory: $ParentDir" -ForegroundColor Green
                    New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null
                }
                
                $Encoding = if ($F.encoding) { $F.encoding } else { "utf8" }
                Write-Host "  [*] Enforcing File State: $TargetPath" -ForegroundColor Gray
                Set-Content -Path $TargetPath -Value $F.content -Encoding $Encoding -Force
            }
        }

        Write-Host "`n[✓] Bifrost: System reconciliation complete." -ForegroundColor Green
    }
}
