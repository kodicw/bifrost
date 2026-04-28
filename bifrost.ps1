# Context: [[nb:jbot:126]]
# ADR: PowerShell Idempotency and Modularity

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
        # STAGE 0: PRE-FLIGHT
        # ==========================================
        Write-BifrostLog "[Stage 0: Pre-Flight Check]" -Color Magenta

        $IsAdmin = Test-BifrostAdmin
        $Policy = Get-ExecutionPolicy
        
        if ($Policy -in @("Restricted", "AllSigned")) {
            Write-BifrostLog "Policy is $Policy. Attempting elevation..." -Color Yellow
            try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop } 
            catch { Write-BifrostLog "Policy locked by System/Domain." -Color Red }
        }

        if (-not (Test-Path "C:\Bifrost")) { 
            Write-BifrostLog "Creating Bifrost root directory..." -Color Gray
            New-Item -Path "C:\Bifrost" -ItemType Directory -Force | Out-Null 
        }

        $Data = Get-BifrostConfig -ConfigPath $Config

        # ==========================================
        # RECONCILIATION LOOP
        # ==========================================
        Sync-BifrostUsers -Users $Data.users -IsAdmin $IsAdmin
        Sync-BifrostPackages -Packages $Data.packages -IsAdmin $IsAdmin -Pure $Pure -Policy $Policy
        Sync-BifrostSystem -System $Data.system -IsAdmin $IsAdmin
        Sync-BifrostNetworking -Networking $Data.networking -IsAdmin $IsAdmin -Pure $Pure
        Sync-BifrostDownloads -Downloads $Data.downloads
        Sync-BifrostFiles -Files $Data.files
        Sync-BifrostRegistry -Registry $Data.registry
        Sync-BifrostServices -Services $Data.services -IsAdmin $IsAdmin
        Sync-BifrostScripts -Scripts $Data.scripts

        Write-BifrostLog "`n[✓] Bifrost: System reconciliation complete." -Color Green
    }
}

# ==========================================
# INTERNAL MODULES
# ==========================================

function Get-BifrostConfig {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) {
        if ($ConfigPath -match "^https?://") {
            Write-BifrostLog "Downloading remote config: $ConfigPath" -Color Gray
            try {
                $RemoteData = Invoke-WebRequest -Uri $ConfigPath -UseBasicParsing -ErrorAction Stop
                return $RemoteData.Content | ConvertFrom-Json
            } catch {
                throw "[!] FATAL: Failed to download or parse remote config from $ConfigPath"
            }
        } else {
            Write-BifrostLog "No config found. Generating sane default template..." -Color Gray
            $Default = @{ 
                users = @(@{ username = "bifrost-user"; fullname = "Local Administrator"; description = "Bifrost Managed Admin" });
                packages = @{ apps = @("git", "neovim"); buckets = @("extras") };
                networking = @{ firewall = @{ enabled = $true; allowPing = $true; allowedTCPPorts = @(22) } };
            }
            $Default | ConvertTo-Json -Depth 10 | Out-File $ConfigPath
            return $Default
        }
    } else {
        try {
            return Get-Content -Raw $ConfigPath | ConvertFrom-Json
        } catch {
            throw "[!] FATAL: Failed to parse config.json. Check for syntax errors!"
        }
    }
}

function Sync-BifrostUsers {
    param($Users, $IsAdmin)
    if (-not $Users) { return }
    Write-BifrostLog "`n[Module: Users]"
    if (-not $IsAdmin) { Write-BifrostLog "Requires Administrator privileges." -Color Red; return }

    foreach ($U in @($Users)) {
        $Existing = Get-LocalUser -Name $U.username -ErrorAction SilentlyContinue
        if ($null -eq $Existing) {
            Write-BifrostLog "Creating User: $($U.username)" -Color Green -Indent
            New-LocalUser -Name $U.username -FullName $U.fullname -Description $U.description -NoPassword | Out-Null
        } else {
            if ($Existing.FullName -ne $U.fullname -or $Existing.Description -ne $U.description) {
                Write-BifrostLog "Updating Metadata: $($U.username)" -Color Gray -Indent
                Set-LocalUser -Name $U.username -FullName $U.fullname -Description $U.description
            } else {
                Write-BifrostLog "User is correct: $($U.username)" -Color DarkGray -Indent
            }
        }
    }
}

