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

# Initialize a new module (template)
init-module name:
    @echo "📦 Initializing module: {{name}}"
    @# Logic to add a new module section to bifrost.ps1 or similar
