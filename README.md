# 🌈 Bifrost: Declarative Windows State Manager

Bifrost is a NixOS-inspired, declarative configuration manager for Windows. It provides a single JSON source of truth for your system's users, packages, OS features, and firewall posture.



## ⚠️ Warnings
Before running this, understand these platform limitations:
* **Scoop Installation**: Scoop explicitly blocks installation from an elevated prompt. You **must** run Bifrost as a standard user first to install Scoop, then run it as an Administrator to process Global Apps, System Features, and Networking.
* **User Passwords**: Bifrost creates users with the `-NoPassword` flag to prevent storing credentials in plain text. An Administrator must manually set the password (`net user <username> *`) before the account can log in.
* **Reboots**: Windows Features (like WSL or IIS) often require a reboot. Bifrost passes `-NoRestart` to prevent mid-script crashes. You are responsible for rebooting later.

## 🚀 Quick Start (One-Liner)

Run this from a PowerShell prompt to bootstrap your system directly from GitHub:

```powershell
iex "& { $(irm 'https://raw.githubusercontent.com/kodicw/bifrost/main/bifrost.ps1') }"

```

*Note: If `C:\Bifrost\config.json` does not exist, the script will automatically generate a sane default template for you on the first run.*

## 📂 System Structure

* **`bifrost.ps1`**: The logic engine that parses your config and enforces system state.
* **`C:\Bifrost\config.json`**: Your declarative configuration.

## 📄 Configuration Modules

Bifrost reads `C:\Bifrost\config.json`. The configuration is divided into four distinct modules:

* **Users**: Manages local Windows accounts.
* Controls `username`, `fullname`, and `description`.


* **Packages**: Manages software via Scoop.
* `buckets`: Repositories to add (e.g., `extras`, `non-portable`).
* `apps`: Installed to your local user profile (`%USERPROFILE%\scoop`).
* `global_apps`: Installed machine-wide (`C:\ProgramData\scoop`). Requires Admin.


* **System**: Manages Windows OS components.
* `features`: Legacy Windows Optional Features (e.g., `Microsoft-Windows-Subsystem-Linux`).
* `capabilities`: Modern Features on Demand (e.g., `OpenSSH.Client`).


* **Networking**: Manages the Windows Firewall profile.
* `enabled`: Master toggle for the firewall profile.
* `allowPing` / `enableRDP`: Quick toggles for ICMPv4 and Port 3389.
* `tailscaleOnly`: If `true`, restricts all defined ports strictly to the `100.64.0.0/10` subnet.
* `allowedTCPPorts` / `allowedUDPPorts`: Explicit port openings.



## 🛠 Example `config.json`

```json
{
  "users": [
    {
      "username": "admin-user",
      "fullname": "Local Administrator",
      "description": "Bifrost Managed Admin"
    }
  ],
  "packages": {
    "buckets": [
      "extras",
      "non-portable"
    ],
    "apps": [
      "git",
      "curl",
      "vscode"
    ],
    "global_apps": [
      "7zip",
      "powertoys"
    ]
  },
  "system": {
    "features": [
      "Microsoft-Windows-Subsystem-Linux"
    ],
    "capabilities": [
      "OpenSSH.Client"
    ]
  },
  "networking": {
    "firewall": {
      "enabled": true,
      "allowPing": true,
      "enableRDP": false,
      "tailscaleOnly": false,
      "allowedTCPPorts": [80, 443],
      "allowedUDPPorts": [],
      "allowedTCPPortRanges": [],
      "allowedUDPPortRanges": []
    }
  }
}

```

## 🔄 Execution Modes

* **Impure (Default)**: Applies the JSON state but leaves existing, unmanaged rules and software alone.
* **Pure Mode**: Wipes all firewall rules tagged with `BifrostManaged` before applying the current JSON state.

**To run in Pure Mode from GitHub:**

```powershell
iex "& { $(irm '[https://raw.githubusercontent.com/kodicw/bifrost/main/bifrost.ps1](https://raw.githubusercontent.com/kodicw/bifrost/main/bifrost.ps1)') } -Pure $true"

```

## 📊 Raw Data: How the Firewall Works

Bifrost tags every firewall rule it creates with the `-Group "BifrostManaged"` property. This allows the script to safely identify, audit, and purge its own rules without breaking critical Windows system rules or dynamic rules created by games and software.
your JSON syntax on every push?

```
