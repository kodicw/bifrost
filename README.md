# 🌈 Bifrost: Declarative Windows Firewall

Bifrost is a NixOS-inspired firewall manager for Windows. It provides a single JSON source of truth for your network security posture.



## 📂 System Structure
* **`Sync-Bifrost.ps1`**: The logic engine.
* **`C:\Bifrost\firewall.json`**: Your declarative configuration.

## 📄 Full Configuration Example
This example includes all modern toggles for a power user.

```json
{
    "Enabled": true,
    "Pure": false,
    "AllowPing": true,
    "EnableRDP": false,
    "TailscaleOnly": false,
    "AllowedTCPPorts": [80, 443],
    "AllowedUDPPorts": [41641, 51820],
    "AllowedTCPPortRanges": ["8000-8010"]
}
```
```powershell
iex "& { $(irm "[https://raw.githubusercontent.com/kodicw/bifrost/main/bifrost.ps1](https://raw.githubusercontent.com/kodicw/bifrost/main/bifrost.ps1)") }"
```
