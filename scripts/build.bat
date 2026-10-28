@echo off
REM ===== TD Hero Defense · Godot 构建脚本 =====
REM 用法: scripts\build.bat [dev|export]

setlocal
set GODOT_DIR=%LOCALAPPDATA%\Programs\Godot
set GODOT_EXE=%GODOT_DIR%\Godot_v4.7.2-stable_win64.exe
set PROJECT_DIR=%~dp0..

if not exist "%GODOT_EXE%" (
  echo [ERROR] Godot not found at: %GODOT_EXE%
  echo Download: https://github.com/godotengine/godot/releases/tag/4.7.2-stable
  exit /b 1
)

cd /d "%PROJECT_DIR%"

if "%1"=="export" (
  echo === Exporting release build ===
  "%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --export-release "Windows Desktop" "build\windows/TDHeroDefense.exe"
  if errorlevel 1 (
    echo [FAIL] Export failed
    exit /b 1
  )
  echo === Export OK: build\windows\TDHeroDefense.exe ===
) else (
  echo === Running editor / project ===
  "%GODOT_EXE%" --path "%PROJECT_DIR%"
)

endlocal
