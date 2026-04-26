
BeforeAll {
    . $PSScriptRoot/../bifrost.ps1
}

Describe "Bifrost Sync Modules" {
    
    Context "Sync-BifrostUsers" {
        It "Should create user if it doesn't exist" {
            Mock Get-LocalUser { return $null }
            Mock New-LocalUser { }
            Mock Write-BifrostLog { }
            
            $Users = @(@{ username = "testuser"; fullname = "Test User"; description = "Test Desc" })
            Sync-BifrostUsers -Users $Users -IsAdmin $true
            
            Assert-MockCalled New-LocalUser -Exactly 1 -ParameterFilter { $Name -eq "testuser" }
        }

        It "Should update user if metadata differs" {
            $ExistingUser = [PSCustomObject]@{ Name = "testuser"; FullName = "Old Name"; Description = "Old Desc" }
            Mock Get-LocalUser { return $ExistingUser }
            Mock Set-LocalUser { }
            Mock Write-BifrostLog { }
            
            $Users = @(@{ username = "testuser"; fullname = "New Name"; description = "New Desc" })
            Sync-BifrostUsers -Users $Users -IsAdmin $true
            
            Assert-MockCalled Set-LocalUser -Exactly 1 -ParameterFilter { $Name -eq "testuser" -and $FullName -eq "New Name" }
        }
    }

    Context "Sync-BifrostFiles" {
        It "Should update file if content differs" {
            Mock Test-Path { return $true }
            Mock Get-Content { return "Old Content" }
            Mock Set-Content { }
            Mock Write-BifrostLog { }

            Sync-BifrostFiles -Files @(@{ path="C:\test.txt"; content="New Content" })
            
            Assert-MockCalled Set-Content -Exactly 1
        }

        It "Should skip file update if content matches" {
            Mock Test-Path { return $true }
            Mock Get-Content { return "Same Content" }
            Mock Set-Content { }
            Mock Write-BifrostLog { }

            Sync-BifrostFiles -Files @(@{ path="C:\test.txt"; content="Same Content" })
            
            Assert-MockCalled Set-Content -Exactly 0
        }
    }

    Context "Sync-BifrostRegistry" {
        It "Should set registry value if different" {
            Mock Test-Path { return $true }
            # Mocking Get-ItemProperty to return an object with the property
            Mock Get-ItemProperty { return [PSCustomObject]@{ "TestValue" = "OldValue" } }
            Mock Set-ItemProperty { }
            Mock Write-BifrostLog { }

            Sync-BifrostRegistry -Registry @(@{ path="HKCU:\Software\Test"; name="TestValue"; value="NewValue" })
            
            Assert-MockCalled Set-ItemProperty -Exactly 1
        }

        It "Should skip registry update if value is correct" {
            Mock Test-Path { return $true }
            Mock Get-ItemProperty { return [PSCustomObject]@{ "TestValue" = "CorrectValue" } }
            Mock Set-ItemProperty { }
            Mock Write-BifrostLog { }

            Sync-BifrostRegistry -Registry @(@{ path="HKCU:\Software\Test"; name="TestValue"; value="CorrectValue" })
            
            Assert-MockCalled Set-ItemProperty -Exactly 0
        }
    }

    Context "Sync-BifrostServices" {
        It "Should start service if stopped" {
            $StoppedSvc = [PSCustomObject]@{ Name = "TestSvc"; Status = "Stopped" }
            Mock Get-Service { return $StoppedSvc }
            Mock Start-Service { }
            Mock Set-Service { }
            Mock Write-BifrostLog { }

            Sync-BifrostServices -Services @(@{ name="TestSvc"; state="Running" }) -IsAdmin $true
            
            Assert-MockCalled Start-Service -Exactly 1
        }
    }
}
