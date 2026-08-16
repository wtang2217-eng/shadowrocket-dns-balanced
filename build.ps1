[CmdletBinding(DefaultParameterSetName = 'Url')]
param(
    [Parameter(ParameterSetName = 'Url')]
    [ValidatePattern('^https://')]
    [string]$SourceUrl = 'https://johnshall.github.io/Shadowrocket-ADBlock-Rules-Forever/sr_top500_whitelist_ad.conf',

    [Parameter(Mandatory = $true, ParameterSetName = 'File')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$SourcePath,

    [ValidatePattern('^https://')]
    [string]$AddonSourceUrl = 'https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Surge-RULE-SET-Only.Ads.list',

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AddonSourcePath,

    [string]$OutputDirectory,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$MinimumRuleCount = 0,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$MinimumAddonRuleCount = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$addonBeginMarker = '# BEGIN CODEX MANAGED AWAvenue Only.Ads'
$addonEndMarker = '# END CODEX MANAGED AWAvenue Only.Ads'

function Test-SuffixCoverage {
    param(
        [Parameter(Mandatory = $true)]$Suffixes,
        [Parameter(Mandatory = $true)][string]$Value,
        [bool]$IncludeSelf = $true
    )

    $probe = $Value
    if (-not $IncludeSelf) {
        $firstDot = $probe.IndexOf('.')
        if ($firstDot -lt 0) { return $false }
        $probe = $probe.Substring($firstDot + 1)
    }

    while (-not [string]::IsNullOrWhiteSpace($probe)) {
        if ($Suffixes.Contains($probe)) { return $true }
        $dot = $probe.IndexOf('.')
        if ($dot -lt 0) { break }
        $probe = $probe.Substring($dot + 1)
    }

    return $false
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = $PSScriptRoot
}

if ($PSCmdlet.ParameterSetName -eq 'File') {
    $resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    $sourceText = [System.IO.File]::ReadAllText($resolvedSourcePath, $utf8)
    $includedFileName = [System.IO.Path]::GetFileName($resolvedSourcePath)
    $sourceDescription = $resolvedSourcePath
}
else {
    $webClient = New-Object System.Net.WebClient
    try {
        $sourceBytes = $webClient.DownloadData($SourceUrl)
    }
    finally {
        $webClient.Dispose()
    }
    $sourceText = $utf8.GetString($sourceBytes)
    $includedFileName = [System.IO.Path]::GetFileName(([uri]$SourceUrl).AbsolutePath)
    $sourceDescription = $SourceUrl
}

if (-not [string]::IsNullOrWhiteSpace($AddonSourcePath)) {
    $resolvedAddonSourcePath = (Resolve-Path -LiteralPath $AddonSourcePath).Path
    $addonText = [System.IO.File]::ReadAllText($resolvedAddonSourcePath, $utf8)
    $addonDescription = $resolvedAddonSourcePath
}
else {
    $addonWebClient = New-Object System.Net.WebClient
    try {
        $addonBytes = $addonWebClient.DownloadData($AddonSourceUrl)
    }
    finally {
        $addonWebClient.Dispose()
    }
    $addonText = $utf8.GetString($addonBytes)
    $addonDescription = $AddonSourceUrl
}

$normalized = (($sourceText -replace "`r`n", "`n") -replace "`r", "`n")
$lines = @($normalized -split "`n")
$generalIndex = [Array]::IndexOf($lines, '[General]')
$ruleIndex = [Array]::IndexOf($lines, '[Rule]')

if ($generalIndex -lt 0 -or $ruleIndex -lt 0 -or $generalIndex -ge $ruleIndex) {
    throw 'Source must contain [General] before [Rule].'
}

$ruleEndIndex = $lines.Count
for ($index = $ruleIndex + 1; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match '^\s*\[[^]]+\]\s*$') {
        $ruleEndIndex = $index
        break
    }
}

$addonBeginIndexes = New-Object System.Collections.Generic.List[int]
$addonEndIndexes = New-Object System.Collections.Generic.List[int]
for ($index = 0; $index -lt $lines.Count; $index++) {
    $trimmedLine = $lines[$index].Trim()
    if ($trimmedLine -ceq $addonBeginMarker) { $addonBeginIndexes.Add($index) }
    if ($trimmedLine -ceq $addonEndMarker) { $addonEndIndexes.Add($index) }
}

if ($addonBeginIndexes.Count -ne $addonEndIndexes.Count -or $addonBeginIndexes.Count -gt 1) {
    throw 'Source contains a malformed or duplicated AWAvenue managed block.'
}

if ($addonBeginIndexes.Count -eq 1) {
    $managedBlockStart = $addonBeginIndexes[0]
    $managedBlockEnd = $addonEndIndexes[0]
    if ($managedBlockStart -le $ruleIndex -or $managedBlockEnd -le $managedBlockStart -or $managedBlockEnd -ge $ruleEndIndex) {
        throw 'AWAvenue managed block must be fully contained inside [Rule].'
    }

    $unmanagedLines = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($index -ge $managedBlockStart -and $index -le $managedBlockEnd) { continue }
        $unmanagedLines.Add($lines[$index])
    }
    $lines = @($unmanagedLines)

    $generalIndex = [Array]::IndexOf($lines, '[General]')
    $ruleIndex = [Array]::IndexOf($lines, '[Rule]')
    $ruleEndIndex = $lines.Count
    for ($index = $ruleIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\[[^]]+\]\s*$') {
            $ruleEndIndex = $index
            break
        }
    }
}

