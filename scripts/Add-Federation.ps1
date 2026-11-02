<#
.SYNOPSIS
    Adds a new federation partner to the B2C custom policy configuration.

.DESCRIPTION
    Interactive script that:
    1. Prompts for IDP type, display name, IDP value, JIT, and metadata URLs
    2. Auto-detects the next federation partner number
    3. Generates the technical profile XML from a template
    4. Adds SubJourney entries (ClaimsProviderSelection + ClaimsExchange)
    5. Adds settings to appsettings.json for Stage and (optionally) Prod
#>

param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$FederationsFile = Join-Path $RepoRoot "B2C_1A_Connect_Federations.xml"
$AppSettingsFile = Join-Path $RepoRoot "appsettings.json"
$TemplatesDir = Join-Path $RepoRoot "federationTemplates"

# --- Template selection ---

$templates = @{
    "1" = @{ Name = "Entra ID (SAML)";   File = "entra-saml.xmltemplate";    Protocol = "SAML" }
    "2" = @{ Name = "Ping (SAML)";       File = "ping-saml.xmltemplate";     Protocol = "SAML" }
    "3" = @{ Name = "OneLogin (SAML)";   File = "onelogin-saml.xmltemplate"; Protocol = "SAML" }
    "4" = @{ Name = "Okta (SAML)";       File = "okta-saml.xmltemplate";     Protocol = "SAML" }
    "5" = @{ Name = "Entra ID (OIDC)";   File = "entra-oidc.xmltemplate";    Protocol = "OIDC" }
    "6" = @{ Name = "Okta (OIDC)";       File = "okta-oidc.xmltemplate";     Protocol = "OIDC" }
}

Write-Host "`nSelect IDP template:" -ForegroundColor Cyan
foreach ($key in ($templates.Keys | Sort-Object { [int]$_ })) {
    Write-Host "  $key) $($templates[$key].Name)"
}

do {
    $templateChoice = Read-Host "`nChoice (1-6)"
} while (-not $templates.ContainsKey($templateChoice))

$selectedTemplate = $templates[$templateChoice]
Write-Host "Selected: $($selectedTemplate.Name)" -ForegroundColor Green

# --- Gather inputs ---

do {
    $displayName = (Read-Host "`nDisplay name (e.g., Kraft)").Trim()
} while ([string]::IsNullOrWhiteSpace($displayName))

do {
    $idpValue = (Read-Host "IDP value / tenant name (e.g., kraft.com)").Trim()
} while ([string]::IsNullOrWhiteSpace($idpValue))

# Tech profile name: strip non-alphanumeric, use as suffix
$techProfileSuffix = $displayName -replace '[^a-zA-Z0-9]', ''

# Escape XML special characters for use in XML attributes/elements
$displayNameXml = $displayName -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'

$jitEnabled = $false
$jitResponse = (Read-Host "JIT enabled? (y/N)").Trim().ToLower()
if ($jitResponse -eq "y" -or $jitResponse -eq "yes") {
    $jitEnabled = $true
}

do {
    $stageMetadata = (Read-Host "`nStage metadata URL").Trim()
} while ([string]::IsNullOrWhiteSpace($stageMetadata))

$prodMetadata = (Read-Host "Prod metadata URL (leave blank to skip)").Trim()

# --- Auto-detect next number ---

$federationsContent = Get-Content $FederationsFile -Raw
$numbers = [regex]::Matches($federationsContent, 'FederationPartner-(\d+)') | ForEach-Object { [int]$_.Groups[1].Value }
$nextNumber = ($numbers | Measure-Object -Maximum).Maximum + 1

Write-Host "`nNext federation partner number: $nextNumber" -ForegroundColor Yellow

# --- Determine protocol suffix for SubJourney entries ---

$protocolSuffix = $selectedTemplate.Protocol

# --- Build JIT claims block ---

