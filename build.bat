@echo off
chcp 65001 >nul
title KinoKino 0.4 - сборка установщика
echo ==========================================
echo          KinoKino 0.4 Windows Setup
echo ==========================================
where node >nul 2>nul
if errorlevel 1 (
  echo Не найден Node.js. Установите LTS-версию с https://nodejs.org/
  pause
  exit /b 1
)
echo.
echo [1/3] Установка зависимостей...
call npm install
if errorlevel 1 goto error
echo.
echo [2/3] Сборка Windows установщика...
call npm run dist
if errorlevel 1 goto error
echo.
echo [3/3] Готово! Установщик находится в папке dist.
explorer dist
pause
exit /b 0
:error
echo.
echo Ошибка сборки. Проверьте подключение к интернету и сообщения выше.
pause
exit /b 1
