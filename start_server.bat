@echo off
echo ==========================================
echo    Paatu Padava - 2-Part Architecture
echo ==========================================
echo.

:: Add bundled Node/npm runtime to PATH
if exist "D:\Library\Ashwin\Offical\Python\Python313\Lib\site-packages\nodejs_wheel" (
    set "PATH=D:\Library\Ashwin\Offical\Python\Python313\Lib\site-packages\nodejs_wheel;%PATH%"
)

:: Detect Node / Frontend runner
set "FRONTEND_CMD=npm run dev"
where npm >nul 2>nul
if errorlevel 1 (
    echo [INFO] System npm not found in PATH.
    echo [INFO] Using bundled node runtime via Python nodejs_wheel...
    set "FRONTEND_CMD=python -m nodejs_wheel ./node_modules/vite/bin/vite.js"
)

:: 1. Start Backend Data API (Hugging Face Role)
echo [1/2] Starting Data API (Python/FastAPI) on Port 8000...
start "Paatu Padava - Brain" cmd /k "cd backend-data-hf && python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

:: 2. Start Frontend UI (Vercel Role) - Now with Integrated IFrame Player
echo [2/2] Starting Frontend (React/Vite)...
start "Paatu Padava - UI" cmd /k "cd frontend-react && %FRONTEND_CMD%"

echo.
echo ==========================================
echo ALL SERVICES STARTING...
echo Data API: http://localhost:8000
echo Frontend: http://localhost:5173
echo ==========================================
echo.

:: Automatically open the web browser after a brief delay
echo Opening browser to http://localhost:5173 in 3 seconds...
ping 127.0.0.1 -n 4 >nul
start http://localhost:5173

pause
