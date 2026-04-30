# Bifrost Justfile

# Default task: show dashboard
default: dashboard

# Show the JBot dashboard
dashboard:
    @bat --paging=never INDEX.md

# Audit the codebase for technical purity
audit:
    @echo "🔍 Auditing for Technical Purity..."
    @statix check .
    @deadnix .
    @pwsh -Command "Invoke-Pester -Path tests"
    @echo "✅ Audit Complete."

# Prune dead code and technical debt
prune:
    @echo "✂️ Pruning Dead Code..."
    @deadnix --edit .
    @echo "✅ Pruning Complete."

# Run tests
test:
    @echo "🧪 Running Tests..."
    @pwsh -Command "Invoke-Pester -Path tests"


# Initialize a new JBot organization
jbot-init name="new-project" goal="Technical Excellence & Architectural Purity":
    @./jbot-init.sh "{{name}}" "{{goal}}"

# Generate config.json from a Nix expression
bifrost-gen file="config.nix" output="config.json":
    @echo "Generating {{output}} from {{file}}..."
    @nix eval --impure --extra-experimental-features "nix-command flakes" --json --expr "let flake = builtins.getFlake (toString ./.); lib = flake.lib; in import (toString ./{{file}}) { inherit lib; }" > {{output}}
    @echo "✅ Done."

# Initialize a new module (template)
init-module name:
    @echo "📦 Initializing module: {{name}}"
    @# Logic to add a new module section to bifrost.ps1 or similar
