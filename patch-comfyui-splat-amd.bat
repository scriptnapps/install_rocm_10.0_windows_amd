@echo off
setlocal EnableExtensions EnableDelayedExpansion
title ComfyUI gaussian-splat AMD / ROCm patcher
set "MODE=patch"
set "BACKUP=1"
set "N=0"
set "FAILED="
set "BADOPT="
set "WANTHELP="

echo.
echo  ============================================================
echo   ComfyUI gaussian-splat  --  AMD / ROCm batched-inverse fix
echo  ============================================================
echo.
echo   Patches  comfy_extras\nodes_gaussian_splat.py  so that
echo   torch.linalg.inv on the camera covariance is chunked on ROCm.
echo   Anchor based, so it re-applies cleanly after a ComfyUI update.
echo.
echo   Drop a ComfyUI install folder onto this .bat, e.g.
echo       ...\ComfyUI-Installs\111
echo   or the workspace folder, or the .py file itself.
echo.
echo   Options:  /check      report what would change, write nothing
echo             /nobackup   do not keep a .orig copy of the file
echo.

if "%~1"=="" goto :usage

rem Keep the raw argument string: shift is destructive and options must be
rem resolved in full BEFORE any target is acted on, or "/check" typed after a
rem path would be ignored and the file would be patched anyway.
set "ARGV=%*"

rem ---- pass 1: options only ----
for %%A in (%ARGV%) do call :setopt "%%~A"
if defined WANTHELP goto :usage
if defined BADOPT goto :badopt

rem ---- pass 2: targets only ----
for %%A in (%ARGV%) do call :dispatch "%%~A"
goto :parsed

:setopt
set "A=%~1"
set "FIRST=%~1"
if /I "!A!"=="/check"    ( set "MODE=check"  & exit /b 0 )
if /I "!A!"=="/dry-run"  ( set "MODE=check"  & exit /b 0 )
if /I "!A!"=="-check"    ( set "MODE=check"  & exit /b 0 )
if /I "!A!"=="--check"   ( set "MODE=check"  & exit /b 0 )
if /I "!A!"=="--dry-run" ( set "MODE=check"  & exit /b 0 )
if /I "!A!"=="/nobackup" ( set "BACKUP=0"    & exit /b 0 )
if /I "!A!"=="-nobackup" ( set "BACKUP=0"    & exit /b 0 )
if /I "!A!"=="--nobackup" ( set "BACKUP=0"   & exit /b 0 )
if /I "!A!"=="/?"        ( set "WANTHELP=1"  & exit /b 0 )
if /I "!A!"=="/h"        ( set "WANTHELP=1"  & exit /b 0 )
if /I "!A!"=="-h"        ( set "WANTHELP=1"  & exit /b 0 )
if /I "!A!"=="--help"    ( set "WANTHELP=1"  & exit /b 0 )
set "C1=!FIRST:~0,1!"
if "!C1!"=="/" set "BADOPT=!A!"
if "!C1!"=="-" set "BADOPT=!A!"
exit /b 0

:dispatch
set "A=%~1"
set "FIRST=%~1"
set "C1=!FIRST:~0,1!"
if "!C1!"=="/" exit /b 0
if "!C1!"=="-" exit /b 0
set "TGT=!A!"
if exist "!TGT!" goto :hastarget
set "FAILED=1"
echo.
echo  [FAIL] path not found: !TGT!
exit /b 0
:hastarget
set /a N+=1
echo.
echo  --- target !N! ---
set "SPLAT_TARGET=!TGT!"
set "SPLAT_MODE=!MODE!"
set "SPLAT_BACKUP=!BACKUP!"
call :payload
if errorlevel 1 set "FAILED=1"
exit /b 0

:badopt
echo.
echo  [FAIL] unknown option: !BADOPT!
echo         valid options:  /check   /nobackup   /?
echo  Nothing was changed.
echo.
endlocal & exit /b 2

:parsed
echo.
if defined FAILED (echo  *** one or more targets failed ***) else (echo  *** done ***)
if "!MODE!"=="check" echo  [check mode] nothing was written.
set "RC=0"
if defined FAILED set "RC=1"
echo.
endlocal & exit /b %RC%

:usage
echo   Usage:  drag a ComfyUI install folder onto this .bat
echo           e.g.  ...\ComfyUI-Installs\111
echo           or    ...\ComfyUI-Installs\111\ComfyUI
echo           or    the nodes_gaussian_splat.py file itself
echo.
echo   Options:
echo     /check      report what would change, write nothing
echo     /nobackup   do not keep a .orig copy of the file
echo.
if "%~1"=="" pause
endlocal & exit /b 2

