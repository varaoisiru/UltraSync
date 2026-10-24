@echo off
rem UltraSync Windows launcher — starts the GUI server and opens the browser.
setlocal
cd /d "%~dp0\.."

if not exist ".venv\Scripts\python.exe" (
    echo Not installed yet - running windows\install.bat first...
    call windows\install.bat
)

start "UltraSync" /min ".venv\Scripts\python.exe" -m ultrasync
timeout /t 3 /nobreak >nul
start http://127.0.0.1:8077
echo UltraSync GUI running at http://127.0.0.1:8077
echo Close the minimized UltraSync window to stop the server.
endlocal
