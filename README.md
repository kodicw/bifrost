# 👻 Bifrost: Declarative Windows State Manager

Bifrost is a NixOS-inspired, declarative configuration manager for Windows. It provides a single JSON source of truth for your system's users, packages, OS features, and firewall posture.



## ⚠️ Warnings
Before running this, understand these platform limitations:
* **Scoop Installation**: Scoop explicitly blocks installation from an elevated prompt. You **must** run Bifrost as a standard user first to install Scoop, then run it as an Administrator to process Global Apps, System Features, and Networking.
* **User Passwords**: Bifrost creates users with the `-NoPassword` flag to prevent storing credentials in plain text. An Administrator must manually set the password (`net user <username> *`) before the account can log in.
* **Reboots**: Windows Features (like WSL or IIS) often require a reboot. Bifrost passes `-NoRestart` to prevent mid-script crashes. You are responsible for rebooting later.
* **Bifrost currently lacks a native lock file implementation.**
## 🚀 Quick Start (One-Liner)

Run this from a PowerShell prompt to bootstrap your system directly from GitHub:

```powershell
irm 'https://raw.githubusercontent.com/kodicw/bifrost/develop/bifrost.ps1' | iex; Invoke-Bifrost
```

**Remote Configuration**: You can also point Bifrost directly to a remote JSON file (e.g., a GitHub Gist or your own repository):

```powershell
irm '...' | iex; Invoke-Bifrost -Config 'https://raw.githubusercontent.com/user/repo/develop/my-config.json'
```

*Note: If `C:\Bifrost\config.json` does not exist and no remote URL is provided, the script will automatically generate a sane default template for you on the first run.*

## 📂 System Structure

* **`bifrost.ps1`**: The logic engine that parses your config and enforces system state.
* **`C:\Bifrost\config.json`**: Your declarative configuration.

## 📄 Configuration Modules

Bifrost reads `C:\Bifrost\config.json`. The configuration is divided into several modules:

* **Users**: Manages local Windows accounts.
    * `username`: Local account name.
    * `fullname`: Display name.
    * `description`: Account description.

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

* **Downloads**: Ensures files exist on disk from remote URLs.
    * `url`: Source URL.
    * `path`: Destination path.

* **Files**: Declaratively manages file content.
    * `path`: Destination path.
    * `content`: Literal text content.
    * `encoding`: Optional encoding (defaults to `utf8`).

* **Registry**: Manages Windows Registry keys and values.
    * `path`: Registry path (e.g., `HKCU:\Software\MyApp`).
    * `name`: Name of the registry value.
    * `value`: Value to set.
    * `type`: Optional value type (e.g., `DWord`, `String`, `Binary`). Defaults to `String`.

* **Services**: Manages Windows System Services.
    * `name`: Service identifier.
    * `state`: Desired state (`Running` or `Stopped`).
    * `startup`: Startup type (`Automatic`, `Manual`, `Disabled`).

* **Scripts**: Runs arbitrary PowerShell commands or scripts.
    * `name`: Descriptive name for the task.
    * `command`: Inline PowerShell command.
    * `path`: Path to an existing script file.

## 📊 How the Firewall Works

Bifrost tags every firewall rule it creates with the `-Group "BifrostManaged"` property. This allows the script to safely identify, audit, and purge its own rules without breaking critical Windows system rules or dynamic rules created by games and software.

## 🔄 Execution Modes

* **Impure (Default)**: Applies the JSON state but leaves existing, unmanaged rules and software alone.
* **Pure Mode**: Wipes all firewall rules tagged with `BifrostManaged` before applying the current JSON state.

## 🐳 Container Host Configuration

Bifrost is ideal for bootstrapping Windows container hosts for use with projects like [Imperative Containment](https://github.com/kodicw/imperative-containment). A minimal configuration can enable the `Containers` feature, install Docker via Scoop, and ensure SSH is available for remote management.

**Example `container-host.json`**:
```json
{
  "system": {
    "features": ["Containers", "Microsoft-Hyper-V"],
    "capabilities": ["OpenSSH.Server"]
  },
  "packages": {
    "apps": ["docker"]
  },
  "services": [
    { "name": "docker", "state": "Running", "startup": "Automatic" },
    { "name": "sshd", "state": "Running", "startup": "Automatic" }
  ]
}
```

## 🧪 CI Validation

Want to validate your JSON syntax on every push? Add a GitHub Action to your repository to ensure your `config.json` remains valid.

