@echo off
REM ===== TD Hero Defense · Godot 构建脚本 =====
REM 用法: scripts\build.bat [dev|export|test|sim]
REM
REM 首次使用需安装导出模板:
REM   1) 下载 Godot_v4.7.2-stable_export_templates.tpz
REM   2) 解压后把 templates\* 复制到 %APPDATA%\Godot\export_templates\4.7.2.stable\
REM      (注意: 不是 Godot 安装目录! Godot 只认这个路径)

setlocal
set GODOT_DIR=%LOCALAPPDATA%\Programs\Godot
set GODOT_EXE=%GODOT_DIR%\Godot_v4.7.2-stable_win64.exe
set GODOT_CONSOLE=%GODOT_DIR%\Godot_v4.7.2-stable_win64_console.exe
set PROJECT_DIR=%~dp0..
set TEMPLATE_DIR=%APPDATA%\Godot\export_templates\4.7.2.stable

if not exist "%GODOT_EXE%" (
  echo [ERROR] Godot not found at: %GODOT_EXE%
  echo Download: https://github.com/godotengine/godot/releases/tag/4.7.2-stable
  exit /b 1
)

cd /d "%PROJECT_DIR%"

if "%1"=="export" (
  if not exist "%TEMPLATE_DIR%\windows_release_x86_64.exe" (
    echo [ERROR] Export templates not found at: %TEMPLATE_DIR%
    echo Download Godot_v4.7.2-stable_export_templates.tpz and extract templates\* there.
    exit /b 1
  )
  REM Godot 不会自动创建导出目录, 缺目录会报 "给定的导出路径不存在"
  if not exist "build\windows" mkdir "build\windows"
  echo === Exporting release build ===
  "%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --export-release "Windows Desktop" "build\windows\TDHeroDefense.exe"
  if errorlevel 1 (
    echo [FAIL] Export failed
    exit /b 1
  )
  echo === Export OK: build\windows\TDHeroDefense.exe ===
) else if "%1"=="test" (
  echo === Running core test suite ===
  "%GODOT_CONSOLE%" --headless --path "%PROJECT_DIR%" --script res://tests/test_runner.gd
) else if "%1"=="sim" (
  echo === Running balance simulator ^(runs seed [verbose]^) ===
  "%GODOT_CONSOLE%" --headless --path "%PROJECT_DIR%" --script res://tools/sim/sim_runner.gd -- %2 %3 %4
) else (
  echo === Running editor / project ===
  "%GODOT_EXE%" --path "%PROJECT_DIR%"
)

endlocal
