{ lib }:
lib.mkConfig {
  users = [
    {
      username = "guest-dev";
      fullname = "Temporary Developer";
      description = "Managed by Bifrost";
    }
  ];
  packages = lib.mkPackages {
    buckets = [ "extras" ];
    apps = [ "git" "neovim" ];
    global_apps = [ "7zip" ];
  };
  networking = {
    firewall = {
      enabled = true;
      allowPing = true;
      allowedTCPPorts = [ 80 443 ];
    };
  };
  scripts = [
    (lib.mkScript {
      name = "Ensure Log Directory";
      command = "New-Item -Path 'C:\\Bifrost\\Logs' -ItemType Directory";
      unless = "Test-Path 'C:\\Bifrost\\Logs'";
    })
  ];
}
