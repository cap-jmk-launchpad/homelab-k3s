@echo off
setlocal
set "TARGET=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Desktop GPU Burst.lnk"
set "SCRIPT=%~dp0run.bat"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws = New-Object -ComObject WScript.Shell; ^
   $s = $ws.CreateShortcut('%TARGET%'); ^
   $s.TargetPath = '%SCRIPT%'; ^
   $s.WorkingDirectory = '%~dp0'; ^
   $s.WindowStyle = 7; ^
   $s.Description = 'Homelab desktop GPU burst toggle'; ^
   $s.Save()"

echo Created startup shortcut:
echo   %TARGET%
echo.
echo Remove that shortcut to disable auto-start.
