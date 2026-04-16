@echo off
chcp 65001 >nul
echo ========================================
echo Cut List App - Build Script for Windows
echo ========================================
echo.

cd /d "%~dp0"

echo [1/4] Checking Flutter dependencies...
call flutter pub get
if errorlevel 1 (
    echo ERROR: flutter pub get failed
    pause
    exit /b 1
)
echo OK
echo.

echo [2/4] Creating Flutter Windows build assets...
mkdir windows\build\android_debug 2>nul
mkdir windows\build\incrcomp_update-dart2_do_not_remove 2>nul

REM Run flutter build to generate assets
call flutter build windows --debug --verbosity=error 2>nul

if exist "windows\build\flutter_assets" (
    echo OK - Flutter assets generated
) else (
    echo WARNING - Flutter assets may need manual generation
)
echo.

echo [3/4] Generating Visual Studio project with CMake...
cd windows
if exist "build" rmdir /s /q build
cmake -G "Visual Studio 17 2022" -A x64 -B build -S . -DCMAKE_BUILD_TYPE=Debug
if errorlevel 1 (
    echo ERROR: CMake failed
    pause
    exit /b 1
)
echo OK
cd ..
echo.

echo [4/4] Building with MSBuild...
cd windows\build
"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" cut_list_app.sln /p:Configuration=Debug /p:Platform=x64 /maxcpucount:4 /nologo /verbosity:minimal
if errorlevel 1 (
    echo ERROR: MSBuild failed
    pause
    exit /b 1
)
cd ..\..

echo.
echo ========================================
echo BUILD SUCCESSFUL!
echo ========================================
echo.
echo Executable: windows\build\Debug\cut_list_app.exe
echo.
echo To run:
echo   start windows\build\Debug\cut_list_app.exe
echo.
pause
