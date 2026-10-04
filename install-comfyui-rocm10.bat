@echo off
setlocal EnableExtensions EnableDelayedExpansion
title ComfyUI - ROCm 10 installer

REM ============================================================================
REM  install-comfyui-rocm10.bat
REM
REM  WHAT IT DOES
REM    Drag a ComfyUI install folder onto this file and it replaces that
REM    install's PyTorch/ROCm stack with ROCm 10. Any install name works --
REM    the folder under ComfyUI-Installs, the ComfyUI workspace inside it, the
REM    .venv itself, or Scripts\python.exe all resolve to the same place.
REM
REM  WHY IT USES uv AND NOT pip
REM    Windows MAX_PATH is 260 by default and these ROCm wheels ship hipBLASLt /
REM    Tensile kernel files whose names run to ~112 chars under a ~148-char
REM    prefix. pip cannot create or move them and dies with
REM        OSError: [Errno 2] No such file or directory
REM    part-way through, leaving a half-converted venv. uv handles
REM    extended-length paths correctly, so this script drives uv end to end.
REM
REM  WHAT IT DOES NOT DO
REM    It does NOT fix the 0xC0000005 hipBLASLt crash. Measured on this machine:
REM    ROCm 7.14 and ROCm 10 fail identically -- same access violation in
REM    hipblasLtMatmulAlgoGetHeuristic for fp32 GEMM shapes such as 512x512,
REM    100%% reproducible on both stacks. Keep fix-comfyui-amd-rocm.bat applied,
REM    or pass /fix to have this script apply it for you.
REM
REM  USAGE
REM    drop a folder on it           install, confirm first
REM    install-comfyui-rocm10.bat <path> [switches]
REM
REM    /y              skip the confirmation prompt
REM    /dry-run        resolve everything, print the uv command, install nothing
REM    /all            install every GPU arch instead of just this one
REM                    -- about 6 GB vs about 1.3 GB, but slower and no faster
REM    /arch:gfxNNNN   target a different GPU arch -- default gfx1201
REM    /ver:X.Y.Z      target a different ROCm version -- default 10.0.0
REM    /fix            also apply the hipBLASLt crash workaround at the end
REM    /force-111      allow the script to touch an install named 111
REM
REM    Switch values take a COLON. cmd splits its own arguments on '=', so
REM    /ver=10.0.0 is read as two arguments and would silently do nothing.
REM
REM  NOTES
REM    - No administrator rights needed. Nothing outside the target venv is
REM      written except the pip-freeze snapshot listed at the end.
REM    - Close ComfyUI first. Windows locks the DLLs of a running process and
REM      uv cannot replace them; the script checks and refuses if it can.
REM    - A pip-freeze snapshot of the old stack is written before anything
REM      changes, so an affected install can be rebuilt by hand afterwards.
REM
REM  MAINTAINER NOTE
REM    Do NOT put literal parentheses in any echo text inside an if-block or a
REM    for-block in this file. cmd's block parser consumes them as block
REM    delimiters, which desynchronises the block and makes branches run
REM    unconditionally. Use the  --  separator instead.
REM ============================================================================

REM ---- what gets installed -------------------------------------------------
set "ROCM_VER=10.0.0"
set "TORCH_VER=2.13.0"
set "TV_VER=0.28.0"
set "TA_VER=2.11.0.2"
set "ARCH=gfx1201"
set "INDEX=https://stable.repo.amd.com/rocm/whl-next/"
set "EXTRA_INDEX=https://pypi.org/simple/"
set "MIGDIR=%USERPROFILE%\comfy-rocm10-migration"
set "FIXBAT=%~dp0fix-comfyui-amd-rocm.bat"

REM ---- state ---------------------------------------------------------------
set "TARGET="
set "ASSUME_YES="
set "DRYRUN="
set "USE_ALL="
set "RUNFIX="
set "FORCE111="
set "VENV="
set "FAILED="

