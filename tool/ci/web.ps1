Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

function Start-WebDriver {
  param(
    [Parameter(Mandatory)]
    [string] $DriverPath,

    [Parameter(Mandatory)]
    [scriptblock] $Action
  )

  $driverProcess = Start-Process -FilePath $DriverPath -ArgumentList '--port=4444' -WindowStyle Hidden -PassThru
  try {
    $deadline = (Get-Date).AddSeconds(15)
    $isReady = $false
    do {
      try {
        if ((Invoke-RestMethod -Uri 'http://127.0.0.1:4444/status' -TimeoutSec 2).value.ready) {
          $isReady = $true
          break
        }
      } catch {
        Start-Sleep -Seconds 1
      }
    } while ((Get-Date) -lt $deadline)

    if (-not $isReady) {
      throw 'ChromeDriver did not become ready on port 4444'
    }
    & $Action
  } finally {
    if ($driverProcess -and -not $driverProcess.HasExited) {
      Stop-Process -Id $driverProcess.Id -Force
    }
  }
}

function Invoke-WebDrive {
  param(
    [Parameter(Mandatory)]
    [string] $Target,

    [string[]] $Arguments = @()
  )

  $driveScript = Join-Path $PSScriptRoot 'drive.ps1'
  & $driveScript $Target 'web-server' '--browser-name=chrome' '--headless' @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Web drive failed for $Target with exit code $LASTEXITCODE"
  }
}

function Assert-WebSourceMatrix {
  $combined = 'all_web_test.dart'
  $separate = @(
    'wasm_bootstrap_web_test.dart',
    'wasm_loader_lifecycle_web_test.dart',
    'wasm_swap_nv_atomicity_web_test.dart',
    'yuv_web_capabilities_web_test.dart',
    'shader_probe_web_test.dart'
  )
  $aggregate = @(
    'getbytes_contract_web_test.dart',
    'image_cache_key_web_test.dart',
    'nv_chroma_order_web_test.dart',
    'padded_bgra_constructor_web_test.dart',
    'probe_web_test.dart',
    'serialization_contract_web_test.dart',
    'wasm_abi_v1_descriptor_staging_web_test.dart',
    'wasm_parity_edge_cases_web_test.dart',
    'web_ownership_regression_web_test.dart'
  )
  $executionSources = @{
    'wasm_bootstrap_web_test.dart' = @('wasm_bootstrap_web_test.dart')
    'wasm_loader_lifecycle_web_test.dart' = @('wasm_loader_lifecycle_web_test.dart')
    'wasm_swap_nv_atomicity_web_test.dart' = @('wasm_swap_nv_atomicity_web_test.dart')
    'fake_loader_web_tests.dart' = @('yuv_web_capabilities_web_test.dart')
    'shader_probe_web_test.dart' = @()
  }
  $baselineCases = @{
    'getbytes_contract_web_test.dart' = 4
    'image_cache_key_web_test.dart' = 1
    'nv_chroma_order_web_test.dart' = 2
    'padded_bgra_constructor_web_test.dart' = 1
    'probe_web_test.dart' = 1
    'serialization_contract_web_test.dart' = 1
    'shader_probe_web_test.dart' = 1
    'wasm_abi_v1_descriptor_staging_web_test.dart' = 29
    'wasm_bootstrap_web_test.dart' = 1
    'wasm_loader_lifecycle_web_test.dart' = 9
    'wasm_parity_edge_cases_web_test.dart' = 2
    'wasm_swap_nv_atomicity_web_test.dart' = 3
    'web_ownership_regression_web_test.dart' = 4
    'yuv_web_capabilities_web_test.dart' = 5
  }

  $integrationDirectory = Join-Path (Get-CiRepositoryRoot) 'example\integration_test'
  $discovered = @(Get-ChildItem -Path $integrationDirectory -Filter '*_web_test.dart' -File |
      Where-Object Name -ne $combined |
      ForEach-Object Name |
      Sort-Object)
  $mapped = @($aggregate + $separate | Sort-Object -Unique)
  $unmapped = @($discovered | Where-Object { $_ -notin $mapped })
  $missingSources = @($mapped | Where-Object { $_ -notin $discovered })
  if ($unmapped.Count -gt 0 -or $missingSources.Count -gt 0 -or $mapped.Count -ne ($aggregate.Count + $separate.Count)) {
    throw "Web source mapping mismatch: unmapped=[$($unmapped -join ', ')]; missing=[$($missingSources -join ', ')]"
  }
  if ($baselineCases.Count -ne $discovered.Count -or @($baselineCases.Keys | Where-Object { $_ -notin $discovered }).Count -gt 0 -or ($baselineCases.Values | Measure-Object -Sum).Sum -ne 64) {
    throw 'Web source case baseline must cover all 14 sources and total 64 cases.'
  }

  $aggregatorPath = Join-Path $integrationDirectory $combined
  if (-not (Test-Path -LiteralPath $aggregatorPath -PathType Leaf)) {
    throw "Missing combined Web target: $combined"
  }
  $aggregatorSource = Get-Content -LiteralPath $aggregatorPath -Raw
  foreach ($source in $aggregate) {
    $importPattern = "import\s+'$([regex]::Escape($source))'\s+as\s+(\w+);"
    if ($aggregatorSource -notmatch $importPattern) {
      throw "Aggregated Web source is not imported and invoked: $source"
    }
    if ($aggregatorSource -notmatch "$([regex]::Escape($Matches[1]))\.main\(\);") {
      throw "Aggregated Web source is not invoked: $source"
    }
  }
  if ($aggregatorSource -match '\bgroup\(') {
    throw 'Aggregated Web target must not wrap source mains in groups.'
  }
  foreach ($target in $executionSources.Keys) {
    if ($target -like '*_web_tests.dart') {
      $targetSource = Get-Content -LiteralPath (Join-Path $integrationDirectory $target) -Raw
      foreach ($source in $executionSources[$target]) {
        $importPattern = "import\s+'$([regex]::Escape($source))'\s+as\s+(\w+);"
        if ($targetSource -notmatch $importPattern -or $targetSource -notmatch "$([regex]::Escape($Matches[1]))\.main\(\);") {
          throw "Separate Web source is not imported and invoked by ${target}: $source"
        }
      }
      if ($targetSource -match '\bgroup\(') {
        throw "Separate Web target must not wrap source mains in groups: $target"
      }
    }
  }

  return @($combined) + @($executionSources.Keys | Sort-Object)
}

