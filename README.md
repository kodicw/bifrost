# 🌈 Bifrost: Declarative Windows Firewall

Bifrost is a NixOS-inspired firewall manager for Windows. It allows you to manage your network security using a declarative JSON configuration rather than imperative CLI commands or the Windows GUI.



## 📂 System Structure
* **`Sync-Bifrost.ps1`**: The logic engine. It reads the config and reconciles the Windows Firewall state.
* **`C:\Bifrost\firewall.json`**: The local "Source of Truth" for your port configurations.

---

## 🛠 Setup & Installation

1. **Create the Bridge Directory**:
   Open PowerShell as **Administrator** and run:
   ```powershell
   New-Item -Path "C:\Bifrost" -ItemType Directory -Force
