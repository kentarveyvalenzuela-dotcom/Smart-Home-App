Param()

Set-StrictMode -Version Latest

Write-Host "Setting up Python virtual environment and installing backend dependencies..."

$venvPath = Join-Path -Path $PSScriptRoot -ChildPath "..\.venv"
$venvPath = (Resolve-Path $venvPath).ProviderPath

if (-Not (Test-Path $venvPath)) {
    python -m venv $venvPath
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create venv with 'python -m venv'"; exit 1 }
}

$pythonExe = Join-Path $venvPath 'Scripts\\python.exe'
if (-Not (Test-Path $pythonExe)) {
    Write-Error "Python executable not found in venv at $pythonExe"; exit 1
}

Write-Host "Upgrading pip..."
& $pythonExe -m pip install --upgrade pip setuptools wheel

Write-Host "Installing backend requirements from requirements.txt (this may take a few minutes)..."
& $pythonExe -m pip install -r (Join-Path $PSScriptRoot '..\\requirements.txt')

if ($LASTEXITCODE -ne 0) { Write-Error "pip install failed. See output above."; exit 1 }

Write-Host "Writing recommended VS Code workspace settings to .vscode/settings.json"
$vscodeDir = Join-Path $PSScriptRoot '..\\.vscode'
if (-Not (Test-Path $vscodeDir)) { New-Item -ItemType Directory -Path $vscodeDir | Out-Null }

$settings = @{
    "python.defaultInterpreterPath" = $pythonExe
    "python.analysis.extraPaths" = @("${PWD}\\backend")
}

$settingsPath = Join-Path $vscodeDir 'settings.json'
$settings | ConvertTo-Json -Depth 4 | Out-File -FilePath $settingsPath -Encoding utf8

Write-Host "Setup complete. To finish, open this folder in VS Code and set the interpreter to: $pythonExe"
Write-Host "If you still see editor diagnostics, reload the VS Code window (Developer: Reload Window) or restart the language server."

Write-Host "Optional: start Postgres via docker-compose (if you want local DB):"
Write-Host "  docker compose -f backend\\docker-compose.yml up -d"

Exit 0
