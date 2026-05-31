@echo off
setlocal
cd /d "%~dp0"

python -m pip install -r requirements.txt -q
python "%~dp0gpu_burst_tray.py"