:payload
set "SPLAT_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SPLAT_SELF);$a='#:SPLATPATCH:PS1';$i=$s.IndexOf($a+':BEGIN');$j=$s.IndexOf($a+':END');if($i -lt 0 -or $j -lt 0){Write-Host '[FAIL] embedded payload markers not found in this .bat';exit 9};$rc=& ([scriptblock]::Create($s.Substring($i,$j-$i)));if($rc -is [array]){$rc=$rc[-1]};if($null -eq $rc){$rc=1};$rc=[int]$rc;exit $rc"
set "PRC=!errorlevel!"
exit /b !PRC!

rem ============================================================
rem  Nothing below this line is read by cmd -- it is the embedded
rem  PowerShell payload, extracted from this same file at runtime.
rem  That is what keeps this a single file with no sidecars.
rem ============================================================
#:SPLATPATCH:PS1:BEGIN
# ComfyUI gaussian-splat AMD/ROCm patcher -- PowerShell payload.
# Reads SPLAT_TARGET / SPLAT_MODE / SPLAT_BACKUP / SPLAT_SELF from the
# environment, prints only with Write-Host, and returns an exit code.
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$script:bakPath        = $null

# ---- the fix, verbatim from D:\comfyui-splat-amd-fix\nodes_gaussian_splat.AMD-AUTOSWITCH.py ----
$BLOCK = @'
# ROCm's batched 3x3 getrf kernel rejects launches above 65536 matrices with
# hipErrorInvalidConfiguration. HIP reports kernel errors asynchronously, so the failure surfaces at
# a later op as a misleading "CUDA error: invalid configuration argument" and poisons the CUDA
# context, failing every subsequent prompt until restart. CUDA has no such limit, so only chunk there.
_INV_CHUNK = 32768                       # matrices per inverse launch
_INV_LIMIT = 65536                       # largest batch accepted by the ROCm kernel
_IS_ROCM = getattr(torch.version, "hip", None) is not None


def _batched_inv3(m):
    # Batched 3x3 inverse. On ROCm, split oversized batches into launches the kernel accepts.
    if not _IS_ROCM or m.shape[0] <= _INV_LIMIT:
        return torch.linalg.inv(m)
    out = torch.empty_like(m)
    for lo in range(0, m.shape[0], _INV_CHUNK):
        hi = min(lo + _INV_CHUNK, m.shape[0])
        out[lo:hi] = torch.linalg.inv(m[lo:hi])
    return out
'@

$RX_DEF    = '^def _render_gaussian\('
$RX_CALL   = '^(?<ind>[ \t]*)si[ \t]*=[ \t]*torch\.linalg\.inv\([ \t]*cam_cov[ \t]*\)[ \t]*(?<tail>#.*)?$'
$RX_HASDEF = '^def _batched_inv3\('
# Runs from a temp .py file, never as a "python -c" one-liner: PowerShell 5.1
# does not escape embedded double quotes when handing an argument to a native
# exe, so a -c payload with quotes in it arrives mangled and always fails.
$PY_CHECK = @'
import py_compile, sys
try:
    py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)
except Exception as e:
    sys.stderr.write("SYNTAX: %s\n" % e)
    sys.exit(1)
sys.exit(0)
'@

function Say([string]$msg, [string]$color) {
    if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg }
}

function Resolve-SplatFile([string]$drop) {
    $d = $drop
    if (Test-Path -LiteralPath $d -PathType Leaf) {
        if ([IO.Path]::GetFileName($d) -ieq 'nodes_gaussian_splat.py') { return (Get-Item -LiteralPath $d).FullName }
        $d = Split-Path -Parent $d
    }
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return $null }
    $cands = @(
        (Join-Path $d 'comfy_extras\nodes_gaussian_splat.py'),
        (Join-Path $d 'ComfyUI\comfy_extras\nodes_gaussian_splat.py'),
        (Join-Path $d 'ComfyUI\ComfyUI\comfy_extras\nodes_gaussian_splat.py'),
        (Join-Path $d 'nodes_gaussian_splat.py')
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c -PathType Leaf) { return (Get-Item -LiteralPath $c).FullName } }
    foreach ($a in @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue)) {
        $p = Join-Path $a.FullName 'comfy_extras\nodes_gaussian_splat.py'
        if (Test-Path -LiteralPath $p -PathType Leaf) { return (Get-Item -LiteralPath $p).FullName }
        foreach ($b in @(Get-ChildItem -LiteralPath $a.FullName -Directory -ErrorAction SilentlyContinue)) {
            $q = Join-Path $b.FullName 'comfy_extras\nodes_gaussian_splat.py'
            if (Test-Path -LiteralPath $q -PathType Leaf) { return (Get-Item -LiteralPath $q).FullName }
        }
    }
    return $null
}