REM ---- argument parsing ----------------------------------------------------
:parse
if "%~1"=="" goto :parsed
set "A=%~1"
if /I "!A!"=="/y"         ( set "ASSUME_YES=1" & shift & goto :parse )
if /I "!A!"=="/dry-run"   ( set "DRYRUN=1"     & shift & goto :parse )
if /I "!A!"=="/all"       ( set "USE_ALL=1"    & shift & goto :parse )
if /I "!A!"=="/fix"       ( set "RUNFIX=1"     & shift & goto :parse )
if /I "!A!"=="/force-111" ( set "FORCE111=1"   & shift & goto :parse )
if /I "!A!"=="/help"      goto :usage
if /I "!A!"=="/?"         goto :usage
if /I "!A!"=="-h"         goto :usage
set "A2=!A!"
REM  Switch VALUES use a colon, not an equals sign. cmd splits its own
REM  arguments on '=' as well as on space, comma and semicolon, so a
REM  "/ver=10.0.0" arrives as the two arguments "/ver" and "10.0.0" and would
REM  otherwise be ignored without complaint.
if /I "!A2:~0,5!"=="/ver:"  for /f "tokens=1,2 delims=:" %%X in ("!A!") do ( set "ROCM_VER=%%Y" & shift & goto :parse )
if /I "!A2:~0,6!"=="/arch:" for /f "tokens=1,2 delims=:" %%X in ("!A!") do ( set "ARCH=%%Y"    & shift & goto :parse )
if not defined TARGET ( set "TARGET=%~1" & shift & goto :parse )
echo   [FAIL] unrecognised argument: !A!
echo          One install path plus any of /y /dry-run /all /fix /force-111
echo          /ver:X.Y.Z /arch:gfxNNNN -- switch values take a COLON.
goto :failed

:parsed
if not defined TARGET goto :usage

REM ---- banner --------------------------------------------------------------
echo ===========================================================================
echo   ComfyUI  -  ROCm %ROCM_VER% installer
echo ===========================================================================
echo.

REM ---- resolve the venv ----------------------------------------------------
:resolve
set "DROP=%TARGET%"
if "%DROP:~-1%"=="\" set "DROP=%DROP:~0,-1%"
if not exist "%DROP%" goto :err_notfound

REM Try, cheapest first. Any of these may miss harmlessly -- a miss just costs
REM one exists check. The last two catch paths dropped below the venv root.
if not defined VENV call :try "%DROP%\ComfyUI\.venv"
if not defined VENV call :try "%DROP%\.venv"
if not defined VENV call :try "%DROP%\ComfyUI\ComfyUI\.venv"
if not defined VENV call :try "%DROP%"
REM dropped ...\.venv\Scripts\python.exe or its parent
if not defined VENV if exist "%DROP%\..\..\Scripts\python.exe" for %%P in ("%DROP%\..\..") do call :try "%%~fP"
if not defined VENV if exist "%DROP%\..\Scripts\python.exe"     for %%P in ("%DROP%\..")     do call :try "%%~fP"
REM bounded search, <drop>\*\*\.venv
if not defined VENV for /d %%A in ("%DROP%\*") do if not defined VENV for /d %%B in ("%%~fA\*") do call :try "%%~fB\.venv"
if not defined VENV goto :err_novenv

set "PY=%VENV%\Scripts\python.exe"
set "SP=%VENV%\Lib\site-packages"
for %%I in ("%VENV%\..") do set "WS=%%~fI"
for %%I in ("%WS%\..") do set "INSTALLROOT=%%~fI"
for %%I in ("%INSTALLROOT%") do set "INAME=%%~nxI"

echo   install      : %INSTALLROOT%
echo   workspace    : %WS%
echo   venv         : %VENV%
echo   python       : %PY%
echo.

REM ---- guard: 111 is off limits -------------------------------------------
echo %INSTALLROOT% | findstr /i /c:"\111" >nul
if not errorlevel 1 if not defined FORCE111 goto :err_111

