param(
  [Parameter(Mandatory = $true)][string]$InstallerPath,
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
$installer = Get-Item -LiteralPath $InstallerPath
$info = [Diagnostics.FileVersionInfo]::GetVersionInfo($installer.FullName)
$fileNumeric = "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart).$($info.FilePrivatePart)"
$productNumeric = "$($info.ProductMajorPart).$($info.ProductMinorPart).$($info.ProductBuildPart).$($info.ProductPrivatePart)"
if ($fileNumeric -ne $expectedNumeric -or $productNumeric -ne $expectedNumeric) {
  throw "Unexpected numeric installer version: file=$fileNumeric product=$productNumeric expected=$expectedNumeric"
}
# Inno pads its fixed-width version strings with spaces.
$fileVersion = "$($info.FileVersion)".TrimEnd()
$productVersion = "$($info.ProductVersion)".TrimEnd()
if ($fileVersion -cne $fullVersion -or $productVersion -cne $fullVersion) {
  throw "Unexpected installer version strings: file=$fileVersion product=$productVersion expected=$fullVersion"
}
[ordered]@{
  file = $installer.Name
  file_numeric = $fileNumeric
  product_numeric = $productNumeric
  file_version = $fileVersion
  product_version = $productVersion
} | ConvertTo-Json | Set-Content -Encoding utf8 $OutputPath
Get-Content -Raw $OutputPath | Write-Output
