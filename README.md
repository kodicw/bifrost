# 🌈 Bifrost: Declarative Windows Firewall

Bifrost is a NixOS-inspired firewall manager for Windows. It provides a single JSON source of truth for your network security posture.



## 📂 System Structure
* **`Sync-Bifrost.ps1`**: The logic engine.
* **`C:\Bifrost\firewall.json`**: Your declarative configuration.

## 📄 Full Configuration Example
This example includes all modern toggles for a power user.

```json
{
    "users": [
        {
            "username": "kodi",
            "fullname": "Kodi Walls",
            "description": "Primary Admin - Managed by Bifrost"
        },
        {
            "username": "guest-dev",
            "fullname": "Guest Developer",
            "description": "Restricted Access Account"
        }
    ],
    "packages": {
        "buckets": [
            "extras",
            "non-portable",
            "versions",
            "nerd-fonts"
        ],
        "apps": [
            "git",
            "neovim",
            "curl",
            "fastfetch",
            "starship",
            "fzf",
            "zoxide",
            "direnv"
        ],
        "global_apps": [
            "7zip",
            "dark",
            "tailscale",
            "powertoys"
        ]
    },
    "networking": {
        "firewall": {
            "enabled": true,
            "allowPing": true,
            "enableRDP": false,
            "tailscaleOnly": true,
            "allowedTCPPorts": [80, 443, 3000, 8080],
            "allowedUDPPorts": [41641, 51820],
            "allowedTCPPortRanges": ["9000-9005"]
        }
    }
}
```
```powershell
iex "& { $(irm "[https://raw.githubusercontent.com/kodicw/bifrost/main/bifrost.ps1](https://raw.githubusercontent.com/kodicw/bifrost/main/bifrost.ps1)") }"
```