try {
    $drop = $env:SPLAT_TARGET
    $mode = $env:SPLAT_MODE
    if (-not $mode) { $mode = 'patch' }
    $doBackup = ($env:SPLAT_BACKUP -ne '0')

    $file = Resolve-SplatFile $drop
    if (-not $file) {
        Say ('  [FAIL] no comfy_extras\nodes_gaussian_splat.py found under: ' + $drop) 'Red'
        Say  '         drop the install folder, the workspace folder, or the .py file.' 'DarkGray'
        return 1
    }
    Say ('  file: ' + $file) 'DarkGray'

    $bytes  = [System.IO.File]::ReadAllBytes($file)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text   = [System.IO.File]::ReadAllText($file)
    if ($text.IndexOf([char]0xFFFD) -ge 0) {
        Say '  [FAIL] file does not decode as UTF-8 -- refusing to touch it.' 'Red'
        return 1
    }
    $nl    = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.IO.File]::ReadAllLines($file)
    $tot   = $lines.Length

    # ---- locate anchors. Never line numbers: an upstream update may shift everything. ----
    $defIdx = -1
    $hasDef = $false
    for ($i = 0; $i -lt $tot; $i++) {
        if ($lines[$i] -match $RX_HASDEF) { $hasDef = $true }
        if ($defIdx -lt 0 -and $lines[$i] -match $RX_DEF) { $defIdx = $i }
    }
    $callIdx = -1
    if ($defIdx -ge 0) {
        for ($i = $defIdx; $i -lt $tot; $i++) { if ($lines[$i] -match $RX_CALL) { $callIdx = $i; break } }
    }

    if ($hasDef -and $callIdx -lt 0) {
        Say '  [ ok ] already patched -- nothing to do.' 'Green'
        return 0
    }
    if ($defIdx -lt 0) {
        Say '  [FAIL] anchor not found:  def _render_gaussian(' 'Red'
        Say '         This file does not look like nodes_gaussian_splat.py, or the' 'DarkGray'
        Say '         function was renamed upstream. Nothing was changed.' 'DarkGray'
        return 1
    }
    if ($callIdx -lt 0) {
        Say '  [FAIL] anchor not found:  si = torch.linalg.inv(cam_cov)' 'Red'
        Say '         The call site was renamed or rewritten upstream, and the AMD' 'DarkGray'
        Say '         helper is not present. Nothing was changed -- the patch has to' 'DarkGray'
        Say '         be re-derived by hand against the new file.' 'DarkGray'
        return 1
    }
    for ($i = $defIdx + 1; $i -lt $callIdx; $i++) {
        if ($lines[$i] -match '^(def |class )') {
            Say '  [FAIL] the inv(cam_cov) call is no longer inside _render_gaussian.' 'Red'
            Say '         Refusing to guess. Nothing was changed.' 'DarkGray'
            return 1
        }
    }

    $insert = @()
    if (-not $hasDef) { $insert = @($BLOCK -split "`r?`n"); $insert += @('', '') }

    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $tot; $i++) {
        if ($insert.Count -gt 0 -and $i -eq $defIdx) { foreach ($b in $insert) { $out.Add($b) } }
        if ($i -eq $callIdx) {
            $m = [regex]::Match($lines[$i], $RX_CALL)
            $ln = $m.Groups['ind'].Value + 'si = _batched_inv3(cam_cov)'
            if ($m.Groups['tail'].Success) { $ln = $ln + '  ' + $m.Groups['tail'].Value }
            $out.Add($ln)
        } else {
            $out.Add($lines[$i])
        }
    }

    if ($mode -eq 'check') {
        if ($hasDef) {
            Say '  [check] helper already present; only the call site would change.' 'Yellow'
        } else {
            Say '  [check] would insert the _batched_inv3 helper before _render_gaussian,' 'Yellow'
            Say '          and redirect the call site to it. Nothing written.' 'Yellow'
        }
        return 0
    }

    $newText = [string]::Join($nl, $out.ToArray())
    if ($text.EndsWith("`n")) { $newText = $newText + $nl }

    $enc   = New-Object System.Text.UTF8Encoding($hasBom)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $ws    = Split-Path -Parent (Split-Path -Parent $file)
    $tag   = (Split-Path -Leaf (Split-Path -Parent $ws)) + '-' + (Split-Path -Leaf $ws)
    $tag   = ($tag -replace '[^\w\-\.]', '_')

    if ($doBackup) {
        $bakDir = Join-Path $env:USERPROFILE 'comfy-splat-patch-backups'
        if (-not (Test-Path -LiteralPath $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
        $script:bakPath = Join-Path $bakDir ($tag + '-nodes_gaussian_splat.py.' + $stamp + '.orig')
        [System.IO.File]::Copy($file, $script:bakPath, $true)
        Say ('  backup: ' + $script:bakPath) 'DarkGray'
    }

    $tmp = Join-Path $env:TEMP ('splatpatch-' + [guid]::NewGuid().ToString('N') + '.py')
    [System.IO.File]::WriteAllText($tmp, $newText, $enc)
    [System.IO.File]::Copy($tmp, $file, $true)
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

    $chk = [System.IO.File]::ReadAllText($file)
    if (($chk -notmatch '(?m)^def _batched_inv3\(') -or ($chk -match '(?m)^[ \t]*si[ \t]*=[ \t]*torch\.linalg\.inv\(')) {
        [System.IO.File]::WriteAllText($file, $text, $enc)
        Say '  [FAIL] post-write verification failed -- original restored.' 'Red'
        return 1
    }

    # Syntax check against the pre-patch file as a baseline, so a python that is
    # simply too old for this source cannot produce a false accusation.
    # Prefer the interpreter that will actually run this file -- the install's
    # own venv -- and never accept Get-Command's answer when it is the Microsoft
    # Store stub, which would pop the Store instead of compiling anything.
    $pyExe = $null
    $up = Split-Path -Parent $ws
    foreach ($c in @(
        (Join-Path $ws '.venv\Scripts\python.exe'),
        (Join-Path $up '.venv\Scripts\python.exe')
    )) { if (-not $pyExe -and (Test-Path -LiteralPath $c -PathType Leaf)) { $pyExe = $c } }
    if (-not $pyExe) {
        $pc = Get-Command python -ErrorAction SilentlyContinue
        if ($pc -and $pc.Source -and ($pc.Source -notlike '*\WindowsApps\*')) { $pyExe = $pc.Source }
    }
    if ($pyExe) {
        $g    = [guid]::NewGuid().ToString('N')
        $chk  = Join-Path $env:TEMP ('splatpatch-check-' + $g + '.py')
        $baseSrc = Join-Path $env:TEMP ('splatpatch-base-' + $g + '.py')
        $basePyc = Join-Path $env:TEMP ('splatpatch-base-' + $g + '.pyc')
        $newPyc  = Join-Path $env:TEMP ('splatpatch-new-'  + $g + '.pyc')
        [System.IO.File]::WriteAllText($chk, $PY_CHECK, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($baseSrc, $text, $enc)
        & $pyExe $chk $baseSrc $basePyc
        $baseRc = $LASTEXITCODE
        & $pyExe $chk $file $newPyc
        $newRc = $LASTEXITCODE
        Remove-Item -LiteralPath $chk, $baseSrc, $basePyc, $newPyc -Force -ErrorAction SilentlyContinue
        if ($baseRc -ne 0) {
            Say '  [skip] syntax check inconclusive: the pre-patch file does not compile with this python.' 'DarkGray'
        } elseif ($newRc -ne 0) {
            [System.IO.File]::WriteAllText($file, $text, $enc)
            Say '  [FAIL] syntax check failed after patching -- original restored.' 'Red'
            return 1
        } else {
            Say '  [ ok ] syntax check passed.' 'Green'
        }
    }

    if ($hasDef) {
        Say '  [ ok ] patched -- call site redirected to the existing helper.' 'Green'
    } else {
        Say '  [ ok ] patched -- helper inserted, call site redirected.' 'Green'
    }
    Say '         si = torch.linalg.inv(cam_cov)  ->  si = _batched_inv3(cam_cov)' 'DarkGray'
    Say '  Restart ComfyUI for the change to take effect.' 'Yellow'
    return 0
} catch {
    Say ('  [FAIL] ' + $_.Exception.Message) 'Red'
    if ($script:bakPath) { Say ('         original saved at: ' + $script:bakPath) 'DarkGray' }
    return 1
}
#:SPLATPATCH:PS1:END