$ruleCount = 0
for ($index = $ruleIndex + 1; $index -lt $ruleEndIndex; $index++) {
    if (-not [string]::IsNullOrWhiteSpace($lines[$index]) -and $lines[$index] -notmatch '^\s*#') {
        $ruleCount++
    }
}
if ($ruleCount -lt $MinimumRuleCount) {
    throw "Source contains $ruleCount active rules; expected at least $MinimumRuleCount."
}

$addonNormalized = (($addonText -replace "`r`n", "`n") -replace "`r", "`n")
$addonLines = @($addonNormalized -split "`n")
$addonInputRuleCount = 0
$addonUniqueKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$addonRules = New-Object System.Collections.Generic.List[object]

for ($index = 0; $index -lt $addonLines.Count; $index++) {
    $line = $addonLines[$index].Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }

    if ($line -notmatch '^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD)\s*,\s*([^,\s]+)\s*$') {
        throw "Addon source contains an unsupported or malformed rule at line $($index + 1): $line"
    }

    $ruleType = $Matches[1].ToUpperInvariant()
    $ruleValue = $Matches[2].Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($ruleValue) -or $ruleValue.StartsWith('.') -or $ruleValue.EndsWith('.') -or $ruleValue.Contains('..')) {
        throw "Addon source contains an invalid rule value at line $($index + 1): $line"
    }
    if (($ruleType -eq 'DOMAIN' -or $ruleType -eq 'DOMAIN-SUFFIX') -and $ruleValue -match '[/*?]') {
        throw "Addon source contains an invalid domain rule at line $($index + 1): $line"
    }

    $addonInputRuleCount++
    $ruleKey = "$ruleType,$ruleValue"
    if ($addonUniqueKeys.Add($ruleKey)) {
        $addonRules.Add([pscustomobject]@{ Type = $ruleType; Value = $ruleValue })
    }
}

if ($addonRules.Count -lt $MinimumAddonRuleCount) {
    throw "Addon source contains $($addonRules.Count) unique supported rules; expected at least $MinimumAddonRuleCount."
}

$existingRejectDomains = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$existingRejectSuffixes = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$existingRejectKeywords = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

for ($index = $ruleIndex + 1; $index -lt $ruleEndIndex; $index++) {
    $line = $lines[$index].Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    $parts = $line.Split(',')
    if ($parts.Count -lt 3 -or $parts[2].Trim() -notmatch '^(?i:REJECT)(?:-|$)') { continue }

    $ruleType = $parts[0].Trim().ToUpperInvariant()
    $ruleValue = $parts[1].Trim().TrimStart('.').ToLowerInvariant()
    if ($ruleType -eq 'DOMAIN') { [void]$existingRejectDomains.Add($ruleValue) }
    elseif ($ruleType -eq 'DOMAIN-SUFFIX') { [void]$existingRejectSuffixes.Add($ruleValue) }
    elseif ($ruleType -eq 'DOMAIN-KEYWORD') { [void]$existingRejectKeywords.Add($ruleValue) }
}

$addonSuffixes = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($rule in $addonRules) {
    if ($rule.Type -eq 'DOMAIN-SUFFIX') { [void]$addonSuffixes.Add($rule.Value) }
}

$addedRules = New-Object System.Collections.Generic.List[object]
foreach ($rule in $addonRules) {
    $covered = $false
    if ($rule.Type -eq 'DOMAIN') {
        $covered = $existingRejectDomains.Contains($rule.Value) -or
            (Test-SuffixCoverage -Suffixes $existingRejectSuffixes -Value $rule.Value) -or
            (Test-SuffixCoverage -Suffixes $addonSuffixes -Value $rule.Value)
    }
    elseif ($rule.Type -eq 'DOMAIN-SUFFIX') {
        $covered = (Test-SuffixCoverage -Suffixes $existingRejectSuffixes -Value $rule.Value) -or
            (Test-SuffixCoverage -Suffixes $addonSuffixes -Value $rule.Value -IncludeSelf $false)
    }
    elseif ($rule.Type -eq 'DOMAIN-KEYWORD') {
        $covered = $existingRejectKeywords.Contains($rule.Value)
    }

    if (-not $covered) { $addedRules.Add($rule) }
}

