<#
MSFS 2024 - silence the loading-screen music (works even when the in-game Music slider is 0).

The loading music lives in the startup sound package
    Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK
which is loaded BEFORE your settings are applied, so the slider can't affect it.
This script replaces the big streamed music clip inside that file with silence of exactly
the same size. It does NOT contain or redistribute any game audio: it only edits your own
copy, and makes a backup (SHARED_MINIMAL.PC.PCK.bak) first.

Usage (or just double-click the .bat files):
    .\msfs24_silence_loading_music.ps1                 # auto-find the file and patch it
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
$MinStream = 1000000   # only touch big streamed clips (the music), not tiny ones
$Rel = 'Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK'

function Find-Pck {
    $drives = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root }
    foreach ($d in $drives) {
        $roots = @(
            (Join-Path $d 'SteamLibrary\steamapps\common\MSFS2024'),
            (Join-Path $d 'Program Files (x86)\Steam\steamapps\common\MSFS2024'),
            (Join-Path $d 'Program Files\Steam\steamapps\common\MSFS2024'),
            (Join-Path $d 'Steam\steamapps\common\MSFS2024'),
            (Join-Path $d 'XboxGames\Microsoft Flight Simulator 2024\Content')
        )
        foreach ($r in $roots) {
            $p = Join-Path $r $Rel
            if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
        }
    }
    return $null
}

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

# ---------------------------------------------------------------- main
if (-not $Path) { $Path = Find-Pck }
if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Host "Couldn't find SHARED_MINIMAL.PC.PCK automatically."
    Write-Host 'Run again with the full path, e.g.:'
    Write-Host '  .\msfs24_silence_loading_music.ps1 -Path "<your MSFS 2024 folder>\Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK"'
    exit 1
}
Write-Host "File: $Path"
$bak = "$Path.bak"

if ($Restore) {
    if (-not (Test-Path -LiteralPath $bak)) { Write-Host "No backup found ($bak); nothing to restore."; exit 1 }
    if ($DryRun) { Write-Host 'Would restore from backup.'; exit 0 }
    Set-ItemProperty -LiteralPath $Path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $bak -Destination $Path -Force
    Write-Host 'Restored original from backup.'
    exit 0
}

[byte[]]$data = [System.IO.File]::ReadAllBytes($Path)
try { $streams = Get-Streams $data } catch { Write-Host "Unexpected file format ($_). Not touching it."; exit 1 }

$todo = @(); $found = 0
foreach ($s in $streams) {
    $off = [int64]$s[1]; $size = [int64]$s[2]
    if ($size -lt $MinStream -or ($off + $size) -gt $data.Length) { continue }
    if ([System.Text.Encoding]::ASCII.GetString($data, [int]$off, 4) -ne 'RIFF') { continue }
    $found++
    if ((Get-FmtTag $data ([int]$off) ([int]$size)) -eq 0xFFFF) { $todo += ,@($s[0], $off, $size) }
}

if ($found -eq 0) { Write-Host 'No streamed music clip found. Game version may have changed; not touching the file.'; exit 1 }
if ($todo.Count -eq 0) { Write-Host 'Already patched (streamed clip is already silent). Nothing to do.'; exit 0 }

foreach ($t in $todo) { Write-Host ("Silencing stream {0} ({1:N1} MB at offset {2})" -f $t[0], ($t[2] / 1e6), $t[1]) }
if ($DryRun) { Write-Host 'Dry run - no changes made.'; exit 0 }

if (-not (Test-Path -LiteralPath $bak)) {
    Copy-Item -LiteralPath $Path -Destination $bak
    Write-Host "Backup saved: $bak"
} else {
    Write-Host "Backup already exists, keeping it: $bak"
}

foreach ($t in $todo) {
    [byte[]]$silent = New-SilentWem ([int]$t[2])
    [Array]::Copy($silent, 0, $data, [int]$t[1], $silent.Length)
}
try {
    Set-ItemProperty -LiteralPath $Path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    [System.IO.File]::WriteAllBytes($Path, $data)
} catch {
    Write-Host "Couldn't write the file ($_). Close the sim, or try running as Administrator."
    exit 1
}

[byte[]]$check = [System.IO.File]::ReadAllBytes($Path)
$ok = ($check.Length -eq $data.Length)
foreach ($t in $todo) { if ((Get-FmtTag $check ([int]$t[1]) ([int]$t[2])) -ne 0xFFFE) { $ok = $false } }
if ($ok) { Write-Host 'Done.' } else { Write-Host 'WARNING: verification failed - run with -Restore.'; exit 1 }
