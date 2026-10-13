@echo off
title Two Player Creative World
cd /d "%~dp0"
set "GODOT_EXE=C:\tools\Godot-App\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
	for /f "delims=" %%G in ('where godot 2^>nul') do if not exist "%GODOT_EXE%" set "GODOT_EXE=%%G"
)
if not exist "%GODOT_EXE%" (
    echo Godot 4.6 was not found. Open project.godot with Godot or add Godot to PATH.
    pause
    exit /b 1
)
start "Two Player Creative World" "%GODOT_EXE%" --path .
