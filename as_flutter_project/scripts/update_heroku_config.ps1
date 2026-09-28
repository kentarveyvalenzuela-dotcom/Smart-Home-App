# Heroku Config Update Script
# Run this after logging in with: heroku login -i

Write-Host "Updating Heroku Config Vars for as-flutter-backend-prod..." -ForegroundColor Cyan

# Update MQTT Configuration (HiveMQ Cloud Production)
heroku config:set `
    MQTT_BROKER=de9d5f2926cf45349f923cadced1aece.s1.eu.hivemq.cloud `
    MQTT_PORT=8883 `
    MQTT_USERNAME=as_flutter_user `
    MQTT_PASSWORD=SmartHome@2025 `
    MQTT_USE_TLS=true `
    --app as-flutter-backend-prod

# Verify the changes
Write-Host "`nVerifying Config Vars:" -ForegroundColor Green
heroku config --app as-flutter-backend-prod

Write-Host "`nDone! Heroku config vars updated successfully." -ForegroundColor Green