function Sync-BifrostPackages {
    param($Packages, $IsAdmin, $Pure, $Policy)
    if (-not $Packages) { return }
    Write-BifrostLog "`n[Module: Packages]"
    if ($Policy -eq "Restricted") { Write-BifrostLog "Restricted ExecutionPolicy prevents Scoop usage." -Color Red; return }

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        if ($IsAdmin) {
            Write-BifrostLog "Cannot install Scoop as Administrator. Run in non-admin prompt first." -Color Red
            return
        } else {
            Write-BifrostLog "Installing Scoop..." -Color Yellow -Indent
            irm get.scoop.sh | iex
        }
    }

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        $ConfigBuckets = @($Packages.buckets) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { "$_".Trim().ToLower() }
        $ConfigUser = @($Packages.apps) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { "$_".Trim().ToLower() }
        $ConfigGlobal = @($Packages.global_apps) | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { "$_".Trim().ToLower() }

        $InstalledApps = scoop list | ForEach-Object { 
            if ($_ -match "^\s*(\S+)\s+\S+") { $matches[1].ToLower() } 
        } | Where-Object { $_ -ne "installed" -and $_ -ne "apps:" }

        if ($Pure) {
            Write-BifrostLog "Pure Mode: Purging unmanaged Scoop packages..." -Color Yellow -Indent
            foreach ($App in $InstalledApps) {
                if ($App -ne 'scoop' -and $ConfigUser -notcontains $App -and $ConfigGlobal -notcontains $App) {
                    Write-BifrostLog "Uninstalling orphaned app: $App" -Color Red -Indent
                    scoop uninstall $App | Out-Null
                }
            }
        }

        foreach ($B in $ConfigBuckets) {
            if (-not (scoop bucket list | Select-String "^$([regex]::Escape($B))\s")) { 
                Write-BifrostLog "Adding Bucket: $B" -Color Green -Indent
                scoop bucket add $B | Out-Null
            }
        }

        foreach ($A in $ConfigUser) {
            if ($InstalledApps -notcontains $A) { 
                Write-BifrostLog "Installing App: $A" -Color Green -Indent
                scoop install $A | Out-Null
            }
        }

        if ($IsAdmin -and $ConfigGlobal.Count -gt 0) {
            foreach ($GA in $ConfigGlobal) {
                if (-not (scoop list | Select-String "^$([regex]::Escape($GA))\s.*\[global\]")) { 
                    Write-BifrostLog "Installing Global App: $GA" -Color Green -Indent
                    scoop install $GA -g | Out-Null
                }
            }
        }
    }
}

function Sync-BifrostSystem {
    param($System, $IsAdmin)
    if (-not $System) { return }
    Write-BifrostLog "`n[Module: System]"
    if (-not $IsAdmin) { Write-BifrostLog "Requires Administrator privileges." -Color Red; return }

    foreach ($F in (@($System.features) | Where-Object { $_ })) {
        $Feature = Get-WindowsOptionalFeature -Online -FeatureName $F -ErrorAction SilentlyContinue
        if ($null -ne $Feature -and $Feature.State -ne 'Enabled') {
            Write-BifrostLog "Enabling Feature: $F" -Color Green -Indent
            Enable-WindowsOptionalFeature -Online -FeatureName $F -NoRestart | Out-Null
        }
    }

    foreach ($C in (@($System.capabilities) | Where-Object { $_ })) {
        $Cap = Get-WindowsCapability -Online -Name "$C*" -ErrorAction SilentlyContinue | Where-Object State -eq 'NotPresent'
        if ($Cap) {
            Write-BifrostLog "Adding Capability: $($Cap.Name)" -Color Green -Indent
            Add-WindowsCapability -Online -Name $Cap.Name | Out-Null
        }
    }
}

