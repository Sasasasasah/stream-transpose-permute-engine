@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE RTL_SXM_TRANSPOSE_CONTROL
iverilog -g2012 -Wall -s tb_sxm_transpose_control_column ^
  -o sim\rtl\tb_sxm_transpose_control_column.vvp ^
  rtl\sxm_transpose_superlane_leaf.v ^
  rtl\sxm_transpose_control_column.v ^
  tb\tb_sxm_transpose_control_column.v ^
  > sim\logs\sxm_transpose_control_rtl_compile.log 2>&1
if errorlevel 1 goto fail

vvp sim\rtl\tb_sxm_transpose_control_column.vvp ^
  > sim\logs\sxm_transpose_control_rtl_regression.log 2>&1
if errorlevel 1 goto fail
type sim\logs\sxm_transpose_control_rtl_regression.log
findstr /C:"RTL_SXM_TRANSPOSE_CONTROL_REGRESSION FAIL" ^
  sim\logs\sxm_transpose_control_rtl_regression.log >nul
if not errorlevel 1 goto fail
findstr /X /C:"RTL_SXM_TRANSPOSE_CONTROL_REGRESSION PASS" ^
  sim\logs\sxm_transpose_control_rtl_regression.log >nul
if errorlevel 1 goto fail

echo RTL_SXM_TRANSPOSE_CONTROL_REGRESSION PASS
echo ============================================
echo SXM_TRANSPOSE_CONTROL_REGRESSION TEST_PASS
echo ============================================
popd
exit /b 0

:fail
echo SXM_TRANSPOSE_CONTROL_REGRESSION FAILED
popd
exit /b 1
