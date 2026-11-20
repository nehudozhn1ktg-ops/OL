# Воспроизводимый Web-экспорт OneLife (WEB-001).
# Запуск из корня проекта:  pwsh -File tools/web_export.ps1
# Требует: Godot 4.7.2 и шаблоны экспорта в %APPDATA%\Godot\export_templates\4.7.2.stable\.

param(
  [string]$Godot = 'C:\Godot\Godot_v4.7.2-stable_win64.exe',
  [string]$Path  = (Resolve-Path (Join-Path $PSScriptRoot '..')),
  [string]$Out   = 'build/web/index.html'
)

$ErrorActionPreference = 'Stop'
$stdout = Join-Path $env:TEMP 'onelife_export.log'
$stderr = Join-Path $env:TEMP 'onelife_export.err.log'
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

# 1. Кэш классов (нужен после свежего checkout — см. docs/web-mvp/README.md).
& $Godot --headless --editor --quit --path $Path 2>$null | Out-Null

# 2. Экспорт.
$p = Start-Process -FilePath $Godot `
  -ArgumentList '--headless','--path',"`"$Path`"",'--export-release','Web',"`"$Out`"" `
  -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow

Write-Output ("export exit: {0}" -f $p.ExitCode)
if (Test-Path $stderr) { Get-Content $stderr | Where-Object { $_ -notmatch '^Godot Engine' } }
if ($p.ExitCode -ne 0) { exit $p.ExitCode }

# 3. Проверка артефактов.
$dir = Split-Path $Out
Get-ChildItem $dir -File | ForEach-Object {
  Write-Output ("{0}`t{1,10} B" -f $_.Name, $_.Length)
}

# 4. Маркер однопоточности: в однопоточной сборке нет SharedArrayBuffer/требования COI.
$js = Get-ChildItem $dir -Filter *.js | Select-Object -First 1
if ($js) {
  $hits = Select-String -Path $js.FullName -Pattern 'SharedArrayBuffer','crossOriginIsolated' -SimpleMatch -ErrorAction SilentlyContinue
  if ($hits) { Write-Output 'WARNING: в JS есть упоминания SharedArrayBuffer/crossOriginIsolated (возможно, потоки).' }
  else { Write-Output 'OK: однопоточная сборка (нет SharedArrayBuffer/COI).' }
}
