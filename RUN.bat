@echo off
rem 부각이 실행 (고양이_실행.vbs 가 막혀 있을 때 쓰는 대체 실행 파일)
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CatPet.ps1"
exit
