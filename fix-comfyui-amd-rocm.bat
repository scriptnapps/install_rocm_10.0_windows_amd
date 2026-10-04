@echo off
setlocal EnableExtensions
title Fix ComfyUI / AMD ROCm access violation 0xC0000005

REM ============================================================================
REM  fix-comfyui-amd-rocm.bat
REM
REM  WHAT THIS FIXES
REM    ComfyUI dies mid-generation with:
REM        Windows fatal exception: access violation
REM        Exception Code: 0xC0000005
REM        libhipblaslt.dll  ...  hipblasLtMatmulAlgoGetHeuristic() + 0x10E
REM    Typically the moment a text encoder / model first runs a matmul, e.g.
REM        comfy\text_encoders\llama.py:539 in precompute_freqs_cis
REM    so it looks like "got prompt" then a hard crash to desktop.
REM
REM  WHY
REM    hipBLASLt's matmul kernel-heuristic lookup faults on some AMD GPUs on
REM    Windows (reported on gfx1201 / RX 9070 XT, gfx110x, R9700) under PyTorch
REM    ROCm builds such as 2.12.0+rocm7.14.0. It is not a ComfyUI bug and not a
REM    missing library. These settings route those matmuls to rocBLAS instead.
REM
REM  WHEN TO RUN
REM    Once per Windows user account. Settings are per-user, so they cover every
REM    ComfyUI install you launch afterwards - Desktop, portable, or venv, and
REM    any ComfyUI you install later. Re-run it on a new machine / new profile.
REM    No administrator rights needed; it writes HKCU only.
REM
REM  USAGE
REM    double-click            apply the fix        pauses when done
REM    fix-...bat /y           apply the fix        no pause, for scripting
REM    fix-...bat remove       undo - deletes the three variables
REM
REM  ONLY VARIABLES THIS TORCH BUILD READS ARE SET
REM    Verified present in the 2.12.0+rocm7.14.0 binaries: TORCH_BLAS_PREFER_
REM    HIPBLASLT and TORCH_BLAS_PREFER_CUBLASLT in torch_cpu.dll, and ROCBLAS_
REM    USE_HIPBLASLT in rocblas.dll. DISABLE_ADDMM_HIP_LT is deliberately NOT
REM    set: it is widely recommended online but is absent from this build, so
REM    it would do nothing.
REM
REM  TRADE-OFF
REM    hipBLASLt can be faster than rocBLAS on some shapes, so you may give up
REM    some speed. Correctness beats a crash; run with "remove" to compare.
REM
REM  MAINTAINER NOTE
REM    Do NOT put literal parentheses in any echo text inside an if-block or a
REM    for-block in this file. cmd's block parser consumes them as block
REM    delimiters, which desynchronises the block and makes branches run
REM    unconditionally. Use the  --  separator instead.
REM ============================================================================

set "NOPAUSE="
set "FAILED="
if /I "%~1"=="/y" set "NOPAUSE=1"
if /I "%~1"=="/remove" goto :remove
if /I "%~1"=="remove" goto :remove
if /I "%~1"=="--remove" goto :remove

:apply
echo ===========================================================================
echo   ComfyUI / AMD ROCm  -  access violation 0xC0000005 fix
echo ===========================================================================
echo.
echo   Routing matmuls away from hipBLASLt, which faults, to rocBLAS.
echo   Scope: current user. Covers all ComfyUI installs launched after this.
echo.

call :setvar TORCH_BLAS_PREFER_HIPBLASLT 0 "PyTorch - prefer rocBLAS over hipBLASLt"
call :setvar TORCH_BLAS_PREFER_CUBLASLT  0 "same switch, CUDA-side alias"
call :setvar ROCBLAS_USE_HIPBLASLT       0 "rocBLAS - use Tensile, never hipBLASLt"
echo.

if defined FAILED goto :apply_failed

echo   Verified - reading these back from your environment:
call :show TORCH_BLAS_PREFER_HIPBLASLT
call :show TORCH_BLAS_PREFER_CUBLASLT
call :show ROCBLAS_USE_HIPBLASLT
echo.
echo   DONE. Now FULLY quit ComfyUI and start it again.
echo   Closing the window is not enough - these are read when the process
echo   starts, so an already-running ComfyUI keeps the broken behaviour.
echo   ComfyUI Desktop: use its Quit / Exit item, then relaunch the app.
echo.
call :maybe_pause
exit /b 0

:apply_failed
echo   One or more values were NOT written - see FAIL above.
echo   The fix is incomplete and ComfyUI will still crash.
echo.
call :maybe_pause
exit /b 1

:setvar
setx %~1 %~2 >nul 2>&1
if errorlevel 1 goto :setvar_failed
echo   [ ok ] %~1 = %~2  --  %~3
exit /b 0

:setvar_failed
echo   [FAIL] %~1 could not be written  --  %~3
set "FAILED=1"
exit /b 0

:show
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v %~1 2^>nul') do echo       %~1 = %%B
exit /b 0

:maybe_pause
if not defined NOPAUSE pause
exit /b 0

:remove
echo ===========================================================================
echo   Removing the ComfyUI ROCm BLAS overrides
echo ===========================================================================
echo.
reg delete "HKCU\Environment" /F /V TORCH_BLAS_PREFER_HIPBLASLT >nul 2>&1
reg delete "HKCU\Environment" /F /V TORCH_BLAS_PREFER_CUBLASLT  >nul 2>&1
reg delete "HKCU\Environment" /F /V ROCBLAS_USE_HIPBLASLT       >nul 2>&1
echo   Removed from your user environment:
echo       TORCH_BLAS_PREFER_HIPBLASLT
echo       TORCH_BLAS_PREFER_CUBLASLT
echo       ROCBLAS_USE_HIPBLASLT
echo.
echo   Relaunch ComfyUI for this to take effect.
echo.
call :maybe_pause
exit /b 0