$addonManagedLines = New-Object System.Collections.Generic.List[string]
$addonManagedLines.Add($addonBeginMarker)
$addonManagedLines.Add("# Source: $addonDescription")
$addonManagedLines.Add("# Input rules: $addonInputRuleCount")
$addonManagedLines.Add("# Unique input rules: $($addonRules.Count)")
$addonManagedLines.Add("# Added rules: $($addedRules.Count)")
foreach ($rule in $addedRules) {
    $addonManagedLines.Add("$($rule.Type),$($rule.Value),REJECT")
}
$addonManagedLines.Add($addonEndMarker)

$managedHeader = '# Daily performance + DNS leak protection (Shadowrocket stable)'
$managedKeys = @(
    'ipv6',
    'prefer-ipv6',
    'dns-server',
    'fallback-dns-server',
    'dns-direct-system',
    'dns-direct-fallback-proxy',
    'private-ip-answer',
    'udp-policy-not-supported-behaviour',
    'block-quic',
    'hijack-dns'
)

$managedLines = @(
    'ipv6 = false',
    'prefer-ipv6 = false',
    'dns-server = https://dns.alidns.com/dns-query, https://doh.pub/dns-query',
    'fallback-dns-server = https://223.5.5.5/dns-query#no-h3, https://1.1.1.1/dns-query#no-h3',
    'dns-direct-system = false',
    'dns-direct-fallback-proxy = true',
    'private-ip-answer = true',
    'udp-policy-not-supported-behaviour = REJECT',
    'block-quic = all-proxy',
    'hijack-dns = 8.8.8.8:53, 8.8.4.4:53, 1.1.1.1:53, 1.0.0.1:53, 9.9.9.9:53, 149.112.112.112:53, 223.5.5.5:53, 223.6.6.6:53, 119.29.29.29:53, 182.254.116.116:53, 114.114.114.114:53, 114.114.115.115:53'
)

$generalEndIndex = $ruleIndex
for ($index = $generalIndex + 1; $index -lt $ruleIndex; $index++) {
    if ($lines[$index] -match '^\s*\[[^]]+\]\s*$') {
        $generalEndIndex = $index
        break
    }
}

$prefix = New-Object System.Collections.Generic.List[string]
for ($index = 0; $index -lt $generalEndIndex; $index++) {
    $line = $lines[$index]
    if ($index -gt $generalIndex -and ($line.Trim() -ceq $managedHeader -or $line.Trim() -ceq '# Balanced DNS leak protection (Shadowrocket only)')) {
        continue
    }
    if ($index -gt $generalIndex -and $line -match '^\s*([A-Za-z0-9-]+)\s*=') {
        $key = $Matches[1].ToLowerInvariant()
        if ($managedKeys -contains $key) { continue }
    }
    $prefix.Add($line)
}

while ($prefix.Count -gt 0 -and [string]::IsNullOrWhiteSpace($prefix[$prefix.Count - 1])) {
    $prefix.RemoveAt($prefix.Count - 1)
}

$prefix.Add('')
$prefix.Add($managedHeader)
foreach ($line in $managedLines) {
    $prefix.Add($line)
}
$prefix.Add('')

for ($index = $generalEndIndex; $index -lt $ruleIndex; $index++) {
    $prefix.Add($lines[$index])
}

$tail = New-Object System.Collections.Generic.List[string]
$tail.Add($lines[$ruleIndex])
foreach ($line in $addonManagedLines) {
    $tail.Add($line)
}
for ($index = $ruleIndex + 1; $index -lt $lines.Count; $index++) {
    $tail.Add($lines[$index])
}
$fullLines = @($prefix) + $tail
$fullText = $fullLines -join "`n"

$extensionLines = @(
    '# Shadowrocket daily performance + DNS leak protection',
    '# If the base config is renamed, update the include filename below.',
    '[General]',
    "include = $includedFileName"
) + $managedLines
$extensionText = (($extensionLines -join "`n").TrimEnd("`n")) + "`n"

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
$fullOutputPath = Join-Path $resolvedOutputDirectory 'sr_top500_whitelist_ad_dns_balanced.conf'
$extensionOutputPath = Join-Path $resolvedOutputDirectory 'sr_top500_dns_balanced_extension.conf'

[System.IO.File]::WriteAllText($fullOutputPath, $fullText, $utf8)
[System.IO.File]::WriteAllText($extensionOutputPath, $extensionText, $utf8)

Write-Output "Source: $sourceDescription"
Write-Output "Rules: $ruleCount"
Write-Output "Addon source: $addonDescription"
Write-Output "Addon input rules: $addonInputRuleCount"
Write-Output "Addon unique rules: $($addonRules.Count)"
Write-Output "Addon added rules: $($addedRules.Count)"
Write-Output "Complete: $fullOutputPath"
Write-Output "Extension: $extensionOutputPath"
