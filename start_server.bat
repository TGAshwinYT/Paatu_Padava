@echo off
echo ==========================================
echo    Paatu Padava - 3-Part Architecture
echo ==========================================
echo.

:: 1. Start Backend Data API (Hugging Face Role)
echo [1/3] Starting Data API (Python/FastAPI) on Port 8000...
start "Paatu Padava - Brain" cmd /k "cd backend-data-hf && python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

:: 2. Start Audio Proxy (Render Role)
echo [2/3] Starting Audio Proxy (Python/FastAPI) on Port 8001...
:: Ensure port 8001 is used to match frontend env
start "Paatu Padava - Bouncer" cmd /k "cd backend-proxy-render && set PORT=8001 && python -m uvicorn main:app --host 0.0.0.0 --port 8001"

:: 3. Start Frontend UI (Vercel Role)
echo [3/3] Starting Frontend (React/Vite)...
start "Paatu Padava - UI" cmd /k "cd frontend-react && npm run dev"

echo.
echo ==========================================
echo ALL SERVICES STARTING...
echo Data API: http://localhost:8000
echo Proxy API: http://localhost:8001
echo Frontend: http://localhost:5173
echo ==========================================
pause
