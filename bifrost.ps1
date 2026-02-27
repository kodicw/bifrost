[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Config = "C:\Bifrost\firewall.json"
)

# --- RAW DATA: Load Config ---
if (-not (Test-Path $Config)) {
    Write-Host "[!] Error: Configuration not found at $Config" -ForegroundColor Red
    Write-Host "[i] Create the directory: New-Item -Path 'C:\Bifrost' -ItemType Directory"
    exit 1
}

try {
    $Data = Get-Content -Raw $Config | ConvertFrom-Json
} catch {
    Write-Host "[!] Error: Failed to parse JSON in $Config. Check your syntax!" -ForegroundColor Red
    exit 1
}

# --- LOGIC: The "Nix-ish" Declarative Sync ---
function Apply-BifrostState {
    param($State)

    $Tag = "BifrostManaged"

    # 1. Reset: Purge existing 'Bifrost' rules to prevent state drift
    Remove-NetFirewallRule -Group $Tag -ErrorAction SilentlyContinue

    # 2. Set Profile State
    $EnabledState = if ($State.Enabled) { "True" } else { "False" }
    Set-NetFirewallProfile -All -Enabled $EnabledState

    if ($State.Enabled) {
        # 3. Batch Apply TCP
        if ($State.AllowedTCPPorts) {
            $State.AllowedTCPPorts | ForEach-Object {
                New-NetFirewallRule -DisplayName "Bifrost-TCP-$_" -Group $Tag -Protocol TCP -LocalPort $_ -Action Allow
            }
        }

        # 4. Batch Apply UDP
        if ($State.AllowedUDPPorts) {
            $State.AllowedUDPPorts | ForEach-Object {
                New-NetFirewallRule -DisplayName "Bifrost-UDP-$_" -Group $Tag -Protocol UDP -LocalPort $_ -Action Allow
            }
        }
    }

    Write-Host "Success: $Config applied to Windows Firewall." -ForegroundColor Cyan
}

Apply-BifrostState -State $Data
