param(
    [string]$AndroidSdk = 'D:\AndroidSDK',
    [string]$JavaSdk = 'D:\jdk17\jdk-17'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
& python (Join-Path $PSScriptRoot 'export_balance.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Excel and release-hard configuration must match before packaging.' }
$enginePath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$keyStorePath = Join-Path $projectRoot '.tools/debug.keystore'
$templatePath = Join-Path $projectRoot '.tools/android-templates/android_debug.apk'
if (-not (Test-Path -LiteralPath $templatePath)) { throw 'Download Android templates first: python tools/download_android_templates.py .tools/android-templates' }
if (-not (Test-Path -LiteralPath $keyStorePath)) {
    & (Join-Path $JavaSdk 'bin/keytool.exe') -genkeypair -keystore $keyStorePath -storepass android -alias androiddebugkey -keypass android -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000 -deststoretype JKS
    if ($LASTEXITCODE -ne 0) { throw 'Debug keystore generation failed' }
}
$env:EMBER_ANDROID_SDK = $AndroidSdk
$env:EMBER_JAVA_SDK = $JavaSdk
& $enginePath --headless --path $projectRoot --editor --script tools/configure_editor.gd
if ($LASTEXITCODE -ne 0) { throw 'Editor SDK configuration failed' }
& $enginePath --headless --path $projectRoot --import --log-file (Join-Path $projectRoot 'builds/import.log')
if ($LASTEXITCODE -ne 0) { throw 'Asset import failed' }
New-Item -ItemType Directory -Force (Join-Path $projectRoot 'builds/android') | Out-Null
& $enginePath --headless --path $projectRoot --export-debug Android (Join-Path $projectRoot 'builds/android/ember-hero-debug.apk')
if ($LASTEXITCODE -ne 0) { throw 'Android export failed' }
& (Join-Path $AndroidSdk 'build-tools/35.0.1/apksigner.bat') verify (Join-Path $projectRoot 'builds/android/ember-hero-debug.apk')
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