$repositoryRoot = Get-CiRepositoryRoot
$gitBash = 'D:\.important\Git\bin\bash.exe'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$chromeDriver = 'D:\.projects\.tools\chromedriver-win64\chromedriver.exe'
$emsdkRoot = 'D:\.projects\.tools\emsdk-3.1.74'

foreach ($requiredPath in @($gitBash, $chrome, $chromeDriver)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required Web CI executable is missing: $requiredPath"
  }
}

$chromeVersion = (Get-Item -LiteralPath $chrome).VersionInfo.ProductVersion
$driverOutput = & $chromeDriver --version
if ($LASTEXITCODE -ne 0) {
  throw "ChromeDriver version check failed with exit code $LASTEXITCODE"
}
$driverVersion = ($driverOutput | Select-Object -First 1) -replace '^ChromeDriver ', ''
if ($chromeVersion.Split('.')[0] -ne $driverVersion.Split('.')[0]) {
  throw "Chrome $chromeVersion and ChromeDriver $driverVersion have different major versions"
}

$env:CHROME_EXECUTABLE = $chrome
$env:CHROMEDRIVER_EXE = $chromeDriver
Add-CiPath (Split-Path -Parent $gitBash)

Push-Location $repositoryRoot
try {
  Invoke-CiNativeCommand flutter config --enable-web
  Invoke-CiNativeCommand flutter pub get

  foreach ($asset in @('assets/wasm/yuv_ffi.js', 'assets/wasm/yuv_ffi.wasm')) {
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf) -or (Get-Item -LiteralPath $asset).Length -eq 0) {
      throw "WASM package asset is missing or empty: $asset"
    }
  }
  Invoke-CiNativeCommand git restore --worktree -- example/windows/flutter/generated_plugin_registrant.cc example/windows/flutter/generated_plugin_registrant.h example/windows/flutter/generated_plugins.cmake
  & git add --refresh -- assets/wasm/yuv_ffi.js assets/wasm/yuv_ffi.wasm
  if ($LASTEXITCODE -ne 0) {
    throw "Could not refresh WASM asset index state: $LASTEXITCODE"
  }
  $publishOutput = & flutter pub publish --dry-run 2>&1
  if ($LASTEXITCODE -ne 0) {
    $publishOutput | Write-Output
    throw "pub publish dry-run exited $LASTEXITCODE"
  }
  $dryRunOutput = [string]::Join([Environment]::NewLine, $publishOutput)
  if ($dryRunOutput -notmatch 'yuv_ffi\.js \(' -or $dryRunOutput -notmatch 'yuv_ffi\.wasm \(') {
    throw 'pub dry-run did not list both committed WASM assets'
  }

  if (-not (Test-Path -LiteralPath (Join-Path $emsdkRoot 'emsdk.bat') -PathType Leaf)) {
    Invoke-CiNativeCommand git clone https://github.com/emscripten-core/emsdk.git $emsdkRoot
  }
  Invoke-CiNativeCommand (Join-Path $emsdkRoot 'emsdk.bat') install 3.1.74
  Invoke-CiNativeCommand (Join-Path $emsdkRoot 'emsdk.bat') activate 3.1.74
  . (Join-Path $emsdkRoot 'emsdk_env.ps1')
  if ($LASTEXITCODE -ne 0) {
    throw "emsdk environment setup failed with $LASTEXITCODE"
  }
  & (Join-Path $emsdkRoot 'upstream\emscripten\emcc.bat') -v
  if ($LASTEXITCODE -ne 0) {
    throw "emcc version check failed with exit code $LASTEXITCODE"
  }
  & $gitBash --noprofile --norc -c 'sh ./tool/wasm/build_wasm.sh --profile release'
  if ($LASTEXITCODE -ne 0) {
    throw "WASM build failed with $LASTEXITCODE"
  }
  Invoke-CiNativeCommand git diff --exit-code -- assets/wasm/yuv_ffi.js assets/wasm/yuv_ffi.wasm

  Push-Location (Join-Path $repositoryRoot 'example')
  try {
    Invoke-CiNativeCommand flutter pub get
  } finally {
    Pop-Location
  }

  $targets = Assert-WebSourceMatrix
  Start-WebDriver -DriverPath $chromeDriver -Action {
    foreach ($target in $targets) {
      Invoke-WebDrive -Target "integration_test/$target"
    }
  }
  Start-WebDriver -DriverPath $chromeDriver -Action {
    Invoke-WebDrive -Target 'integration_test/reference_web_conversions_test.dart' -Arguments @('--profile')
  }
  Start-WebDriver -DriverPath $chromeDriver -Action {
    Invoke-WebDrive -Target 'integration_test/camera_source_web_smoke_test.dart' -Arguments @('--web-browser-flag=--use-fake-device-for-media-stream', '--web-browser-flag=--use-fake-ui-for-media-stream')
  }

  $wasmTargets = @(
    'integration_test/probe_web_test.dart',
    'integration_test/shader_probe_web_test.dart',
    'integration_test/all_web_test.dart'
  )
  $wasmStarted = [System.Diagnostics.Stopwatch]::StartNew()
  Start-WebDriver -DriverPath $chromeDriver -Action {
    foreach ($target in $wasmTargets) {
      Invoke-WebDrive -Target $target -Arguments @('--wasm')
    }
  }
  $wasmStarted.Stop()
  Write-Output "Web WASM CI passed: targets=$($wasmTargets.Count); elapsed=$($wasmStarted.Elapsed.ToString('hh\:mm\:ss'))."

  & git add --refresh -- assets/wasm/yuv_ffi.js assets/wasm/yuv_ffi.wasm example/windows/flutter/generated_plugin_registrant.cc example/windows/flutter/generated_plugin_registrant.h example/windows/flutter/generated_plugins.cmake
  if ($LASTEXITCODE -ne 0) {
    throw "Could not refresh generated-file index state: $LASTEXITCODE"
  }

  Write-Output "Web CI passed: Chrome $chromeVersion; sources=14; integration cases=64; reference matrix=119; camera smoke=1."
} finally {
  Pop-Location
}