REM ---- guard: does the venv look sane -------------------------------------
if not exist "%PY%" goto :err_nopy
echo   [ ok ] venv has Scripts\python.exe

REM ---- guard: is it in use ------------------------------------------------
REM  The path is handed over in an env var so the PowerShell command needs no
REM  inner quotes. The pipes below are intentionally NOT caret-escaped: they sit
REM  inside the -Command double quotes, so cmd does not read them as pipelines,
REM  and a caret would be passed through to PowerShell literally and break it.
set "VENVPATH=%VENV%\*"
set "INUSE="
for /f "delims=" %%C in ('powershell -NoProfile -Command "(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like $env:VENVPATH } | Measure-Object).Count" 2^>nul') do set "INUSE=%%C"
if "!INUSE!"=="" set "INUSE=0"
echo !INUSE!| findstr /r /c:"^[0-9][0-9]*$" >nul || set "INUSE=0"
if !INUSE! GTR 0 goto :err_inuse
echo   [ ok ] no running process is using this venv

REM ---- uv ----------------------------------------------------------------
call :find_uv
if not defined UV goto :err_nouv
echo   [ ok ] uv at %UV%

REM ---- what is installed now ---------------------------------------------
echo.
echo   -- current stack in this venv --
"%UV%" pip list --python "%PY%" | findstr /i /b /c:"torch " /c:"torchvision " /c:"torchaudio " /c:"rocm " /c:"rocm-sdk-core " /c:"rocm-sdk-libraries " /c:"rocm-bootstrap "

REM ---- snapshot for rollback ---------------------------------------------
if not exist "%MIGDIR%" mkdir "%MIGDIR%" >nul 2>&1
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss" 2^>nul') do set "TS=%%T"
if not defined TS set "TS=manual"
set "SNAP=%MIGDIR%\%INAME%-pipfreeze-before-rocm%ROCM_VER%-%TS%.txt"
"%UV%" pip freeze --python "%PY%" > "%SNAP%" 2>nul
if exist "%SNAP%" goto :snap_ok
echo.
echo   [warn] could not write a rollback snapshot
goto :snap_done
:snap_ok
echo.
echo   rollback snapshot written:
echo      %SNAP%
:snap_done

REM ---- resolve the package set -------------------------------------------
if defined USE_ALL goto :pkgs_all
set "PKGS=torch==%TORCH_VER%+rocm%ROCM_VER% torchvision==%TV_VER%+rocm%ROCM_VER% torchaudio==%TA_VER%+rocm%ROCM_VER% rocm==%ROCM_VER% rocm-sdk-core==%ROCM_VER% rocm-sdk-libraries==%ROCM_VER% rocm-sdk-device-%ARCH%==%ROCM_VER% amd-torch-device-%ARCH%==%TORCH_VER%+rocm%ROCM_VER% amd-torchvision-device-%ARCH%==%TV_VER%+rocm%ROCM_VER%"
goto :pkgs_done
:pkgs_all
set "PKGS=torch[device-all]==%TORCH_VER%+rocm%ROCM_VER% torchvision[device-all]==%TV_VER%+rocm%ROCM_VER% torchaudio==%TA_VER%+rocm%ROCM_VER% rocm[libraries,device-all]==%ROCM_VER%"
:pkgs_done

REM ---- confirm -----------------------------------------------------------
echo.
if defined DRYRUN goto :do_dryrun
if defined ASSUME_YES goto :preflight
echo   This will REPLACE the PyTorch/ROCm stack in the venv printed above with
echo   ROCm %ROCM_VER% -- torch %TORCH_VER%, torchvision %TV_VER%, torchaudio %TA_VER%.
echo   The old stack is removed first. Close ComfyUI before continuing.
echo.
choice /c YN /n /m "  Proceed? [Y/N] "
if errorlevel 2 goto :cancelled
goto :preflight

