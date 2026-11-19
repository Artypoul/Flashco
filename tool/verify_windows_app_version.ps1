param(
  [Parameter(Mandatory = $true)][string]$ZipPath,
  [Parameter(Mandatory = $true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$pubspec = Get-Content -Raw 'pubspec.yaml'
$match = [regex]::Match($pubspec, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
if (-not $match.Success) { throw 'Expected a numeric semantic version and build in pubspec.yaml.' }
$parts = @(1..3 | ForEach-Object { [long]$match.Groups[$_].Value })
if (@($parts | Where-Object { $_ -gt 65535 }).Count -ne 0) {
  throw 'Windows numeric semantic version components must fit 16 bits.'
}
$fullVersion = $match.Value.Substring($match.Value.IndexOf(':') + 1).Trim()
$expectedNumeric = "$($parts[0]).$($parts[1]).$($parts[2]).0"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
$temp = Join-Path ([IO.Path]::GetTempPath()) ('flashco-version-' + [guid]::NewGuid())
try {
  $entries = @($archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq 'Flashco.exe' })
  if ($entries.Count -ne 1) { throw 'ZIP must contain exactly one root Flashco.exe.' }
  [IO.Directory]::CreateDirectory($temp) | Out-Null
  $app = Join-Path $temp 'Flashco.exe'
  [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $app)
  $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($app)
  $fileNumeric = "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart).$($info.FilePrivatePart)"
  $productNumeric = "$($info.ProductMajorPart).$($info.ProductMinorPart).$($info.ProductBuildPart).$($info.ProductPrivatePart)"
  if ($fileNumeric -ne $expectedNumeric -or $productNumeric -ne $expectedNumeric) {
    throw "Unexpected numeric app version: file=$fileNumeric product=$productNumeric expected=$expectedNumeric"
  }
  if ($info.FileVersion -cne $fullVersion -or $info.ProductVersion -cne $fullVersion) {
    throw "Unexpected app version strings: file=$($info.FileVersion) product=$($info.ProductVersion) expected=$fullVersion"
  }
  [ordered]@{
    archive = (Split-Path -Leaf $ZipPath)
    application = 'Flashco.exe'
    file_numeric = $fileNumeric
    product_numeric = $productNumeric
    file_string = $info.FileVersion
    product_string = $info.ProductVersion
  } | ConvertTo-Json | Set-Content -Encoding utf8 $OutputPath
  Get-Content -Raw $OutputPath | Write-Output
}
finally {
  $archive.Dispose()
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
