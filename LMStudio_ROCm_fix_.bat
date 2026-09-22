@echo off
setlocal EnableDelayedExpansion

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
setlocal
pushd "%~dp0"


if exist "C:\TheRock\build\bin" (

    del /F /Q "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\amdhip64_7.dll"

    xcopy /E /I /Y "C:\TheRock\build\bin\rocblas" "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\rocblas" >nul

    copy /Y "C:\TheRock\build\bin\amdhip64_7.dll" "C:\Users\nro\.lmstudio\extensions\backends\llama.cpp-win-x86_64-amd-rocm-avx2-2.42.0\amdhip64_7.dll"

    copy /Y "C:\TheRock\build\bin\amdhip64_7.dll"   "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\amd_comgr_3.dll"     "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\amd_comgr.dll"     "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\libhipblas.dll"      "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\libhipblaslt.dll"    "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\rocblas.dll" "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    echo done fixed lmstudio ROCm10.0
    pause
    goto :eof
)


rem tarball from here https://rocm.docs.amd.com/en/latest/install/rocm.html?
rem therock-dist-windows-gfx110X-all-10.0.0.tar.gz

set "TARBALL=therock-dist-windows-gfx120X-all-10.0.0.tar.gz"
set "MARKER=alreadyinstalled.txt"
set "URL=https://stable.repo.amd.com/rocm/core/tarball/%TARBALL%"

mkdir C:\TheRock\build 2>nul
cd /d C:\TheRock

REM -------- Decide whether to install --------
set "DO_INSTALL=1"
if exist "%MARKER%" (
    echo Found existing installation ^(%MARKER%^) - previous install detected.
    set /p "REPLY=To delete and reinstall, type yes: "
    if /i not "!REPLY!"=="yes" (
        echo Skipping installation.
        set "DO_INSTALL=0"
    ) else (
        echo Reinstalling...
        del /q "%MARKER%" 2>nul
        rmdir /s /q "C:\TheRock\build" 2>nul
        mkdir "C:\TheRock\build"
    )
)

if "!DO_INSTALL!"=="1" (
    REM -------- Ensure tarball is present --------
    if not exist "%TARBALL%" (
        echo Tarball not found. Downloading...
        curl -o "%TARBALL%" "%URL%"
    ) else (
        echo Found existing %TARBALL% - skipping download.
    )

    REM -------- Verify & extract --------
    if not exist "%TARBALL%" (
        echo ERROR: %TARBALL% is missing. Download may have failed.
        pause
        exit /b 1
    ) else (
        echo Extracting...
        tar -xzf "%TARBALL%" -C build --strip-components=1
        del /q "%TARBALL%"
    )

    REM -------- Mark installation complete --------
    type nul > "%MARKER%"
)

cd /d C:\TheRock\build


REM -------- SKIP Environment variables --------
REM setx HIP_DEVICE_LIB_PATH "C:\TheRock\build\lib\llvm\amdgcn\bitcode" /M
REM setx HIP_PATH "C:\TheRock\build" /M
REM setx HIP_PLATFORM "amd" /M
REM setx LLVM_PATH "C:\TheRock\build\lib\llvm" /M
REM Properly append to machine PATH without blowing past 1024 chars
REM for /f "skip=2 tokens=2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYSPATH=%%B"
REM echo !SYSPATH! | find /i "C:\TheRock\build\bin" >nul || setx PATH "!SYSPATH!;C:\TheRock\build\bin;C:\TheRock\build\lib\llvm\bin" /M


cd /d C:\TheRock\build

if exist "C:\TheRock\build\bin" (

    del /F /Q "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\amdhip64_7.dll"

    xcopy /E /I /Y "C:\TheRock\build\bin\rocblas" "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\rocblas" >nul

    copy /Y "C:\TheRock\build\bin\amdhip64_7.dll" "C:\Users\nro\.lmstudio\extensions\backends\llama.cpp-win-x86_64-amd-rocm-avx2-2.42.0\amdhip64_7.dll"

    copy /Y "C:\TheRock\build\bin\amdhip64_7.dll"   "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\amd_comgr_3.dll"     "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\amd_comgr.dll"     "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\libhipblas.dll"      "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\libhipblaslt.dll"    "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    copy /Y "C:\TheRock\build\bin\rocblas.dll" "C:\Users\nro\.lmstudio\extensions\backends\vendor\win-llama-rocm-vendor-v6\bin\"

    echo done fixed lmstudio ROCm10.0
    pause
    goto :eof
)

pause

endlocal
goto :eof