
BeforeAll {
    # Define placeholders for Windows-specific commands so they can be mocked on Linux
    $WindowsCommands = @(
        "Get-LocalUser", "New-LocalUser", "Set-LocalUser",
        "Get-Service", "Start-Service", "Stop-Service", "Set-Service",
        "Get-NetFirewallRule", "New-NetFirewallRule", "Remove-NetFirewallRule", "Set-NetFirewallProfile",
        "Get-WindowsOptionalFeature", "Enable-WindowsOptionalFeature",
        "Get-WindowsCapability", "Add-WindowsCapability",
        "Get-ItemProperty", "Set-ItemProperty", "scoop", "Get-Item", "Get-FileHash", "Invoke-WebRequest"
    )

    # These exist on Linux but with different parameter sets or providers
    $ForceOverride = @("Set-ItemProperty", "Get-ItemProperty", "Get-Item", "Get-FileHash", "Invoke-WebRequest")

    foreach ($Cmd in $WindowsCommands) {
        if ($Cmd -in $ForceOverride -or -not (Get-Command $Cmd -ErrorAction SilentlyContinue)) {
            $scriptBlock = [scriptblock]::Create("param([Parameter(ValueFromRemainingArguments)]`$rest) ")
            # Use Force to overwrite existing cmdlets with functions
            New-Item -Path "function:Global:$Cmd" -Value $scriptBlock -Force | Out-Null
        }
    }

    . $PSScriptRoot/../bifrost.ps1
}

