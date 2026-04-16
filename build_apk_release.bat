@echo off
echo ================================================
echo  Fitter Welder Pro - Build APK Release
echo ================================================
echo.
cd /d "%~dp0"
echo [1/3] flutter pub get...
flutter pub get
if errorlevel 1 (
    echo BLAD: flutter pub get
    pause
    exit /b 1
)
echo OK
echo.
echo [2/3] flutter build apk --release...
flutter build apk --release
if errorlevel 1 (
    echo BLAD: flutter build apk
    pause
    exit /b 1
)
echo OK
echo.
echo [3/3] Kopiowanie APK...
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "app-release-NOWY.apk"
echo.
echo ================================================
echo  GOTOWE! Plik: app-release-NOWY.apk
echo ================================================
echo.
pause
