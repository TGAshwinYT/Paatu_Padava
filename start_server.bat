@echo off
echo ==========================================
echo   Paaatu_Padava - Starting Full Stack
echo ==========================================
echo.

:: Start Backend in a new window
echo [STAGING] Starting Backend (FastAPI)...
start "Paaatu_Padava Backend" cmd /k "cd backend && py -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

:: Start Frontend in a new window
echo [STAGING] Starting Frontend (Vite)...
start "Paaatu_Padava Frontend" cmd /k "cd frontend && npm run dev"