$jitClaimsBlock = ""
if ($jitEnabled) {
    $jitClaimsBlock = @"
                        <!-- JIT claims -->
                        <OutputClaim ClaimTypeReferenceId="jitEnabled" DefaultValue="true" AlwaysUseDefaultValue="true" />
                        <OutputClaim ClaimTypeReferenceId="jit_company" PartnerClaimType="company" />
                        <OutputClaim ClaimTypeReferenceId="jit_country" PartnerClaimType="country" />
                        <OutputClaim ClaimTypeReferenceId="jit_language" PartnerClaimType="language" />
                        <OutputClaim ClaimTypeReferenceId="jit_culture" PartnerClaimType="culture" />
                        <OutputClaim ClaimTypeReferenceId="jit_currency" PartnerClaimType="currency" />
                        <OutputClaim ClaimTypeReferenceId="jit_timezone" PartnerClaimType="timezone" />
                        <OutputClaim ClaimTypeReferenceId="jit_externalid" PartnerClaimType="assertionSubjectName" />
                        <OutputClaim ClaimTypeReferenceId="jit_rolename" PartnerClaimType="rolename" />
                        <OutputClaim ClaimTypeReferenceId="jit_unitnumber" PartnerClaimType="unitnumber" />
                        <OutputClaim ClaimTypeReferenceId="ignorePreAuthSignInName" DefaultValue="false" AlwaysUseDefaultValue="true" />
"@
}

# --- Generate technical profile from template ---

$templatePath = Join-Path $TemplatesDir $selectedTemplate.File
$templateContent = Get-Content $templatePath -Raw
$technicalProfile = $templateContent `
    -replace '{{NUMBER}}', $nextNumber `
    -replace '{{DISPLAY_NAME}}', $displayNameXml `
    -replace '{{IDP_VALUE}}', $idpValue

if ($jitEnabled) {
    $technicalProfile = $technicalProfile -replace '{{JIT_CLAIMS}}', $jitClaimsBlock
} else {
    # Remove the placeholder line entirely
    $technicalProfile = $technicalProfile -replace '[ \t]*{{JIT_CLAIMS}}\r?\n', ''
}

# --- 1. Insert technical profile into Federations XML ---

Write-Host "`nUpdating $FederationsFile..." -ForegroundColor Cyan

# Insert before </ClaimsProviders>
$newClaimsProviderBlock = "`n$technicalProfile"
$federationsContent = $federationsContent -replace '(\s*</ClaimsProviders>)', "$newClaimsProviderBlock`$1"

# --- 2. Add SubJourney entries ---

# ClaimsProviderSelection entry
$selectionEntry = "                        <ClaimsProviderSelection TargetClaimsExchangeId=""AAD-FederationPartner-$nextNumber-$protocolSuffix-CE"" />"
$federationsContent = $federationsContent -replace `
    '(                        <ClaimsProviderSelection TargetClaimsExchangeId="AAD-ORG-OIDC-CE" />)', `
    "$selectionEntry`n`$1"

# ClaimsExchange entry
$exchangeEntry = "                        <ClaimsExchange Id=""AAD-FederationPartner-$nextNumber-$protocolSuffix-CE"" TechnicalProfileReferenceId=""Step-16-FederationPartner-{Settings:FederationPartner-$nextNumber-TechProfileName}"" />"
$federationsContent = $federationsContent -replace `
    '(                        <ClaimsExchange Id="AAD-ORG-OIDC-CE")', `
    "$exchangeEntry`n`$1"

# Write back
Set-Content -Path $FederationsFile -Value $federationsContent -NoNewline

Write-Host "  Added ClaimsProvider, ClaimsProviderSelection, and ClaimsExchange for partner $nextNumber" -ForegroundColor Green

# --- 3. Add appsettings entries ---

Write-Host "`nUpdating $AppSettingsFile..." -ForegroundColor Cyan

$appSettingsContent = Get-Content $AppSettingsFile -Raw

