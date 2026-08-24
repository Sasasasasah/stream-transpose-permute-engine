@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\cmodel mkdir sim\cmodel
if not exist sim\rtl mkdir sim\rtl
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE CMODEL_SXM_SLICE
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto fail
set "VSROOT="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT goto fail
call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64 ^
  > sim\logs\sxm_slice_cmodel_msvc_environment.log 2>&1
if errorlevel 1 goto fail

cl /nologo /std:c++17 /W4 /WX /EHsc /c ^
  cmodel\sxm_transpose_result_buffer_array_model.cpp ^
  /Fo:sim\cmodel\sxm_transpose_result_buffer_array_model_slice.obj ^
  > sim\logs\sxm_slice_cmodel_compile.log 2>&1
if errorlevel 1 goto fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c ^
  cmodel\sxm_permute_engine_model.cpp ^
  /Fo:sim\cmodel\sxm_permute_engine_model_slice.obj ^
  >> sim\logs\sxm_slice_cmodel_compile.log 2>&1
if errorlevel 1 goto fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c ^
  cmodel\sxm_slice_model.cpp ^
  /Fo:sim\cmodel\sxm_slice_model.obj ^
  >> sim\logs\sxm_slice_cmodel_compile.log 2>&1
if errorlevel 1 goto fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c ^
  cmodel\test_sxm_slice_model.cpp ^
  /Fo:sim\cmodel\test_sxm_slice_model.obj ^
  >> sim\logs\sxm_slice_cmodel_compile.log 2>&1
if errorlevel 1 goto fail
link /NOLOGO /OUT:sim\cmodel\test_sxm_slice_model.exe ^
  sim\cmodel\sxm_transpose_result_buffer_array_model_slice.obj ^
  sim\cmodel\sxm_permute_engine_model_slice.obj ^
  sim\cmodel\sxm_slice_model.obj ^
  sim\cmodel\test_sxm_slice_model.obj ^
  >> sim\logs\sxm_slice_cmodel_compile.log 2>&1
if errorlevel 1 goto fail

sim\cmodel\test_sxm_slice_model.exe ^
  > sim\logs\sxm_slice_cmodel_regression.log 2>&1
if errorlevel 1 goto fail
type sim\logs\sxm_slice_cmodel_regression.log
findstr /X /C:"CMODEL_SXM_SLICE_BASIC PASS" ^
  sim\logs\sxm_slice_cmodel_regression.log >nul
if errorlevel 1 goto fail
findstr /X /C:"CMODEL_SXM_COMMAND_LEGALITY PASS" ^
  sim\logs\sxm_slice_cmodel_regression.log >nul
if errorlevel 1 goto fail
findstr /X /C:"CMODEL_SXM_32X32_SINGLE_BLOCK PASS" ^
  sim\logs\sxm_slice_cmodel_regression.log >nul
if errorlevel 1 goto fail
findstr /X /C:"CMODEL_SXM_32X32_CONTINUOUS PASS" ^
  sim\logs\sxm_slice_cmodel_regression.log >nul
if errorlevel 1 goto fail

echo RUN_STAGE RTL_CANONICAL_TRACE
iverilog -g2012 -Wall -s tb_sxm_32x32 ^
  -o sim\rtl\tb_sxm_32x32_trace.vvp ^
  rtl\sxm_command_decode.v ^
  rtl\sxm_transpose_superlane_leaf.v ^
  rtl\sxm_transpose_control_column.v ^
  rtl\sxm_transpose_result_buffer_array.v ^
  rtl\sxm_permute_engine.v ^
  rtl\sxm_slice.v ^
  tb\tb_sxm_32x32.v ^
  > sim\logs\sxm_slice_trace_rtl_compile.log 2>&1
if errorlevel 1 goto fail
vvp sim\rtl\tb_sxm_32x32_trace.vvp ^
  > sim\logs\sxm_slice_trace_rtl_run.log 2>&1
if errorlevel 1 goto fail

powershell -NoProfile -Command ^
  "$a=Get-Content -LiteralPath 'sim/sxm_rtl_trace.txt'; $b=Get-Content -LiteralPath 'sim/sxm_cmodel_trace.txt'; $n=[Math]::Max($a.Count,$b.Count); for($i=0;$i -lt $n;$i++){ if($a[$i] -cne $b[$i]){ Write-Host ('TRACE_MISMATCH cycle_line=' + $i); Write-Host ('RTL:    ' + $a[$i]); Write-Host ('CMODEL: ' + $b[$i]); exit 1 } }; exit 0" ^
  > sim\logs\sxm_slice_trace_compare.log 2>&1
if errorlevel 1 (
  type sim\logs\sxm_slice_trace_compare.log
  goto fail
)

echo SXM_RTL_CMODEL_TRACE_COMPARE PASS
echo ========================================
echo SXM_SLICE_CMODEL_REGRESSION TEST_PASS
echo ========================================
popd
exit /b 0

:fail
echo SXM_SLICE_CMODEL_REGRESSION FAILED
popd
exit /b 1
