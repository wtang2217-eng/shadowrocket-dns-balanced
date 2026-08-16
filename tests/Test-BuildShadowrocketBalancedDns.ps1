[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDirectory = Split-Path -Parent $testDirectory
$builder = Join-Path $projectDirectory 'build.ps1'
$fixture = Join-Path $testDirectory 'fixtures\minimal-upstream.conf'
$addonFixture = Join-Path $testDirectory 'fixtures\awavenue-only-ads.list'
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("shadowrocket-dns-test-" + [guid]::NewGuid().ToString('N'))
$addonBeginMarker = '# BEGIN CODEX MANAGED AWAvenue Only.Ads'
$addonEndMarker = '# END CODEX MANAGED AWAvenue Only.Ads'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Equal {
    param([string]$Expected, [string]$Actual, [string]$Message)
    if ($Expected -cne $Actual) {
        throw "Assertion failed: $Message`nExpected: $Expected`nActual: $Actual"
    }
}

function Normalize-Newlines {
    param([string]$Text)
    return (($Text -replace "`r`n", "`n") -replace "`r", "`n")
}

function Get-RuleTail {
    param([string]$Text)
    $normalized = Normalize-Newlines $Text
    $index = $normalized.IndexOf("[Rule]`n", [System.StringComparison]::Ordinal)
    if ($index -lt 0) { throw 'Missing [Rule] section.' }
    return $normalized.Substring($index)
}

function Remove-ManagedAddonBlock {
    param([string]$Text)
    $lines = @((Normalize-Newlines $Text) -split "`n")
    $start = [Array]::IndexOf($lines, $addonBeginMarker)
    $end = [Array]::IndexOf($lines, $addonEndMarker)
    if ($start -lt 0 -and $end -lt 0) {
        return (Normalize-Newlines $Text)
    }
    if ($start -lt 0 -or $end -le $start) {
        throw 'Malformed managed addon block.'
    }

    $result = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($index -ge $start -and $index -le $end) { continue }
        $result.Add($lines[$index])
    }
    return (@($result) -join "`n")
}

function Get-SectionBody {
    param([string]$Text, [string]$SectionName)
    $lines = @((Normalize-Newlines $Text) -split "`n")
    $sectionIndex = [Array]::IndexOf($lines, $SectionName)
    if ($sectionIndex -lt 0) { throw "Missing $SectionName section." }

    $endIndex = $lines.Count
    for ($index = $sectionIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\[[^]]+\]\s*$') {
            $endIndex = $index
            break
        }
    }

    return @($lines[($sectionIndex + 1)..($endIndex - 1)])
}