# Build settings entries based on protocol
if ($protocolSuffix -eq "OIDC") {
    $settingsBlock = @"
                "FederationPartner-$nextNumber-TechProfileName":"$techProfileSuffix-OIDC",
                "FederationPartner-$nextNumber-ProviderName":"TODO",
                "FederationPartner-$nextNumber-TenantName":"$idpValue",
                "FederationPartner-$nextNumber-ClientId":"TODO",
                "FederationPartner-$nextNumber-PolicyKey":"B2C_1A_${techProfileSuffix}OIDCSecret",
                "FederationPartner-$nextNumber-MetadataUrl":"METADATA_URL_PLACEHOLDER",
"@
} else {
    $settingsBlock = @"
                "FederationPartner-$nextNumber-TechProfileName":"$techProfileSuffix",
                "FederationPartner-$nextNumber-TenantName":"$idpValue",
                "FederationPartner-$nextNumber-MetadataUrl":"METADATA_URL_PLACEHOLDER",
"@
}

# Helper: insert settings block into a specific environment section
function Add-SettingsToEnvironment {
    param(
        [string]$Content,
        [string]$EnvName,
        [string]$SettingsBlock,
        [string]$MetadataUrl
    )

    if ([string]::IsNullOrWhiteSpace($MetadataUrl)) {
        return $Content
    }

    $blockWithUrl = $SettingsBlock -replace 'METADATA_URL_PLACEHOLDER', $MetadataUrl

    # Find the LoadUri line for this environment to insert before it
    # Strategy: find the environment's "Name": "EnvName" line, then find the first LoadUri line after it
    $envPattern = """Name"":\s*""$EnvName"""
    $envMatch = [regex]::Match($Content, $envPattern)

    if (-not $envMatch.Success) {
        Write-Host "  WARNING: Could not find $EnvName environment in appsettings.json" -ForegroundColor Red
        return $Content
    }

    # From the env match position, find the first LoadUri line
    $afterEnv = $Content.Substring($envMatch.Index)
    $loadUriMatch = [regex]::Match($afterEnv, '(\s*"LoadUri\.)')

    if ($loadUriMatch.Success) {
        $insertPos = $envMatch.Index + $loadUriMatch.Index
        $Content = $Content.Insert($insertPos, "`n$blockWithUrl")
        Write-Host "  Added settings for partner $nextNumber to $EnvName" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Could not find LoadUri insertion point in $EnvName" -ForegroundColor Red
    }

    return $Content
}

$appSettingsContent = Add-SettingsToEnvironment -Content $appSettingsContent -EnvName "Stage" -SettingsBlock $settingsBlock -MetadataUrl $stageMetadata

if (-not [string]::IsNullOrWhiteSpace($prodMetadata)) {
    $appSettingsContent = Add-SettingsToEnvironment -Content $appSettingsContent -EnvName "Prod" -SettingsBlock $settingsBlock -MetadataUrl $prodMetadata
}

Set-Content -Path $AppSettingsFile -Value $appSettingsContent -NoNewline

# --- Summary ---

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Federation Partner Number: $nextNumber"
Write-Host "Display Name:             $displayName"
Write-Host "IDP Value:                $idpValue"
Write-Host "Template:                 $($selectedTemplate.Name)"
Write-Host "JIT Enabled:              $jitEnabled"
Write-Host "Protocol:                 $protocolSuffix"
Write-Host ""
Write-Host "Files modified:" -ForegroundColor Yellow
Write-Host "  - $FederationsFile"
Write-Host "  - $AppSettingsFile"

if ($protocolSuffix -eq "OIDC") {
    Write-Host ""
    Write-Host "TODO: Update the following placeholders in appsettings.json:" -ForegroundColor Yellow
    Write-Host "  - FederationPartner-$nextNumber-ProviderName"
    Write-Host "  - FederationPartner-$nextNumber-ClientId"
    Write-Host "  - FederationPartner-$nextNumber-PolicyKey (upload key to B2C)"
}

Write-Host ""
Write-Host "Done! Review the changes before committing." -ForegroundColor Green