function Sync-BifrostNetworking {
    param($Networking, $IsAdmin, $Pure)
    if (-not $Networking.firewall) { return }
    Write-BifrostLog "`n[Module: Networking]"
    if (-not $IsAdmin) { Write-BifrostLog "Requires Administrator privileges." -Color Red; return }

    $FW = $Networking.firewall
    $Tag = "BifrostManaged"

    if ($Pure) {
        Write-BifrostLog "Pure Mode: Purging managed firewall rules..." -Color Yellow -Indent
        Remove-NetFirewallRule -Group $Tag -ErrorAction SilentlyContinue
    }

    $ProfileState = if ($FW.enabled) { "True" } else { "False" }
    Set-NetFirewallProfile -All -Enabled $ProfileState

    if ($FW.enabled) {
        $Rules = @()
        if ($FW.allowPing) { $Rules += @{ Name="Ping"; Proto="ICMPv4"; Port="Any" } }
        if ($FW.enableRDP) { $Rules += @{ Name="RDP"; Proto="TCP"; Port=3389 } }
        
        $Remote = if ($FW.tailscaleOnly) { "100.64.0.0/10" } else { "Any" }

        foreach ($P in (@($FW.allowedTCPPorts) | Where-Object { $_ })) { $Rules += @{ Name="TCP-$P"; Proto="TCP"; Port=$P } }
        foreach ($P in (@($FW.allowedUDPPorts) | Where-Object { $_ })) { $Rules += @{ Name="UDP-$P"; Proto="UDP"; Port=$P } }

        foreach ($R in $Rules) {
            $ID = "Bifrost-$($R.Name)"
            $Existing = Get-NetFirewallRule -Name $ID -ErrorAction SilentlyContinue
            if (-not $Existing) {
                Write-BifrostLog "Creating Rule: $ID ($($R.Proto) $($R.Port))" -Color Green -Indent
                New-NetFirewallRule -Name $ID -DisplayName $ID -Group $Tag -Protocol $R.Proto -LocalPort $R.Port -RemoteAddress $Remote -Action Allow | Out-Null
            }
        }
    }
}

