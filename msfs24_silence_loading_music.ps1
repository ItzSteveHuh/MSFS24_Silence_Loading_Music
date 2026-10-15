# MSFS 2024 - Silence Loading Music
# Copyright (C) 2026 ItzSteveHuh
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

<#
Silences the loading-screen music in MSFS 2024 (even when the in-game Music slider is 0).

The loading music lives in the startup sound package
    Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK
which is loaded BEFORE your settings are applied, so the slider can't affect it.
This script replaces the big streamed music clip inside that file with silence of exactly
the same size. It does NOT contain or redistribute any game audio: it only edits your own
copy, and makes a backup (SHARED_MINIMAL.PC.PCK.bak) first.

Finding your install (automatic):
  Steam         - Steam's registry entry, every Steam library (libraryfolders.vdf) and the
                  MSFS 2024 app manifest (app id 2537590).
  Xbox / Store  - the Microsoft.Limitless package plus each drive's .GamingRoot file, which
                  points at the real "XboxGames" folder wherever it is.
  Fallback      - a scan of common folders on every drive.
If more than one install is found (for example Steam AND Store), each one is patched.

Usage (or just double-click the .bat files):
    .\msfs24_silence_loading_music.ps1                 # auto-find your install(s) and patch
    .\msfs24_silence_loading_music.ps1 -Path "<your MSFS 2024 folder>\Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK"
    .\msfs24_silence_loading_music.ps1 -Restore        # put the original back
    .\msfs24_silence_loading_music.ps1 -DryRun         # show what it would do

Close MSFS first. Steam updates / "Verify integrity" restore the original file; just run
this again afterwards. Use at your own risk.
#>
param(
    [string]$Path,
    [switch]$Restore,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ToolVersion   = '1.1.0'
$MinStream     = 1000000          # only touch big streamed clips (the music), not tiny ones
$SteamAppId    = '2537590'        # MSFS 2024 on Steam
$RelPck        = 'fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK'
$IsWindowsHost = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)

# ---------------------------------------------------------------- detection

function Write-Detect([string]$msg) { Write-Host "  $msg" }

# Official content folder: Xbox/Store uses <install>\Content\Packages, Steam uses <install>\Packages.
function Get-PackagesRoot([string]$loc) {
    if (-not $loc) { return $null }
    foreach ($c in @((Join-Path $loc 'Content\Packages'), (Join-Path $loc 'Packages'))) {
        if (Test-Path -LiteralPath $c -PathType Container) { return $c }
    }
    return $null
}