Describe "Bifrost Sync Modules" {
    
    Context "Sync-BifrostUsers" {
        It "Should create user if it doesn't exist" {
            Mock Get-LocalUser { return $null }
            Mock New-LocalUser { }
            Mock Write-BifrostLog { }
            
            $Users = @(@{ username = "testuser"; fullname = "Test User"; description = "Test Desc" })
            Sync-BifrostUsers -Users $Users -IsAdmin $true | Out-Null
            
            Assert-MockCalled New-LocalUser -Exactly 1
        }

        It "Should update user if metadata differs" {
            $ExistingUser = [PSCustomObject]@{ Name = "testuser"; FullName = "Old Name"; Description = "Old Desc" }
            Mock Get-LocalUser { return $ExistingUser }
            Mock Set-LocalUser { }
            Mock Write-BifrostLog { }
            
            $Users = @(@{ username = "testuser"; fullname = "New Name"; description = "New Desc" })
            Sync-BifrostUsers -Users $Users -IsAdmin $true | Out-Null
            
            Assert-MockCalled Set-LocalUser -Exactly 1
        }
    }

    Context "Sync-BifrostPackages" {
        It "Should add buckets and install apps" {
            Mock Get-Command { return $true }
            Mock scoop { 
                param([Parameter(ValueFromRemainingArguments)]$rest) 
            }
            Mock Write-BifrostLog { }

            $Packages = @{ buckets = @("extras"); apps = @("git") }
            Sync-BifrostPackages -Packages $Packages -IsAdmin $false -Pure $false -Policy "RemoteSigned" | Out-Null

            # scoop bucket list (1) + scoop bucket add (1) + scoop list (1) + scoop install (1) = 4 calls
            Assert-MockCalled scoop -Times 4 -Exactly
        }

        It "Should purge unmanaged apps in Pure mode" {
            Mock Get-Command { return $true }
            Mock scoop { 
                param([Parameter(ValueFromRemainingArguments)]$rest)
                if ($rest[0] -eq "list") { return "Installed apps:", "git 2.30.0", "unmanaged-app 1.0.0" }
                return $null
            }
            Mock Write-BifrostLog { }

            $Packages = @{ apps = @("git") }
            Sync-BifrostPackages -Packages $Packages -IsAdmin $false -Pure $true -Policy "RemoteSigned" | Out-Null

            # Should call 'scoop uninstall unmanaged-app'
            Assert-MockCalled scoop -ParameterFilter { $rest[0] -eq "uninstall" -and $rest[1] -eq "unmanaged-app" } -Exactly 1
        }

        It "Should ignore scoop headers in messy list output" {
            Mock Get-Command { return $true }
            Mock scoop { 
                param([Parameter(ValueFromRemainingArguments)]$rest)
                if ($rest[0] -eq "list") { return "Installed apps (C:\scoop):", "---", "git 2.30.0" }
                return $null
            }
            Mock Write-BifrostLog { }

            $Packages = @{ apps = @("git") }
            # If git is correctly identified as installed, scoop install git should NOT be called
            Sync-BifrostPackages -Packages $Packages -IsAdmin $false -Pure $false -Policy "RemoteSigned" | Out-Null
            
            Assert-MockCalled scoop -ParameterFilter { $rest[0] -eq "install" -and $rest[1] -eq "git" } -Exactly 0
        }

        It "Should handle regex special characters in bucket names" {
            Mock Get-Command { return $true }
            Mock scoop { 
                param([Parameter(ValueFromRemainingArguments)]$rest)
                if ($rest[0] -eq "bucket" -and $rest[1] -eq "list") { return "extras" }
                return $null
            }
            Mock Write-BifrostLog { }

            $Packages = @{ buckets = @("my.bucket+") }
            Sync-BifrostPackages -Packages $Packages -IsAdmin $false -Pure $false -Policy "RemoteSigned" | Out-Null

            # Should call 'scoop bucket add my.bucket+'
            Assert-MockCalled scoop -ParameterFilter { $rest[0] -eq "bucket" -and $rest[1] -eq "add" -and $rest[2] -eq "my.bucket+" } -Exactly 1
        }
    }

    Context "Sync-BifrostSystem" {
        It "Should enable optional features if disabled" {
            Mock Get-WindowsOptionalFeature { return [PSCustomObject]@{ State = "Disabled" } }
            Mock Enable-WindowsOptionalFeature { }
            Mock Write-BifrostLog { }

            Sync-BifrostSystem -System @{ features = @("NetFx3") } -IsAdmin $true | Out-Null

            Assert-MockCalled Enable-WindowsOptionalFeature -Exactly 1
        }

        It "Should handle null feature arrays gracefully" {
            Mock Write-BifrostLog { }
            Sync-BifrostSystem -System @{ features = $null } -IsAdmin $true | Out-Null
            # Should not throw
        }
    }

    Context "Sync-BifrostDownloads" {
        It "Should download if file missing" {
            Mock Test-Path { return $false }
            Mock New-Item { }
            Mock Invoke-WebRequest { }
            Mock Write-BifrostLog { }

            Sync-BifrostDownloads -Downloads @(@{ url="http://test"; path="C:\test.bin" }) | Out-Null
            
            Assert-MockCalled Invoke-WebRequest -Exactly 1
        }

        It "Should skip if file exists and no hash provided" {
            Mock Test-Path { return $true }
            Mock Invoke-WebRequest { }
            Mock Write-BifrostLog { }

            Sync-BifrostDownloads -Downloads @(@{ url="http://test"; path="C:\test.bin" }) | Out-Null
            
            Assert-MockCalled Invoke-WebRequest -Exactly 0
        }

        It "Should re-download if hash mismatches" {
            Mock Test-Path { return $true }
            Mock Get-FileHash { return [PSCustomObject]@{ Hash = "WRONG_HASH" } }
            Mock Invoke-WebRequest { }
            Mock Write-BifrostLog { }

            $D = @(@{ url="http://test"; path="C:\test.bin"; hash="RIGHT_HASH" })
            Sync-BifrostDownloads -Downloads $D | Out-Null
            
            Assert-MockCalled Invoke-WebRequest -Exactly 1
        }

        It "Should skip if hash matches" {
            Mock Test-Path { return $true }
            Mock Get-FileHash { return [PSCustomObject]@{ Hash = "RIGHT_HASH" } }
            Mock Invoke-WebRequest { }
            Mock Write-BifrostLog { }

            $D = @(@{ url="http://test"; path="C:\test.bin"; hash="RIGHT_HASH" })
            Sync-BifrostDownloads -Downloads $D | Out-Null
            
            Assert-MockCalled Invoke-WebRequest -Exactly 0
        }
    }

    Context "Sync-BifrostFiles" {
        It "Should update file if content differs" {
            Mock Test-Path { return $true }
            Mock Get-FileHash { 
                param([Parameter(ValueFromRemainingArguments)]$rest)
                # Count calls to simulate different hashes
                if ($global:hashCallCount -eq 0) { 
                    $global:hashCallCount++
                    return [PSCustomObject]@{ Hash = "OLD_HASH" } 
                }
                return [PSCustomObject]@{ Hash = "NEW_HASH" }
            }
            Mock Set-Content { }
            Mock Write-BifrostLog { }

            $global:hashCallCount = 0
            Sync-BifrostFiles -Files @(@{ path="C:\test.txt"; content="New Content" }) | Out-Null
            
            Assert-MockCalled Set-Content -Exactly 1
        }

        It "Should skip file update if content matches" {
            Mock Test-Path { return $true }
            Mock Get-FileHash { return [PSCustomObject]@{ Hash = "SAME_HASH" } }
            Mock Set-Content { }
            Mock Write-BifrostLog { }

            Sync-BifrostFiles -Files @(@{ path="C:\test.txt"; content="Same Content" }) | Out-Null
            
            Assert-MockCalled Set-Content -Exactly 0
        }
    }

    Context "Sync-BifrostRegistry" {
        It "Should set registry value if different" {
            Mock Test-Path { return $true }
            Mock Get-Item { 
                $obj = New-Object PSObject
                $obj | Add-Member -MemberType ScriptMethod -Name "GetValueNames" -Value { return @("TestValue") }
                $obj | Add-Member -MemberType ScriptMethod -Name "GetValueKind" -Value { return "String" }
                return $obj
            }
            Mock Get-ItemProperty { return [PSCustomObject]@{ "TestValue" = "OldValue" } }
            Mock Set-ItemProperty { param([Parameter(ValueFromRemainingArguments)]$rest) }
            Mock Write-BifrostLog { }

            Sync-BifrostRegistry -Registry @(@{ path="HKCU:\Software\Test"; name="TestValue"; value="NewValue" }) | Out-Null
            
            Assert-MockCalled Set-ItemProperty -Exactly 1
        }
    }

    Context "Sync-BifrostNetworking" {
        It "Should create firewall rule if missing" {
            Mock Set-NetFirewallProfile { }
            Mock Get-NetFirewallRule { return $null }
            Mock New-NetFirewallRule { 
                param([Parameter(ValueFromRemainingArguments)]$rest) 
            }
            Mock Write-BifrostLog { }

            $Net = @{ firewall = @{ enabled = $true; allowedTCPPorts = @(80) } }
            Sync-BifrostNetworking -Networking $Net -IsAdmin $true -Pure $false | Out-Null

            Assert-MockCalled New-NetFirewallRule -Times 1 -Exactly
        }

        It "Should purge rules in Pure mode" {
            Mock Set-NetFirewallProfile { }
            Mock Remove-NetFirewallRule { }
            Mock Get-NetFirewallRule { return $null }
            Mock New-NetFirewallRule { }
            Mock Write-BifrostLog { }

            $Net = @{ firewall = @{ enabled = $true; allowedTCPPorts = @(80) } }
            Sync-BifrostNetworking -Networking $Net -IsAdmin $true -Pure $true | Out-Null

            Assert-MockCalled Remove-NetFirewallRule -Exactly 1
        }

        It "Should NOT purge rules when Pure is false" {
            Mock Set-NetFirewallProfile { }
            Mock Remove-NetFirewallRule { }
            Mock Get-NetFirewallRule { return $null }
            Mock New-NetFirewallRule { }
            Mock Write-BifrostLog { }

            $Net = @{ firewall = @{ enabled = $true; allowedTCPPorts = @(80) } }
            Sync-BifrostNetworking -Networking $Net -IsAdmin $true -Pure $false | Out-Null

            Assert-MockCalled Remove-NetFirewallRule -Exactly 0
        }

        It "Should handle null port arrays" {
            Mock Set-NetFirewallProfile { }
            Mock Get-NetFirewallRule { return $null }
            Mock New-NetFirewallRule { }
            Mock Write-BifrostLog { }

            $Net = @{ firewall = @{ enabled = $true; allowedTCPPorts = $null } }
            Sync-BifrostNetworking -Networking $Net -IsAdmin $true -Pure $false | Out-Null
            # Should not throw
            Assert-MockCalled New-NetFirewallRule -Exactly 0
        }
    }

    Context "Sync-BifrostServices" {
        It "Should start service if stopped" {
            $StoppedSvc = [PSCustomObject]@{ Name = "TestSvc"; Status = "Stopped" }
            Mock Get-Service { return $StoppedSvc }
            Mock Start-Service { }
            Mock Set-Service { }
            Mock Write-BifrostLog { }

            Sync-BifrostServices -Services @(@{ name="TestSvc"; state="Running" }) -IsAdmin $true | Out-Null
            
            Assert-MockCalled Start-Service -Exactly 1
        }
    }

    Context "Sync-BifrostScripts" {
        It "Should execute script if no condition provided" {
            Mock Write-BifrostLog { }
            $Scripts = @(@{ name = "Test"; command = "Write-Output 'Hello'" })
            Sync-BifrostScripts -Scripts $Scripts | Out-Null
            Assert-MockCalled Write-BifrostLog -Times 2
        }

        It "Should skip script if 'creates' path exists" {
            Mock Test-Path { return $true }
            Mock Write-BifrostLog { }
            $Scripts = @(@{ name = "Test"; command = "Write-Output 'Hello'"; creates = "C:\exists.txt" })
            Sync-BifrostScripts -Scripts $Scripts | Out-Null
            Assert-MockCalled Write-BifrostLog -ParameterFilter { $Message -match "Skipping \(Path exists\)" } -Exactly 1
        }

        It "Should skip script if 'unless' returns true" {
            Mock Write-BifrostLog { }
            $Scripts = @(@{ name = "Test"; command = "Write-Output 'Hello'"; unless = '$true' })
            Sync-BifrostScripts -Scripts $Scripts | Out-Null
            Assert-MockCalled Write-BifrostLog -ParameterFilter { $Message -match "Skipping \(Condition met\)" } -Exactly 1
        }
    }

    Context "Get-BifrostConfig" {
        It "Should load local config if it exists" {
            Mock Test-Path { return $true }
            Mock Get-Content { return '{"users":[]}' }
            
            $Config = Get-BifrostConfig -ConfigPath "C:\config.json"
            $Config.users.Count | Should -Be 0
        }

        It "Should download remote config if URL provided" {
            Mock Test-Path { return $false }
            Mock Invoke-WebRequest { 
                return [PSCustomObject]@{ Content = '{"users":[{"username":"remote"}]}' }
            }
            Mock Write-BifrostLog { }
            
            $Config = Get-BifrostConfig -ConfigPath "https://example.com/config.json"
            $Config.users[0].username | Should -Be "remote"
        }

        It "Should generate default template if no config found" {
            Mock Test-Path { return $false }
            Mock Out-File { }
            Mock Write-BifrostLog { }
            
            $Config = Get-BifrostConfig -ConfigPath "C:\nonexistent.json"
            $Config.users[0].username | Should -Be "bifrost-user"
            Assert-MockCalled Out-File -Exactly 1
        }
    }

    Context "Invoke-Bifrost" {
        It "Should orchestrate all modules" {
            Mock Test-BifrostAdmin { return $true }
            Mock Get-BifrostConfig { return @{ users = @(); packages = @(); system = @() } }
            Mock Write-BifrostLog { }
            Mock Sync-BifrostUsers { }
            Mock Sync-BifrostPackages { }
            Mock Sync-BifrostSystem { }
            Mock Sync-BifrostNetworking { }
            Mock Sync-BifrostDownloads { }
            Mock Sync-BifrostFiles { }
            Mock Sync-BifrostRegistry { }
            Mock Sync-BifrostServices { }
            Mock Sync-BifrostScripts { }
            Mock Test-Path { return $true }

            Invoke-Bifrost -Config "C:\config.json" | Out-Null

            Assert-MockCalled Sync-BifrostUsers -Exactly 1
            Assert-MockCalled Sync-BifrostPackages -Exactly 1
            Assert-MockCalled Sync-BifrostSystem -Exactly 1
        }
    }
}
