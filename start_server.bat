@echo off
echo ==========================================
echo    Paatu Padava - 2-Part Architecture
echo ==========================================
echo.

:: 1. Start Backend Data API (Hugging Face Role)
echo [1/2] Starting Data API (Python/FastAPI) on Port 8000...
start "Paatu Padava - Brain" cmd /k "cd backend-data-hf && python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

:: 2. Start Frontend UI (Vercel Role) - Now with Integrated IFrame Player
echo [2/2] Starting Frontend (React/Vite)...
start "Paatu Padava - UI" cmd /k "cd frontend-react && npm run dev"

echo.
echo ==========================================
echo ALL SERVICES STARTING...
echo Data API: http://localhost:8000
echo Frontend: http://localhost:5173
echo.
echo Note: Audio Proxy (8001) has been decommissioned. 
echo Playback is now handled via integrated YouTube IFrame.
echo ==========================================
pause
