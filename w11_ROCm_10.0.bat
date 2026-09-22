@echo off
setlocal EnableDelayedExpansion
net session >nul 2>&1
if %errorlevel% == 0 (
    call :Main
) else (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
goto :eof

:Main
setlocal
pushd "%~dp0"

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

REM -------- Environment variables --------
setx HIP_DEVICE_LIB_PATH "C:\TheRock\build\lib\llvm\amdgcn\bitcode" /M
setx HIP_PATH "C:\TheRock\build" /M
setx HIP_PLATFORM "amd" /M
setx LLVM_PATH "C:\TheRock\build\lib\llvm" /M

REM Properly append to machine PATH without blowing past 1024 chars
for /f "skip=2 tokens=2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYSPATH=%%B"
echo !SYSPATH! | find /i "C:\TheRock\build\bin" >nul || setx PATH "!SYSPATH!;C:\TheRock\build\bin;C:\TheRock\build\lib\llvm\bin" /M

set
hipinfo

endlocal
goto :eof