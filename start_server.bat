@echo off
echo ==========================================
echo   Paatu_Paaduva - Starting Full Stack
echo ==========================================
echo.

:: Start Backend in a new window
echo [STAGING] Starting Backend (FastAPI)...
start "Paatu_Paaduva Backend" cmd /k "cd backend && py -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

:: Start Frontend in a new window
echo [STAGING] Starting Frontend (Vite)...
start "Paatu_Paaduva Frontend" cmd /k "cd frontend && npm run dev"
