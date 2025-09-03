@echo off
set src="%cd%\HLAE_CamIO_Import.lua"

set dest="C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Utility\HLAE\"

xcopy /I /Y /Q %src% %dest%

echo.
echo Done!
pause