:cancelled
echo.
echo   Cancelled. Nothing was changed.
echo.
goto :done

REM ---- dry run -----------------------------------------------------------
:do_dryrun
echo   -- dry run -- nothing will be installed --
echo.
echo   step 1, remove the old stack:
echo      "%UV%" pip uninstall --python "%PY%" ^<rocm and torch family^>
echo.
echo   step 2, install:
echo      "%UV%" pip install --python "%PY%" --index-url %INDEX% --extra-index-url %EXTRA_INDEX% --index-strategy unsafe-best-match
echo        %PKGS%
echo.
echo   Dry run complete. Re-run without /dry-run to apply.
echo.
goto :done

REM ---- preflight ---------------------------------------------------------
REM  Resolve the pins BEFORE anything is removed. A future ROCm version that
REM  renamed a package, or an /arch that has no wheels, fails here with the
REM  working stack still intact instead of halfway through a gutted venv.
:preflight
echo.
echo   -- resolving ROCm %ROCM_VER% for %ARCH% --
"%UV%" pip install --dry-run --python "%PY%" --index-url %INDEX% --extra-index-url %EXTRA_INDEX% --index-strategy unsafe-best-match %PKGS% > "%TEMP%\rocm10-preflight.log" 2>&1
if errorlevel 1 goto :err_preflight
echo   [ ok ] every pin resolves

REM ---- uninstall the old family -----------------------------------------
echo.
echo   -- removing the existing ROCm / PyTorch stack --
set "FAMILY="
for /d %%D in ("%SP%\rocm_sdk_device_*.dist-info" "%SP%\amd_torch_device_*.dist-info" "%SP%\amd_torchvision_device_*.dist-info") do for /f "tokens=1 delims=-" %%N in ("%%~nD") do set "FAMILY=!FAMILY! %%N"
set "FAMILY=!FAMILY! torch torchvision torchaudio rocm-bootstrap rocm-sdk-core rocm-sdk-libraries rocm"
if defined FAMILY "%UV%" pip uninstall --python "%PY%" !FAMILY! > "%TEMP%\rocm10-uninstall.log" 2>&1
if errorlevel 1 goto :err_uninstall
echo   [ ok ] old stack removed

echo.
echo   -- installing ROCm %ROCM_VER% --
echo.
"%UV%" pip install --python "%PY%" --index-url %INDEX% --extra-index-url %EXTRA_INDEX% --index-strategy unsafe-best-match %PKGS%
if errorlevel 1 goto :err_install

REM ---- verify ------------------------------------------------------------
:verify
echo.
echo   -- verifying --
echo.
"%PY%" -c "import torch,sys;print('  torch      :',torch.__version__);print('  hip        :',torch.version.hip);print('  available  :',torch.cuda.is_available());print('  device     :',torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'n/a')"
if errorlevel 1 goto :err_verify
echo   [ ok ] torch imports and sees the GPU
echo.
echo   NOTE: this check deliberately does NOT run a matmul. An fp32 GEMM such
echo   as 512x512 trips the hipBLASLt crash on ROCm 7.14 AND on ROCm 10, so a
echo   passing import does not mean generation is safe.

REM ---- optional crash workaround ----------------------------------------
if not defined RUNFIX goto :no_fix
if not exist "%FIXBAT%" goto :fix_missing
echo.
echo   -- applying the hipBLASLt crash workaround --
call "%FIXBAT%" /y
goto :summary

:fix_missing
echo.
echo   [warn] /fix requested but not found: %FIXBAT%
goto :summary

:no_fix
echo.
echo   REMINDER: ROCm %ROCM_VER% does not fix the 0xC0000005 hipBLASLt crash.
echo   Run this once, then fully restart ComfyUI:
echo       %FIXBAT%
echo   Or re-run this installer with /fix to have it applied automatically.

