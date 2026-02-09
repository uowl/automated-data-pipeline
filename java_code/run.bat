@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

REM Load .env if present (set DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME)
if exist .env (
  for /f "usebackq eol=# tokens=1,* delims==" %%a in (".env") do (
    set "key=%%a"
    set "val=%%b"
    set "key=!key:export =!"
    if not "!key!"=="" set "!key!=!val!"
  )
)

where mvn >nul 2>&1
if errorlevel 1 (
  echo Maven (mvn) not found. Install Maven and add it to PATH, or run: mvn jetty:run
  exit /b 1
)
where java >nul 2>&1
if errorlevel 1 (
  echo Java (java) not found. Install Java 11+ and add it to PATH.
  exit /b 1
)

echo Starting pipeline at http://localhost:8080/
echo Press Ctrl+C to stop.
call mvn jetty:run
