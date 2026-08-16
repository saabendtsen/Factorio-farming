@echo off
setlocal EnableExtensions

rem Entry point for the isolated Factorio production slice test harness.
rem The stages themselves live in run-factorio-tests.ps1 because the harness
rem drives a headless capture run and computes percentile timings.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-factorio-tests.ps1" %*
exit /b %ERRORLEVEL%
