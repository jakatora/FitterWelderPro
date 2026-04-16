@echo off
REM Fix Flutter Windows Build Script
REM This script fixes common Flutter Windows build issues

echo [1/7] Copying Flutter engine files to ephemeral directory...
mkdir "windows\flutter\ephemeral\cpp_client_wrapper" 2>nul
copy "%FLUTTER_ROOT%\bin\cache\artifacts\engine\windows-x64\flutter_windows.dll.lib" "windows\flutter\ephemeral\" >nul
copy "%FLUTTER_ROOT%\bin\cache\artifacts\engine\windows-x64\*.h" "windows\flutter\ephemeral\" >nul
copy "%FLUTTER_ROOT%\bin\cache\artifacts\engine\windows-x64\cpp_client_wrapper\*.h" "windows\flutter\ephemeral\cpp_client_wrapper\" >nul

echo [2/7] Cleaning old build directory...
rmdir /s /q build >nul 2>nul

echo [3/7] Running flutter create to regenerate Windows files...
flutter create --platforms=windows . >nul 2>&1

echo [4/7] Building debug version first to generate INSTALL.vcxproj...
flutter build windows --debug >nul 2>&1

echo [5/7] Building release version...
flutter build windows >nul 2>&1

echo [6/7] Building Flutter assets...
flutter build bundle >nul 2>&1

echo [7/7] Copying assets to release directory...
mkdir "build\windows\x64\install\data" 2>nul
xcopy "build\flutter_assets\*" "build\windows\x64\install\data\" /e /i >nul
copy "C:\flutter\bin\cache\artifacts\engine\windows-x64\flutter_windows.dll" "build\windows\x64\install\" >nul 2>&1

echo.
echo Build complete!
echo Output is in: build\windows\x64\install\
echo IMPORTANT: Make sure all files are in the same directory.
echo Files needed:
echo   - cut_list_app.exe
echo   - flutter_windows.dll
echo   - data/ folder (with flutter_assets)
pause
