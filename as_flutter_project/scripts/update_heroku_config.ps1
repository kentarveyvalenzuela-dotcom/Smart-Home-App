# Heroku Config Update Script
# Run this after logging in with: heroku login -i

Write-Host "Updating Heroku Config Vars for as-flutter-backend-prod..." -ForegroundColor Cyan

# Read values from the current PowerShell environment; do not commit credentials.
$required = @('MQTT_BROKER', 'MQTT_USERNAME', 'MQTT_PASSWORD')
foreach ($name in $required) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Set `$env:$name before running this script."
    }
}

heroku config:set `
    "MQTT_BROKER=$env:MQTT_BROKER" `
    "MQTT_PORT=$($env:MQTT_PORT ?? '8883')" `
    "MQTT_USERNAME=$env:MQTT_USERNAME" `
    "MQTT_PASSWORD=$env:MQTT_PASSWORD" `
    "MQTT_USE_TLS=$($env:MQTT_USE_TLS ?? 'true')" `
    --app as-flutter-backend-prod

# Verify the changes
Write-Host "`nVerifying Config Vars:" -ForegroundColor Green
heroku config --app as-flutter-backend-prod

Write-Host "`nDone! Heroku config vars updated successfully." -ForegroundColor Green