# Library paths listed in Steam's libraryfolders.vdf (backslashes are doubled in the file).
function Read-LibraryFolders([string]$vdf) {
    $out = @()
    foreach ($line in (Get-Content -LiteralPath $vdf)) {
        if ($line -match '"path"\s+"([^"]+)"') { $out += ($Matches[1] -replace '\\\\', '\') }
    }
    return $out
}

function Get-SteamLibraries {
    $roots = @()
    if ($IsWindowsHost) {
        foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
            try {
                $p = Get-ItemProperty -Path $k -ErrorAction Stop
                foreach ($n in @('SteamPath', 'InstallPath')) {
                    if ($p.$n) { $roots += ([string]$p.$n -replace '/', '\') }
                }
            } catch { }
        }
    }
    $libs = @()
    foreach ($r in @($roots | Select-Object -Unique)) {
        $libs += $r
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) { $libs += Read-LibraryFolders $vdf }
    }
    return @($libs | Select-Object -Unique)
}

function Get-SteamInstalls {
    $found = @()
    $libs = @(Get-SteamLibraries)
    if ($libs.Count -eq 0) { Write-Detect 'Steam: not found'; return $found }
    foreach ($lib in $libs) {
        $manifest = Join-Path $lib "steamapps\appmanifest_$SteamAppId.acf"
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        $dir = $null
        foreach ($line in (Get-Content -LiteralPath $manifest)) {
            if ($line -match '"installdir"\s+"([^"]+)"') { $dir = $Matches[1]; break }
        }
        if ($dir) {
            Write-Detect "Steam: MSFS 2024 is installed in library $lib"
            $found += [pscustomobject]@{ Platform = 'Steam'; Install = (Join-Path $lib "steamapps\common\$dir") }
        }
    }
    if ($found.Count -eq 0) { Write-Detect ("Steam: found ({0} librar{1} checked), but MSFS 2024 is not installed there" -f $libs.Count, $(if ($libs.Count -eq 1) { 'y' } else { 'ies' })) }
    return $found
}

# .GamingRoot = "RGBX" + 4-byte version + UTF-16 folder name (e.g. \XboxGames). Returns the folder name.
function Read-GamingRoot([string]$file) {
    try { [byte[]]$b = [System.IO.File]::ReadAllBytes($file) } catch { return $null }
    if ($b.Length -le 8) { return $null }
    if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'RGBX') { return $null }
    $name = [System.Text.Encoding]::Unicode.GetString($b, 8, $b.Length - 8).Trim([char[]]@(0, 92, 32))
    if ($name) { return $name }
    return $null
}

function Get-XboxInstalls {
    $found = @()
    $pkg = $null
    if ($IsWindowsHost) {
        try { $pkg = Get-AppxPackage -Name 'Microsoft.Limitless' -ErrorAction Stop } catch { }
    }
    $hits = @()
    # 1) .GamingRoot on every drive -> the real Xbox games folder
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($d.Root -notmatch '^[A-Za-z]:\\$') { continue }
        $gr = Join-Path $d.Root '.GamingRoot'
        if (-not (Test-Path -LiteralPath $gr -PathType Leaf)) { continue }
        $name = Read-GamingRoot $gr
        if (-not $name) { continue }
        $gamesRoot = Join-Path $d.Root $name
        if (-not (Test-Path -LiteralPath $gamesRoot -PathType Container)) { continue }
        foreach ($c in @(Get-ChildItem -LiteralPath $gamesRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($c.Name -like '*Flight Simulator 2024*' -and (Get-PackagesRoot $c.FullName)) { $hits += $c.FullName }
        }
    }
    # 2) fallback: link target of the package registration folder
    if ($hits.Count -eq 0 -and $pkg -and $pkg.InstallLocation) {
        $item = Get-Item -LiteralPath $pkg.InstallLocation -Force -ErrorAction SilentlyContinue
        if ($item -and $item.Target) {
            $t = @($item.Target)[0]
            if (Get-PackagesRoot $t) { $hits += $t }
        }
    }
    foreach ($h in @($hits | Select-Object -Unique)) {
        Write-Detect "Xbox / Microsoft Store: MSFS 2024 is installed at $h"
        $found += [pscustomobject]@{ Platform = 'Xbox / Microsoft Store'; Install = $h }
    }
    if ($found.Count -eq 0) {
        if ($pkg) { Write-Detect 'Xbox / Microsoft Store: package is registered, but the install folder could not be located' }
        else      { Write-Detect 'Xbox / Microsoft Store: not found' }
    }
    return $found
}

# Last resort: common folders on every drive (the way v1.0 did it).
function Get-FallbackFiles {
    $out = @()
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $drive = $d.Root
        $roots = @(
            'SteamLibrary\steamapps\common\MSFS2024',
            'Program Files (x86)\Steam\steamapps\common\MSFS2024',
            'Program Files\Steam\steamapps\common\MSFS2024',
            'Steam\steamapps\common\MSFS2024',
            'XboxGames\Microsoft Flight Simulator 2024\Content'
        )
        foreach ($r in $roots) {
            $f = Join-Path (Join-Path $drive $r) ('Packages\' + $RelPck)
            if (Test-Path -LiteralPath $f -PathType Leaf) { $out += $f }
        }
    }
    return $out
}

# Returns objects with Platform + File for every install that actually contains the startup package.
function Find-Targets {
    $targets = @()
    $installs = @()
    $installs += @(Get-SteamInstalls)
    $installs += @(Get-XboxInstalls)
    foreach ($i in $installs) {
        $pr = Get-PackagesRoot $i.Install
        $f = $null
        if ($pr) { $f = Join-Path $pr $RelPck }
        if ($f -and (Test-Path -LiteralPath $f -PathType Leaf)) {
            $targets += [pscustomobject]@{ Platform = $i.Platform; File = $f }
        } else {
            Write-Detect "$($i.Platform): install found at $($i.Install), but SHARED_MINIMAL.PC.PCK is not in it"
        }
    }
    if ($targets.Count -eq 0) {
        Write-Detect 'Trying common install folders on every drive...'
        foreach ($f in @(Get-FallbackFiles | Select-Object -Unique)) {
            $targets += [pscustomobject]@{ Platform = 'Detected by folder scan'; File = $f }
        }
    }
    return @($targets | Group-Object File | ForEach-Object { $_.Group[0] })
}

# ---------------------------------------------------------------- Wwise PCK + patching

function Get-FmtTag([byte[]]$b, [int]$start, [int]$len) {
    $p = $start + 12
    $end = $start + $len
    while (($p + 8) -le $end) {
        $id = [System.Text.Encoding]::ASCII.GetString($b, $p, 4)
        $sz = [BitConverter]::ToUInt32($b, $p + 4)
        if ($id -eq 'fmt ') { return [int][BitConverter]::ToUInt16($b, $p + 8) }
        $p += 8 + $sz + ($sz -band 1)
    }
    return -1
}

function New-SilentWem([int]$size) {
    # Silent stereo 48 kHz 16-bit PCM RIFF/WAVE of exactly $size bytes.
    $odd = $size -band 1
    $total = $size - $odd
    $n = [int]([math]::Floor(($total - 76) / 4) * 4)
    $k = $total - 76 - $n
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($ms)
    $ascii = [System.Text.Encoding]::ASCII
    $bodyLen = 4 + (8 + 40) + (8 + $n) + (8 + $k)
    $w.Write($ascii.GetBytes('RIFF')); $w.Write([uint32]$bodyLen)
    $w.Write($ascii.GetBytes('WAVE'))
    $w.Write($ascii.GetBytes('fmt ')); $w.Write([uint32]40)
    $w.Write([uint16]0xFFFE); $w.Write([uint16]2); $w.Write([uint32]48000); $w.Write([uint32]192000)
    $w.Write([uint16]4); $w.Write([uint16]16); $w.Write([uint16]22); $w.Write([uint16]16); $w.Write([uint32]3)
    $w.Write([byte[]](0x01,0x00,0x00,0x00,0x00,0x00,0x10,0x00,0x80,0x00,0x00,0xAA,0x00,0x38,0x9B,0x71))
    $w.Write($ascii.GetBytes('data')); $w.Write([uint32]$n); $w.Write((New-Object byte[] $n))
    $w.Write($ascii.GetBytes('JUNK')); $w.Write([uint32]$k); $w.Write((New-Object byte[] $k))
    if ($odd) { $w.Write([byte]0) }
    $w.Flush()
    $bytes = $ms.ToArray()
    if ($bytes.Length -ne $size) { throw "internal error: built $($bytes.Length) bytes, wanted $size" }
    return ,$bytes
}

function Get-Streams([byte[]]$d) {
    if ([System.Text.Encoding]::ASCII.GetString($d, 0, 4) -ne 'AKPK') { throw 'not a Wwise AKPK package' }
    $langSz = [BitConverter]::ToUInt32($d, 12)
    $bankSz = [BitConverter]::ToUInt32($d, 16)
    $stmSz  = [BitConverter]::ToUInt32($d, 20)
    $pos = 28 + $langSz + $bankSz            # skip language map + soundbank table
    $list = @()
    if ($stmSz -ge 4) {
        $count = [BitConverter]::ToUInt32($d, $pos)
        for ($i = 0; $i -lt $count; $i++) {
            $e = $pos + 4 + 20 * $i
            $id    = [BitConverter]::ToUInt32($d, $e)
            $blk   = [BitConverter]::ToUInt32($d, $e + 4)
            $size  = [BitConverter]::ToUInt32($d, $e + 8)
            $start = [BitConverter]::ToUInt32($d, $e + 12)
            if ($blk -eq 0) { $blk = 1 }
            $list += ,@([uint64]$id, ([uint64]$start * [uint64]$blk), [uint64]$size)
        }
    }
    return ,$list
}

# Patch (or restore) one file. Returns $true on success / nothing to do, $false on a problem.
function Invoke-OnFile([string]$file) {
    $bak = "$file.bak"

    if ($Restore) {
        if (-not (Test-Path -LiteralPath $bak)) { Write-Host "  No backup found ($bak); nothing to restore."; return $false }
        if ($DryRun) { Write-Host '  Would restore from backup.'; return $true }
        try {
            Set-ItemProperty -LiteralPath $file -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $bak -Destination $file -Force
        } catch { Write-Host "  Couldn't restore ($_). Close the sim, or try running as Administrator."; return $false }
        Write-Host '  Restored original from backup.'
        return $true
    }

    try { [byte[]]$data = [System.IO.File]::ReadAllBytes($file) } catch { Write-Host "  Couldn't read the file ($_)."; return $false }
    try { $streams = Get-Streams $data } catch { Write-Host "  Unexpected file format ($_). Not touching it."; return $false }

    $todo = @(); $found = 0
    foreach ($s in $streams) {
        $off = [int64]$s[1]; $size = [int64]$s[2]
        if ($size -lt $MinStream -or ($off + $size) -gt $data.Length) { continue }
        if ([System.Text.Encoding]::ASCII.GetString($data, [int]$off, 4) -ne 'RIFF') { continue }
        $found++
        if ((Get-FmtTag $data ([int]$off) ([int]$size)) -eq 0xFFFF) { $todo += ,@($s[0], $off, $size) }
    }
    if ($found -eq 0) { Write-Host '  No streamed music clip found. Game version may have changed; not touching the file.'; return $false }
    if ($todo.Count -eq 0) { Write-Host '  Already patched (streamed clip is already silent). Nothing to do.'; return $true }

    foreach ($t in $todo) { Write-Host ("  Silencing stream {0} ({1:N1} MB at offset {2})" -f $t[0], ($t[2] / 1e6), $t[1]) }
    if ($DryRun) { Write-Host '  Dry run - no changes made.'; return $true }

    try {
        if (-not (Test-Path -LiteralPath $bak)) {
            Copy-Item -LiteralPath $file -Destination $bak
            Write-Host "  Backup saved: $bak"
        } else {
            Write-Host "  Backup already exists, keeping it: $bak"
        }
    } catch { Write-Host "  Couldn't create the backup ($_). Close the sim, or try running as Administrator."; return $false }

    foreach ($t in $todo) {
        [byte[]]$silent = New-SilentWem ([int]$t[2])
        [Array]::Copy($silent, 0, $data, [int]$t[1], $silent.Length)
    }
    try {
        Set-ItemProperty -LiteralPath $file -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllBytes($file, $data)
    } catch {
        Write-Host "  Couldn't write the file ($_). Close the sim, or try running as Administrator."
        return $false
    }

    [byte[]]$check = [System.IO.File]::ReadAllBytes($file)
    $ok = ($check.Length -eq $data.Length)
    foreach ($t in $todo) { if ((Get-FmtTag $check ([int]$t[1]) ([int]$t[2])) -ne 0xFFFE) { $ok = $false } }
    if ($ok) { Write-Host '  Done.'; return $true }
    Write-Host '  WARNING: verification failed - run with -Restore.'
    return $false
}

# ---------------------------------------------------------------- main
# (Stops here when the file is dot-sourced, so the functions above can be tested on their own.)
if ($MyInvocation.InvocationName -eq '.') { return }

Write-Host "MSFS 2024 - Silence Loading Music v$ToolVersion"

if ($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Host "The file you gave doesn't exist: $Path"
        exit 1
    }
    $targets = @([pscustomobject]@{ Platform = 'Manual path'; File = $Path })
} else {
    Write-Host 'Looking for your MSFS 2024 install...'
    $targets = @(Find-Targets)
}

if ($targets.Count -eq 0) {
    Write-Host ''
    Write-Host "Couldn't find SHARED_MINIMAL.PC.PCK automatically."
    Write-Host 'Run again with the full path to the file, using YOUR install folder:'
    Write-Host '  .\msfs24_silence_loading_music.ps1 -Path "<your MSFS 2024 folder>\Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK"'
    Write-Host 'If you report this problem, please include everything printed above.'
    exit 1
}

$failed = 0
foreach ($t in $targets) {
    Write-Host ''
    Write-Host "[$($t.Platform)] $($t.File)"
    if (-not (Invoke-OnFile $t.File)) { $failed++ }
}
if ($failed -gt 0) { exit 1 }