:summary
echo.
echo ===========================================================================
echo   DONE -- ROCm %ROCM_VER% installed into:
echo     %VENV%
echo.
echo   Rollback snapshot:
echo     %SNAP%
echo ===========================================================================
echo.
goto :done

REM ---- helpers ------------------------------------------------------------
:try
if not defined VENV if exist "%~1\Scripts\python.exe" set "VENV=%~f1"
exit /b 0

:find_uv
set "UV="
for /f "delims=" %%U in ('where uv 2^>nul') do if not defined UV set "UV=%%U"
if defined UV exit /b 0
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\astral-sh.uv_*") do if not defined UV if exist "%%~fD\uv.exe" set "UV=%%~fD\uv.exe"
if defined UV exit /b 0
if exist "%APPDATA%\uv\tools\comfy-cli\Scripts\uv.exe" set "UV=%APPDATA%\uv\tools\comfy-cli\Scripts\uv.exe"
exit /b 0

REM ---- errors -------------------------------------------------------------
:err_notfound
echo   [FAIL] no such folder: %TARGET%
goto :failed

:err_111
echo   [FAIL] refusing to touch an install named 111.
echo          That install is the known-good reference. Re-run with /force-111
echo          if you really mean it.
goto :failed

:err_novenv
echo   [FAIL] could not find a .venv under:
echo            %DROP%
echo          Drop the ComfyUI-Installs folder for that install, its ComfyUI
echo          workspace, or the .venv itself.
goto :failed

:err_nopy
echo   [FAIL] found %VENV% but it has no Scripts\python.exe
goto :failed

:err_inuse
echo   [FAIL] !INUSE! running process(es) are using this venv.
echo          Quit ComfyUI AND Comfy Desktop completely. Closing the window is
echo          not enough: Desktop keeps its instance running in the background
echo          and will simply restart it. Then run this again.
goto :failed

:err_nouv
echo   [FAIL] uv was not found on PATH.
echo          Install it with:  winget install astral-sh.uv
goto :failed

:err_preflight
echo   [FAIL] those pins do not resolve. Nothing was changed -- the existing
echo          stack is still in place. Full uv output:
echo            %TEMP%\rocm10-preflight.log
echo          Check /ver: and /arch: against what that index actually carries.
goto :failed

:err_uninstall
echo   [FAIL] uv could not remove the old stack. Log:
echo            %TEMP%\rocm10-uninstall.log
echo          Nothing was installed. Re-run once any locking process is gone.
goto :failed

:err_install
echo   [FAIL] uv install failed -- see the output above.
echo          The venv may now be missing torch. Re-run this script; it is
echo          safe to run repeatedly.
goto :failed

:err_verify
echo   [FAIL] torch did not import cleanly after the install.
goto :failed

:failed
set "FAILED=1"
echo.
if defined ASSUME_YES goto :done
pause
goto :done

:usage
echo ===========================================================================
echo   ComfyUI  -  ROCm %ROCM_VER% installer
echo ===========================================================================
echo.
echo   Drag a ComfyUI install folder onto this file, or run:
echo       install-comfyui-rocm10.bat "C:\...\ComfyUI-Installs\YourInstall"
echo.
echo   Switches:
echo       /y              skip the confirmation prompt
echo       /dry-run        show what would happen, change nothing
echo       /all            install every GPU arch -- about 6 GB instead of 1.3 GB
echo       /arch:gfxNNNN   target another GPU arch -- default %ARCH%
echo       /ver:X.Y.Z      target another ROCm version -- default %ROCM_VER%
echo       /fix            also apply the hipBLASLt crash workaround
echo       /force-111      allow touching an install named 111
echo.
echo   Switch values take a colon, not an equals sign.
echo.
echo   Close ComfyUI before running this.
echo.
goto :done

:done
if not defined ASSUME_YES if not defined DRYRUN pause
REM RC is expanded while the setlocal scope is still live, then handed out.
set "RC=0"
if defined FAILED set "RC=1"
endlocal & exit /b %RC%
