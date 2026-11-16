<#
.SYNOPSIS
    Synchronizes LookupKnownIdP entries with federation partner domains.

.DESCRIPTION
    Reads the Domain value from each ClaimsProvider that contains a
    Step-16-FederationPartner technical profile, then replaces the
    LookupKnownIdP InputParameters in the extensions policy.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Dev", "Stage", "Prod")]
    [string]$EnvironmentName,
    [string]$FederationsFile,
    [string]$ExtensionsFile,
    [string]$AppSettingsFile = (Join-Path (Split-Path -Parent $PSScriptRoot) "appsettings.json")
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$policyDirectory = Join-Path $repoRoot "Environments/$EnvironmentName"

if ([string]::IsNullOrWhiteSpace($FederationsFile)) {
    $FederationsFile = Join-Path $policyDirectory "B2C_1A_Connect_Federations.xml"
}

if ([string]::IsNullOrWhiteSpace($ExtensionsFile)) {
    $ExtensionsFile = Join-Path $policyDirectory "B2C_1A_Connect_Extensions.xml"
}

foreach ($path in @($FederationsFile, $ExtensionsFile, $AppSettingsFile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required policy file was not found: $path"
    }
}

$appSettings = Get-Content -LiteralPath $AppSettingsFile -Raw | ConvertFrom-Json
$environmentSettings = $null
if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
    $environment = @($appSettings.Environments) |
        Where-Object { $_.Name -eq $EnvironmentName } |
        Select-Object -First 1
    if ($null -eq $environment) {
        throw "Environment '$EnvironmentName' was not found in $AppSettingsFile"
    }
    if ($null -eq $environment.PolicySettings) {
        throw "Environment '$EnvironmentName' has no PolicySettings in $AppSettingsFile"
    }
    $environmentSettings = $environment.PolicySettings
}

$federationsContent = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $FederationsFile).Path)
$federationsDocument = [xml]$federationsContent
$domains = [System.Collections.Generic.List[string]]::new()
$seenDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

foreach ($claimsProvider in $federationsDocument.SelectNodes("//*[local-name()='ClaimsProvider']")) {
    $partnerProfiles = @(
        $claimsProvider.SelectNodes(".//*[local-name()='TechnicalProfile']") |
            Where-Object { $_.GetAttribute("Id").StartsWith("Step-16-FederationPartner", [System.StringComparison]::Ordinal) }
    )

    if ($partnerProfiles.Count -eq 0) {
        continue
    }

    $domainNode = $claimsProvider.SelectSingleNode("./*[local-name()='Domain']")
    if ($null -eq $domainNode -or [string]::IsNullOrWhiteSpace($domainNode.InnerText)) {
        continue
    }

    $domain = $domainNode.InnerText.Trim()
    if ($domain -match '^\{Settings:([^}]+)\}$') {
        $settingKey = $Matches[1]
        if ($null -ne $environmentSettings) {
            $setting = $environmentSettings.PSObject.Properties[$settingKey]
            if ($null -eq $setting -or [string]::IsNullOrWhiteSpace([string]$setting.Value)) {
                Write-Warning "Skipping federation domain '$domain': setting '$settingKey' is missing or empty for environment '$EnvironmentName'"
                continue
            }
            $domain = [string]$setting.Value
        }
    } elseif ($domain -match '\{Settings:') {
        throw "Federation domain '$domain' contains a Settings placeholder that is not a single setting reference"
    }

    if ($seenDomains.Add($domain)) {
        $domains.Add($domain)
    }
}

if ($domains.Count -eq 0) {
    throw "No federation partner domains were found in $FederationsFile"
}

$extensionsFullPath = (Resolve-Path -LiteralPath $ExtensionsFile).Path
$extensionsContent = [System.IO.File]::ReadAllText($extensionsFullPath)
$extensionsDocument = [xml]$extensionsContent
$lookupTransformations = @(
    $extensionsDocument.SelectNodes("//*[local-name()='ClaimsTransformation']") |
        Where-Object { $_.GetAttribute("Id") -eq "LookupKnownIdP" }
)

if ($lookupTransformations.Count -ne 1) {
    throw "Expected exactly one LookupKnownIdP transformation in $ExtensionsFile; found $($lookupTransformations.Count)"
}

if ($null -eq $lookupTransformations[0].SelectSingleNode("./*[local-name()='InputParameters']")) {
    throw "LookupKnownIdP has no InputParameters element in $ExtensionsFile"
}

$lineEnding = if ($extensionsContent.Contains("`r`n")) { "`r`n" } else { "`n" }
$inputParameters = foreach ($domain in $domains) {
    $escapedDomain = [System.Security.SecurityElement]::Escape($domain)
    "          <InputParameter Id=`"$escapedDomain`" DataType=`"string`" Value=`"true`" />"
}
$generatedParameters = $inputParameters -join $lineEnding

$lookupPattern = '(?s)(<ClaimsTransformation\b(?=[^>]*\bId\s*=\s*["'']LookupKnownIdP["''])[^>]*>.*?<InputParameters\b[^>]*>).*?(</InputParameters>.*?</ClaimsTransformation>)'
$lookupMatches = [System.Text.RegularExpressions.Regex]::Matches($extensionsContent, $lookupPattern)

if ($lookupMatches.Count -ne 1) {
    throw "Could not safely isolate LookupKnownIdP InputParameters in $ExtensionsFile"
}

$updatedContent = [System.Text.RegularExpressions.Regex]::Replace(
    $extensionsContent,
    $lookupPattern,
    [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $match.Groups[1].Value + $lineEnding + $generatedParameters + $lineEnding + $match.Groups[2].Value
    },
    [System.Text.RegularExpressions.RegexOptions]::None
)

$updatedDocument = [xml]$updatedContent
$updatedTransformations = @(
    $updatedDocument.SelectNodes("//*[local-name()='ClaimsTransformation']") |
        Where-Object { $_.GetAttribute("Id") -eq "LookupKnownIdP" }
)
$updatedTransformation = $updatedTransformations[0]
$updatedParameters = @(
    $updatedTransformation.SelectNodes("./*[local-name()='InputParameters']/*[local-name()='InputParameter']") |
        ForEach-Object { $_.GetAttribute("Id") }
)

if ($updatedParameters.Count -ne $domains.Count) {
    throw "Generated LookupKnownIdP parameter count does not match the federation domain count"
}

for ($index = 0; $index -lt $domains.Count; $index++) {
    if ($updatedParameters[$index] -ne $domains[$index]) {
        throw "Generated LookupKnownIdP parameter at position $($index + 1) does not match its federation domain"
    }
}

if ($updatedContent -ne $extensionsContent) {
    [System.IO.File]::WriteAllText(
        $extensionsFullPath,
        $updatedContent,
        [System.Text.UTF8Encoding]::new($false)
    )
}

Write-Host "Synchronized $($domains.Count) federation domain(s) in $ExtensionsFile" -ForegroundColor Green
