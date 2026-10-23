# Adds the Aura Pet home-screen widget receiver to AndroidManifest.xml.
# Run ONCE from the project root (the folder that contains the android\ dir):
#
#   powershell -ExecutionPolicy Bypass -File android\add-widget-to-manifest.ps1
#
# Safe to run twice — it checks first and skips if already present.

$manifest = "android\app\src\main\AndroidManifest.xml"

if (-not (Test-Path $manifest)) {
    Write-Host "Not found: $manifest"
    Write-Host "Run this from the project root (the folder containing android\)."
    exit 1
}

$text = Get-Content $manifest -Raw

if ($text -match "AuraPetWidgetProvider") {
    Write-Host "Widget receiver already present in AndroidManifest.xml — nothing to do."
    exit 0
}

$receiver = @'
    <receiver
        android:name=".AuraPetWidgetProvider"
        android:exported="false">
        <intent-filter>
            <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
        </intent-filter>
        <meta-data
            android:name="android.appwidget.provider"
            android:resource="@xml/aura_pet_widget_info" />
    </receiver>
'@

$text = $text -replace "</application>", ($receiver + "`r`n    </application>")
Set-Content $manifest $text -NoNewline
Write-Host "Widget receiver added to AndroidManifest.xml"
