@echo off
rem UltraSync Windows installer — bootstraps a venv and installs deps.
setlocal
cd /d "%~dp0\.."

where py >nul 2>nul && (set PYCMD=py -3) || (set PYCMD=python)
%PYCMD% --version >nul 2>nul || (
    echo Python 3 was not found. Install it from https://www.python.org/downloads/
    echo and re-run this script.
    pause
    exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
    echo Creating virtual environment...
    %PYCMD% -m venv .venv
    if errorlevel 1 ( echo venv creation failed & pause & exit /b 1 )
)

echo Installing dependencies...
".venv\Scripts\python.exe" -m pip install -q --upgrade pip
".venv\Scripts\python.exe" -m pip install -q -r requirements.txt
if errorlevel 1 ( echo dependency install failed & pause & exit /b 1 )

if not exist "%USERPROFILE%\.config\ultrasync" mkdir "%USERPROFILE%\.config\ultrasync"
if not exist "%USERPROFILE%\.cache\ultrasync" mkdir "%USERPROFILE%\.cache\ultrasync"

echo.
echo UltraSync installed. Launch it with windows\run.bat
echo Config: %USERPROFILE%\.config\ultrasync\config.json
pause
endlocal
