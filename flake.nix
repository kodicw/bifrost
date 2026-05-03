{
  description = "Bifrost: Declarative Windows State Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    jbot.url = "github:kodicw/jbot";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    let
      # Use nixpkgs lib for the library
      lib = import ./lib.nix { inherit (nixpkgs) lib; };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        inherit lib;
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.powershell
            pkgs.nb
            pkgs.git
          ];

          shellHook = ''
            echo "👻 Bifrost Development Environment"
            echo "JBot Organization is active in .jbot/"
          '';
        };
      }
    ) // {
      inherit lib;
      # Expose a Home Manager module to schedule Bifrost agents
      homeManagerModules.default = _: {
        programs.nixspirit.agents = {
          bifrost-lead = {
            enable = true;
            role = "Managerial Lead";
            description = "Orchestrator for PowerShell stability and project roadmap.";
            projectDir = "/home/kodicw/code/bifrost";
            interval = "hourly";
          };
          bifrost-architect = {
            enable = true;
            role = "System Architect";
            description = "Expert in Nix-to-Windows declarative state mapping.";
            projectDir = "/home/kodicw/code/bifrost";
            interval = "*-*-* 00/2:00:00";
          };
          bifrost-tester = {
            enable = true;
            role = "QA Engineer";
            description = "PowerShell testing expert using Pester and idempotency validation.";
            projectDir = "/home/kodicw/code/bifrost";
            interval = "*-*-* 00/2:00:00";
          };
        };
      };
    };
}
