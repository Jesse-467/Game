param([switch]$Check, [switch]$Editor)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$enginePath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $enginePath)) {
    $enginePath = [Environment]::GetEnvironmentVariable('GODOT_BIN', 'User')
}
if (-not $enginePath -or -not (Test-Path -LiteralPath $enginePath)) {
    throw 'Install Godot 4.7.2 standard edition, then set GODOT_BIN to its console executable.'
}
if ($Check) {
    & python (Join-Path $PSScriptRoot 'export_balance.py') --check
    if ($LASTEXITCODE -ne 0) { throw 'Excel and runtime configuration do not match.' }
    & python (Join-Path $PSScriptRoot 'check_configuration_pipeline.py')
    if ($LASTEXITCODE -ne 0) { throw 'Configuration pipeline check failed.' }
    foreach ($testScript in @('tests/combat_smoke.gd', 'tests/arena_field_smoke.gd', 'tests/ui_smoke.gd', 'tests/spatial_index_smoke.gd', 'tests/modal_touch_smoke.gd', 'tests/checkpoint_smoke.gd', 'tests/boss_patterns_smoke.gd', 'tests/player_readout_smoke.gd', 'tests/world_smoke.gd', 'tests/iteration_0_7_smoke.gd')) {
        $checkOutput = & $enginePath --headless --path $projectRoot --script $testScript --quit-after 180 2>&1
        $checkOutput | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0 -or ($checkOutput -match 'SCRIPT ERROR|^ERROR:') -or -not ($checkOutput -match '^PASS:')) { throw "Checks failed: $testScript" }
    }
} elseif ($Editor) {
    & $enginePath --path $projectRoot --editor
} else {
    & $enginePath --path $projectRoot
}
if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE" }
