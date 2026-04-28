
BeforeAll {
    # Define placeholders for Windows-specific commands so they can be mocked on Linux
    $WindowsCommands = @(
        "Get-LocalUser", "New-LocalUser", "Set-LocalUser",
        "Get-Service", "Start-Service", "Stop-Service", "Set-Service",
        "Get-NetFirewallRule", "New-NetFirewallRule", "Remove-NetFirewallRule", "Set-NetFirewallProfile",
        "Get-WindowsOptionalFeature", "Enable-WindowsOptionalFeature",
        "Get-WindowsCapability", "Add-WindowsCapability",
        "Get-ItemProperty", "Set-ItemProperty", "scoop", "Get-Item", "Get-FileHash"
    )

    # These exist on Linux but with different parameter sets or providers
    $ForceOverride = @("Set-ItemProperty", "Get-ItemProperty", "Get-Item", "Get-FileHash")

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
    }

    Context "Sync-BifrostSystem" {
        It "Should enable optional features if disabled" {
            Mock Get-WindowsOptionalFeature { return [PSCustomObject]@{ State = "Disabled" } }
            Mock Enable-WindowsOptionalFeature { }
            Mock Write-BifrostLog { }

            Sync-BifrostSystem -System @{ features = @("NetFx3") } -IsAdmin $true | Out-Null

            Assert-MockCalled Enable-WindowsOptionalFeature -Exactly 1
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
