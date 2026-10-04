Set-StrictMode -Version Latest

function Get-Ra25InstalledVersionCode([string]$PackageInfo, [int]$ExitCode) {
  if ($ExitCode -ne 0) {
    throw "Unable to read installed package information (adb exit code $ExitCode)."
  }
  if ($PackageInfo -match '(?im)^\s*Unable to find package:') {
    return [long]0
  }

  $matches = [regex]::Matches($PackageInfo, '(?m)^\s*versionCode=(\d+)(?:\s|$)')
  if ($matches.Count -ne 1) {
    throw "Unable to determine one installed versionCode; found $($matches.Count) versionCode entries."
  }

  [long]$versionCode = 0
  $parsed = [long]::TryParse(
    $matches[0].Groups[1].Value,
    [Globalization.NumberStyles]::None,
    [Globalization.CultureInfo]::InvariantCulture,
    [ref]$versionCode
  )
  if (-not $parsed -or $versionCode -gt 2147483647) {
    throw "Installed versionCode is outside Android's supported range: $($matches[0].Groups[1].Value)."
  }
  return $versionCode
}

function Get-Ra25ApkVersionCode([string]$Badging) {
  $matches = [regex]::Matches($Badging, "(?m)^package:\s.*\bversionCode='(\d+)'(?:\s|$)")
  if ($matches.Count -ne 1) {
    throw "Unable to determine one APK versionCode; found $($matches.Count) package entries."
  }

  [long]$versionCode = 0
  if (-not [long]::TryParse(
    $matches[0].Groups[1].Value,
    [Globalization.NumberStyles]::None,
    [Globalization.CultureInfo]::InvariantCulture,
    [ref]$versionCode
  ) -or $versionCode -gt 2147483647) {
    throw "APK versionCode is outside Android's supported range: $($matches[0].Groups[1].Value)."
  }
  return $versionCode
}

function Get-Ra25VersionCodePlan([long]$InstalledVersionCode, [string]$Abi) {
  if ($InstalledVersionCode -lt 0 -or $InstalledVersionCode -gt 2147483647) {
    throw "Installed versionCode is outside Android's supported range: $InstalledVersionCode."
  }

  $abiCode = switch ($Abi) {
    'armv7' { 1L }
    'arm64' { 2L }
    default { throw "Unsupported Android ABI for versionCode calculation: $Abi" }
  }

  $abiBase = 1000L * $abiCode
  $buildNumber = [Math]::Max(1L, $InstalledVersionCode + 1L - $abiBase)
  $builtVersionCode = $abiBase + $buildNumber
  if ($builtVersionCode -le $InstalledVersionCode -or $builtVersionCode -gt 2147483647) {
    throw "Cannot create a versionCode above $InstalledVersionCode for $Abi within Android's supported range."
  }

  return [pscustomobject]@{
    abi = $Abi
    installedVersionCode = $InstalledVersionCode
    buildNumber = $buildNumber
    builtVersionCode = $builtVersionCode
  }
}
