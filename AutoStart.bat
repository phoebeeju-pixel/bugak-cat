@echo off
rem Turn Windows startup auto-run ON/OFF for Bugak the cat.
rem Run this file again to turn it off.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StartupToggle.ps1"
