param(
    [string]$Serial = 'emulator-5554',
    [int]$Width = 2400,
    [int]$Height = 1080,
    [string]$AndroidSdk = 'D:\AndroidSDK',
    [string]$JavaSdk = 'D:\jdk17\jdk-17'
)
$ErrorActionPreference = 'Stop'
if (-not $Serial.StartsWith('emulator-')) { throw 'This probe is restricted to a computer emulator.' }
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$probeRoot = Join-Path $projectRoot '.tools/touch-probe'
New-Item -ItemType Directory -Force (Join-Path $probeRoot 'classes'),(Join-Path $probeRoot 'dex') | Out-Null
& (Join-Path $JavaSdk 'bin/javac.exe') -encoding UTF-8 --release 8 -classpath (Join-Path $AndroidSdk 'platforms/android-35/android.jar') -d (Join-Path $probeRoot 'classes') (Join-Path $PSScriptRoot 'TouchProbe.java')
if ($LASTEXITCODE -ne 0) { throw 'Touch probe compilation failed' }
$env:JAVA_HOME = $JavaSdk
& (Join-Path $AndroidSdk 'build-tools/35.0.1/d8.bat') --lib (Join-Path $AndroidSdk 'platforms/android-35/android.jar') --output (Join-Path $probeRoot 'dex') (Join-Path $probeRoot 'classes/TouchProbe.class')
if ($LASTEXITCODE -ne 0) { throw 'Touch probe DEX compilation failed' }
& (Join-Path $JavaSdk 'bin/jar.exe') --create --file (Join-Path $probeRoot 'touch-probe.jar') -C (Join-Path $probeRoot 'dex') classes.dex
if ($LASTEXITCODE -ne 0) { throw 'Touch probe packaging failed' }
$bridge = Join-Path $AndroidSdk 'platform-tools/adb.exe'
& $bridge -s $Serial push (Join-Path $probeRoot 'touch-probe.jar') /data/local/tmp/ember-touch-probe.jar
if ($LASTEXITCODE -ne 0) { throw 'Cannot copy probe to emulator' }
& $bridge -s $Serial shell 'CLASSPATH=/data/local/tmp/ember-touch-probe.jar app_process /data/local/tmp TouchProbe' $Width $Height
if ($LASTEXITCODE -ne 0) { throw 'Emulator touch probe failed' }
