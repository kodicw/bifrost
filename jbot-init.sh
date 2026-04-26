#!/usr/bin/env bash

# JBot Organization Bootstrapper (jbot init)
# Reference implementation for the jbot-cli feature.

set -e

# Usage: jbot-init [project_name] [project_goal]
PROJECT_NAME=${1:-"new-project"}
PROJECT_GOAL=${2:-"Technical Excellence & Architectural Purity"}

echo "🚀 Initializing JBot Organization for: $PROJECT_NAME"

# 1. Create directory structure
mkdir -p .jbot/{directives/archive,locks,messages/archive,outbox,queues}
echo "✅ Directory structure created."

# 2. Generate .project_goal
cat <<EOF > .project_goal
# Technical Excellence & Architectural Purity

#type:goal

# $PROJECT_NAME

$PROJECT_GOAL
EOF
echo "✅ .project_goal generated."

# 3. Generate agents.json
cat <<EOF > agents.json
{
  "lead": {
    "role": "Managerial Lead",
    "description": "Orchestrator and task delegator.",
    "projectDir": "$(pwd)",
    "interval": "hourly"
  },
  "architect": {
    "role": "System Architect",
    "description": "High-level design and ADR maintenance.",
    "projectDir": "$(pwd)",
    "interval": "*-*-* 00/2:00:00"
  },
  "tester": {
    "role": "QA Engineer",
    "description": "Test automation and verification.",
    "projectDir": "$(pwd)",
    "interval": "*-*-* 00/2:00:00"
  }
}
EOF
echo "✅ agents.json generated."

# 4. Initialize nb notebook
if command -v nb &> /dev/null; then
    nb notebooks add "$PROJECT_NAME" .jbot/notebook
    echo "✅ nb notebook initialized: $PROJECT_NAME"
    
    # Push initial vision to nb
    nb "$PROJECT_NAME":add --title "Strategic Vision" --body "Vision for $PROJECT_NAME: $PROJECT_GOAL"
    echo "✅ Initial vision pushed to notebook."
else
    echo "⚠️ nb not found. Skipping notebook initialization."
fi

# 5. Generate flake.nix template
cat <<EOF > flake.nix
{
  description = "$PROJECT_NAME: A JBot-managed project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    jbot.url = "github:kodicw/jbot";
  };

  outputs = { self, nixpkgs, flake-utils, jbot, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nb
            pkgs.git
            jbot.packages.\${system}.jbot-cli
          ];

          shellHook = ''
            echo "🌈 $PROJECT_NAME Development Environment"
            echo "JBot Organization is active in .jbot/"
          '';
        };
      }
    );
}
EOF
echo "✅ flake.nix template generated."

echo "🎉 JBot initialization complete!"
echo "Next steps:"
echo "1. Review agents.json and agents roles."
echo "2. Run 'jbot status' to verify."
