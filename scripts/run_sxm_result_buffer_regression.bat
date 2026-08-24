@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\cmodel mkdir sim\cmodel
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE RTL_SXM_RESULT_BUFFER
iverilog -g2012 -Wall -s tb_sxm_transpose_result_buffer_array ^
  -o sim\rtl\tb_sxm_transpose_result_buffer_array.vvp ^
  rtl\sxm_transpose_result_buffer_array.v ^
  tb\tb_sxm_transpose_result_buffer_array.v ^
  > sim\logs\sxm_result_buffer_rtl_compile.log 2>&1
if errorlevel 1 goto fail

vvp sim\rtl\tb_sxm_transpose_result_buffer_array.vvp ^
  > sim\logs\sxm_result_buffer_rtl_regression.log 2>&1
if errorlevel 1 goto fail
type sim\logs\sxm_result_buffer_rtl_regression.log
findstr /C:"RTL_SXM_RESULT_BUFFER_REGRESSION FAIL" ^
  sim\logs\sxm_result_buffer_rtl_regression.log >nul
if not errorlevel 1 goto fail
findstr /X /C:"RTL_SXM_RESULT_BUFFER_REGRESSION PASS" ^
  sim\logs\sxm_result_buffer_rtl_regression.log >nul
if errorlevel 1 goto fail

echo RUN_STAGE CMODEL_SXM_RESULT_BUFFER
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto fail
set "VSROOT="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT goto fail
call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64 ^
  > sim\logs\sxm_result_buffer_msvc_environment.log 2>&1
if errorlevel 1 goto fail

cl /nologo /std:c++17 /W4 /WX /EHsc /c ^
  cmodel\sxm_transpose_result_buffer_array_model.cpp ^
  /Fo:sim\cmodel\sxm_transpose_result_buffer_array_model.obj ^
  > sim\logs\sxm_result_buffer_cmodel_compile.log 2>&1
if errorlevel 1 goto fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c ^
  cmodel\test_sxm_transpose_result_buffer_array.cpp ^
  /Fo:sim\cmodel\test_sxm_transpose_result_buffer_array.obj ^
  >> sim\logs\sxm_result_buffer_cmodel_compile.log 2>&1
if errorlevel 1 goto fail
link /NOLOGO /OUT:sim\cmodel\test_sxm_transpose_result_buffer_array.exe ^
  sim\cmodel\sxm_transpose_result_buffer_array_model.obj ^
  sim\cmodel\test_sxm_transpose_result_buffer_array.obj ^
  >> sim\logs\sxm_result_buffer_cmodel_compile.log 2>&1
if errorlevel 1 goto fail

sim\cmodel\test_sxm_transpose_result_buffer_array.exe ^
  > sim\logs\sxm_result_buffer_cmodel_regression.log 2>&1
if errorlevel 1 goto fail
type sim\logs\sxm_result_buffer_cmodel_regression.log
findstr /C:"CMODEL_SXM_RESULT_BUFFER_REGRESSION FAIL" ^
  sim\logs\sxm_result_buffer_cmodel_regression.log >nul
if not errorlevel 1 goto fail
findstr /X /C:"CMODEL_SXM_RESULT_BUFFER_REGRESSION PASS" ^
  sim\logs\sxm_result_buffer_cmodel_regression.log >nul
if errorlevel 1 goto fail

echo ========================================
echo SXM_RESULT_BUFFER_REGRESSION TEST_PASS
echo ========================================
popd
exit /b 0

:fail
echo SXM_RESULT_BUFFER_REGRESSION FAILED
popd
exit /b 1
