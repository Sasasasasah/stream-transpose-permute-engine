@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\cmodel mkdir sim\cmodel
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE RTL_SXM_PERMUTE
iverilog -g2012 -Wall -s tb_sxm_permute_engine ^
  -o sim\rtl\tb_sxm_permute_engine.vvp ^
  rtl\sxm_permute_engine.v ^
  tb\tb_sxm_permute_engine.v ^
  > sim\logs\sxm_permute_rtl_compile.log 2>&1
if errorlevel 1 goto fail

vvp sim\rtl\tb_sxm_permute_engine.vvp ^
  > sim\logs\sxm_permute_rtl_regression.log 2>&1
if errorlevel 1 goto fail
type sim\logs\sxm_permute_rtl_regression.log
findstr /C:"RTL_SXM_PERMUTE_REGRESSION FAIL" ^
  sim\logs\sxm_permute_rtl_regression.log >nul
if not errorlevel 1 goto fail
findstr /X /C:"RTL_SXM_PERMUTE_REGRESSION PASS" ^
  sim\logs\sxm_permute_rtl_regression.log >nul
if errorlevel 1 goto fail

echo RUN_STAGE CMODEL_SXM_PERMUTE
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto fail
set "VSROOT="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT goto fail
call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64 ^
  > sim\logs\sxm_permute_msvc_environment.log 2>&1
if errorlevel 1 goto fail

cl /nologo /std:c++17 /W4 /WX /EHsc /c ^
  cmodel\sxm_permute_engine_model.cpp ^
  /Fo:sim\cmodel\sxm_permute_engine_model.obj ^
  > sim\logs\sxm_permute_cmodel_compile.log 2>&1
if errorlevel 1 goto fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c ^
  cmodel\test_sxm_permute_engine.cpp ^
  /Fo:sim\cmodel\test_sxm_permute_engine.obj ^
  >> sim\logs\sxm_permute_cmodel_compile.log 2>&1
if errorlevel 1 goto fail
link /NOLOGO /OUT:sim\cmodel\test_sxm_permute_engine.exe ^
  sim\cmodel\sxm_permute_engine_model.obj ^
  sim\cmodel\test_sxm_permute_engine.obj ^
  >> sim\logs\sxm_permute_cmodel_compile.log 2>&1
if errorlevel 1 goto fail

sim\cmodel\test_sxm_permute_engine.exe ^
  > sim\logs\sxm_permute_cmodel_regression.log 2>&1
if errorlevel 1 goto fail
type sim\logs\sxm_permute_cmodel_regression.log
findstr /C:"CMODEL_SXM_PERMUTE_REGRESSION FAIL" ^
  sim\logs\sxm_permute_cmodel_regression.log >nul
if not errorlevel 1 goto fail
findstr /X /C:"CMODEL_SXM_PERMUTE_REGRESSION PASS" ^
  sim\logs\sxm_permute_cmodel_regression.log >nul
if errorlevel 1 goto fail

echo ==================================
echo SXM_PERMUTE_REGRESSION TEST_PASS
echo ==================================
popd
exit /b 0

:fail
echo SXM_PERMUTE_REGRESSION FAILED
popd
exit /b 1