[System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null

try {
    $buildOutput = @(
        & $builder -SourcePath $fixture -AddonSourcePath $addonFixture -OutputDirectory $temporaryDirectory -MinimumRuleCount 6 -MinimumAddonRuleCount 9
    )
    Assert-True ($buildOutput -contains 'Addon input rules: 10') 'addon input rule count was not reported'
    Assert-True ($buildOutput -contains 'Addon unique rules: 9') 'addon unique rule count was not reported'
    Assert-True ($buildOutput -contains 'Addon added rules: 3') 'addon added rule count was not reported'

    $fullPath = Join-Path $temporaryDirectory 'sr_top500_whitelist_ad_dns_balanced.conf'
    $extensionPath = Join-Path $temporaryDirectory 'sr_top500_dns_balanced_extension.conf'
    Assert-True (Test-Path -LiteralPath $fullPath -PathType Leaf) 'complete config was not created'
    Assert-True (Test-Path -LiteralPath $extensionPath -PathType Leaf) 'extension config was not created'

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $source = [System.IO.File]::ReadAllText($fixture, $utf8)
    $full = [System.IO.File]::ReadAllText($fullPath, $utf8)
    $extension = [System.IO.File]::ReadAllText($extensionPath, $utf8)

    Assert-Equal (Get-RuleTail $source) (Remove-ManagedAddonBlock (Get-RuleTail $full)) 'source rule tail changed outside managed addon block'
    Assert-True ((Get-RuleTail $full).StartsWith("[Rule]`n$addonBeginMarker`n", [System.StringComparison]::Ordinal)) 'managed addon block is not first in Rule'
    Assert-True (@($full -split [regex]::Escape($addonBeginMarker)).Count -eq 2) 'managed addon begin marker count is not one'
    Assert-True (@($full -split [regex]::Escape($addonEndMarker)).Count -eq 2) 'managed addon end marker count is not one'
    $managedBlockStart = $full.IndexOf($addonBeginMarker, [System.StringComparison]::Ordinal)
    $managedBlockEnd = $full.IndexOf($addonEndMarker, [System.StringComparison]::Ordinal) + $addonEndMarker.Length
    $managedBlock = $full.Substring($managedBlockStart, $managedBlockEnd - $managedBlockStart)

    foreach ($line in @(
        'DOMAIN,unique.example,REJECT',
        'DOMAIN-SUFFIX,newads.example,REJECT',
        'DOMAIN-KEYWORD,-ad-unit,REJECT'
    )) {
        Assert-True ($managedBlock.Contains($line)) "managed addon block lacks: $line"
    }
    Assert-True (@($managedBlock -split [regex]::Escape('DOMAIN,unique.example,REJECT')).Count -eq 2) 'case-insensitive addon duplicate was not removed'

    foreach ($line in @(
        'DOMAIN,ads.example,REJECT',
        'DOMAIN,sub.ads.example,REJECT',
        'DOMAIN,exact.example,REJECT',
        'DOMAIN-SUFFIX,parent.example,REJECT',
        'DOMAIN-SUFFIX,child.parent.example,REJECT',
        'DOMAIN,sub.newads.example,REJECT'
    )) {
        Assert-True (-not $managedBlock.Contains($line)) "semantic duplicate was added: $line"
    }
    Assert-True ($full.Contains('bypass-system = true')) 'unmanaged General key was lost'
    Assert-True ($full.Contains('skip-proxy = 192.168.0.0/16, localhost, *.local, *.lan')) 'skip-proxy was changed'

    $fullGeneralLines = @(Get-SectionBody $full '[General]')
    $extensionGeneralLines = @(Get-SectionBody $extension '[General]')
    $fullHostLines = @(Get-SectionBody $full '[Host]')
    Assert-True ($fullHostLines -ccontains 'dns-server = 192.0.2.53') 'managed-looking key outside General was changed'

    $required = @(
        'ipv6 = false',
        'prefer-ipv6 = false',
        'dns-server = https://dns.alidns.com/dns-query, https://doh.pub/dns-query',
        'fallback-dns-server = https://223.5.5.5/dns-query#no-h3, https://1.1.1.1/dns-query#no-h3',
        'dns-direct-system = false',
        'dns-direct-fallback-proxy = true',
        'private-ip-answer = true',
        'udp-policy-not-supported-behaviour = REJECT',
        'block-quic = always-allow',
        'hijack-dns = 8.8.8.8:53, 8.8.4.4:53, 1.1.1.1:53, 1.0.0.1:53, 9.9.9.9:53, 149.112.112.112:53, 223.5.5.5:53, 223.6.6.6:53, 119.29.29.29:53, 182.254.116.116:53, 114.114.114.114:53, 114.114.115.115:53'
    )

    foreach ($line in $required) {
        Assert-True ($fullGeneralLines -ccontains $line) "complete General section lacks: $line"
        Assert-True ($extensionGeneralLines -ccontains $line) "extension General section lacks: $line"
    }

    $activeFullGeneralLines = $fullGeneralLines | Where-Object { $_ -notmatch '^\s*#' }
    foreach ($key in @('ipv6', 'prefer-ipv6', 'dns-server', 'fallback-dns-server', 'dns-direct-system', 'dns-direct-fallback-proxy', 'private-ip-answer', 'udp-policy-not-supported-behaviour', 'block-quic', 'hijack-dns')) {
        $count = @($activeFullGeneralLines | Where-Object { $_ -match ("^\s*" + [regex]::Escape($key) + "\s*=") }).Count
        Assert-True ($count -eq 1) "managed key '$key' occurs $count times in General"
    }

    Assert-True ($extension.Contains('include = minimal-upstream.conf')) 'extension does not inherit the source filename'
    Assert-True (-not $full.Contains('fallback-dns-server = system')) 'system fallback remains active'
    Assert-True (-not $full.Contains('block-quic = all-proxy')) 'proxied QUIC remains blocked'
    Assert-True (-not $full.Contains('hijack-dns = :53')) 'global port-53 hijack was introduced'
    Assert-True (-not $full.Contains('always-real-ip = *')) 'always-real-ip wildcard was introduced'
    Assert-True (-not $full.Contains('always-ip-address')) 'always-ip-address was introduced'
    Assert-True (-not $full.Contains('direct-dns-server')) 'beta-only direct-dns-server was introduced'
    Assert-True (-not $full.Contains('proxy-dns-server')) 'unverified proxy-dns-server was introduced'

    $minimumRuleGuardTriggered = $false
    try {
        & $builder -SourcePath $fixture -AddonSourcePath $addonFixture -OutputDirectory $temporaryDirectory -MinimumRuleCount 7 -MinimumAddonRuleCount 9
    }
    catch {
        $minimumRuleGuardTriggered = $true
        Assert-True ($_.Exception.Message.Contains('expected at least 7')) 'minimum rule guard failed for an unexpected reason'
    }
    Assert-True $minimumRuleGuardTriggered 'minimum rule guard accepted a truncated source'

    $truncatedAddon = Join-Path $temporaryDirectory 'truncated-addon.list'
    [System.IO.File]::WriteAllText($truncatedAddon, "DOMAIN,one.example`n", $utf8)
    $minimumAddonGuardTriggered = $false
    try {
        & $builder -SourcePath $fixture -AddonSourcePath $truncatedAddon -OutputDirectory $temporaryDirectory -MinimumRuleCount 6 -MinimumAddonRuleCount 2
    }
    catch {
        $minimumAddonGuardTriggered = $true
        Assert-True ($_.Exception.Message.Contains('expected at least 2')) 'minimum addon rule guard failed for an unexpected reason'
    }
    Assert-True $minimumAddonGuardTriggered 'minimum addon rule guard accepted a truncated addon source'

    $invalidAddon = Join-Path $temporaryDirectory 'invalid-addon.list'
    [System.IO.File]::WriteAllText($invalidAddon, "DOMAIN,ok.example`nIP-CIDR,192.0.2.0/24`n", $utf8)
    $invalidAddonGuardTriggered = $false
    try {
        & $builder -SourcePath $fixture -AddonSourcePath $invalidAddon -OutputDirectory $temporaryDirectory -MinimumRuleCount 6 -MinimumAddonRuleCount 1
    }
    catch {
        $invalidAddonGuardTriggered = $true
        Assert-True ($_.Exception.Message.Contains('unsupported or malformed rule')) 'invalid addon guard failed for an unexpected reason'
    }
    Assert-True $invalidAddonGuardTriggered 'invalid addon rule was accepted'

    $secondDirectory = Join-Path $temporaryDirectory 'second'
    [System.IO.Directory]::CreateDirectory($secondDirectory) | Out-Null
    & $builder -SourcePath $fullPath -AddonSourcePath $addonFixture -OutputDirectory $secondDirectory -MinimumRuleCount 6 -MinimumAddonRuleCount 9 | Out-Null
    $secondFullPath = Join-Path $secondDirectory 'sr_top500_whitelist_ad_dns_balanced.conf'
    $secondFull = [System.IO.File]::ReadAllText($secondFullPath, $utf8)
    Assert-Equal $full $secondFull 'repeated build was not idempotent'

    foreach ($path in @($fullPath, $extensionPath, $secondFullPath)) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        Assert-True (-not $hasBom) "$path contains a UTF-8 BOM"
    }

    Write-Output 'PASS: Shadowrocket balanced DNS build tests'
}
finally {
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedTemporaryDirectory = [System.IO.Path]::GetFullPath($temporaryDirectory)
    Assert-True ($resolvedTemporaryDirectory.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) 'refusing to remove a path outside the temporary directory'
    if (Test-Path -LiteralPath $resolvedTemporaryDirectory) {
        Remove-Item -LiteralPath $resolvedTemporaryDirectory -Recurse -Force
    }
}
