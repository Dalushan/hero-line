@echo off
REM ===== TD Hero Defense · 测试与模拟 =====
REM 用法: scripts\test.bat

setlocal
set GODOT_DIR=%LOCALAPPDATA%\Programs\Godot
set GODOT_EXE=%GODOT_DIR%\Godot_v4.7.2-stable_win64.exe
set PROJECT_DIR=%~dp0..

if not exist "%GODOT_EXE%" (
  echo [ERROR] Godot not found at: %GODOT_EXE%
  exit /b 1
)

cd /d "%PROJECT_DIR%"

echo === Importing project resources (first run may take a while) ===
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --import 2>&1 | findstr /C:"ERROR" /C:"SCRIPT ERROR"
echo === Running core test suite ===
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/test_runner.gd
exit /b %errorlevel%