function Sync-BifrostDownloads {
    param($Downloads)
    if (-not $Downloads) { return }
    Write-BifrostLog "`n[Module: Downloads]"
    foreach ($D in @($Downloads)) {
        $TargetPath = $D.path
        if (-not (Test-Path $TargetPath)) {
            Write-BifrostLog "Downloading: $($D.url) -> $TargetPath" -Color Green -Indent
            try {
                $Parent = Split-Path $TargetPath -Parent
                if (-not (Test-Path $Parent)) { New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
                Invoke-WebRequest -Uri $D.url -OutFile $TargetPath -ErrorAction Stop
            } catch {
                Write-BifrostLog "Download failed: $($D.url)" -Color Red -Indent
            }
        } else {
            Write-BifrostLog "File exists: $TargetPath" -Color DarkGray -Indent
        }
    }
}

function Sync-BifrostFiles {
    param($Files)
    if (-not $Files) { return }
    Write-BifrostLog "`n[Module: Files]"
    foreach ($F in @($Files)) {
        $TargetPath = $F.path
        $ParentDir = Split-Path $TargetPath -Parent
        if (-not (Test-Path $ParentDir)) { New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null }
        
        $Encoding = if ($F.encoding) { $F.encoding } else { "utf8" }
        $NeedsUpdate = $false

        if (-not (Test-Path $TargetPath)) {
            $NeedsUpdate = $true
        } else {
            # Use SHA256 hashing to determine if content differs
            $CurrentHash = Get-FileHash -Path $TargetPath -Algorithm SHA256
            $DesiredContentBytes = [System.Text.Encoding]::UTF8.GetBytes($F.content)
            $Stream = [System.IO.MemoryStream]::new($DesiredContentBytes)
            $DesiredHash = Get-FileHash -InputStream $Stream -Algorithm SHA256
            
            if ($CurrentHash.Hash -ne $DesiredHash.Hash) {
                $NeedsUpdate = $true
            }
        }

        if ($NeedsUpdate) {
            Write-BifrostLog "Enforcing File: $TargetPath" -Color Green -Indent
            Set-Content -Path $TargetPath -Value $F.content -Encoding $Encoding -Force
        } else {
            Write-BifrostLog "File is correct (Hash matched): $TargetPath" -Color DarkGray -Indent
        }
    }
}

function Sync-BifrostRegistry {
    param($Registry)
    if (-not $Registry) { return }
    Write-BifrostLog "`n[Module: Registry]"
    foreach ($R in @($Registry)) {
        if (-not (Test-Path $R.path)) { New-Item -Path $R.path -Force | Out-Null }
        
        $Type = if ($R.type) { $R.type } else { "String" }
        $Key = Get-Item -Path $R.path -ErrorAction SilentlyContinue
        $ExistingKind = if ($Key -and ($Key.GetValueNames() -contains $R.name)) { $Key.GetValueKind($R.name).ToString() } else { $null }
        $CurrentValue = Get-ItemProperty -Path $R.path -Name $R.name -ErrorAction SilentlyContinue

        $NeedsUpdate = $false
        if ($null -eq $CurrentValue -or $null -eq $ExistingKind) {
            $NeedsUpdate = $true
        } elseif ($CurrentValue.$($R.name) -ne $R.value) {
            $NeedsUpdate = $true
        } elseif ($ExistingKind -ne $Type) {
            # Special case for DWord/Int32 if needed, but usually they match
            $NeedsUpdate = $true
        }

        if ($NeedsUpdate) {
            Write-BifrostLog "Enforcing Registry: $($R.path)\$($R.name) (Type: $Type)" -Color Green -Indent
            Set-ItemProperty -Path $R.path -Name $R.name -Value $R.value -Type $Type -Force
        } else {
            Write-BifrostLog "Registry correct: $($R.name)" -Color DarkGray -Indent
        }
    }
}

function Sync-BifrostServices {
    param($Services, $IsAdmin)
    if (-not $Services) { return }
    Write-BifrostLog "`n[Module: Services]"
    if (-not $IsAdmin) { Write-BifrostLog "Requires Administrator privileges." -Color Red; return }

    foreach ($S in @($Services)) {
        $Svc = Get-Service -Name $S.name -ErrorAction SilentlyContinue
        if ($Svc) {
            $Changed = $false
            if ($S.startup -and $Svc.StartType -ne $S.startup) { 
                Write-BifrostLog "Updating StartupType: $($S.name) -> $($S.startup)" -Color Gray -Indent
                Set-Service -Name $S.name -StartupType $S.startup
                $Changed = $true
            }
            
            if ($S.state -eq "Running" -and $Svc.Status -ne "Running") {
                Write-BifrostLog "Starting Service: $($S.name)" -Color Green -Indent
                Start-Service -Name $S.name
                $Changed = $true
            } elseif ($S.state -eq "Stopped" -and $Svc.Status -ne "Stopped") {
                Write-BifrostLog "Stopping Service: $($S.name)" -Color Red -Indent
                Stop-Service -Name $S.name
                $Changed = $true
            } 
            
            if (-not $Changed) {
                Write-BifrostLog "Service correct: $($S.name)" -Color DarkGray -Indent
            }
        } else {
            Write-BifrostLog "Service NOT FOUND: $($S.name)" -Color Red -Indent
        }
    }
}

function Sync-BifrostScripts {
    param($Scripts)
    if (-not $Scripts) { return }
    Write-BifrostLog "`n[Module: Scripts]"
    foreach ($S in @($Scripts)) {
        Write-BifrostLog "Executing: $($S.name)" -Color Gray -Indent
        if ($S.command) { & ([scriptblock]::Create($S.command)) }
        elseif ($S.path -and (Test-Path $S.path)) { & $S.path }
    }
}

function Write-BifrostLog {
    param([string]$Message, [string]$Color = "Cyan", [switch]$Indent)
    $Prefix = if ($Indent) { "  -> " } else { "" }
    Write-Host "$Prefix$Message" -ForegroundColor $Color
}

function Test-BifrostAdmin {
    try {
        return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}
