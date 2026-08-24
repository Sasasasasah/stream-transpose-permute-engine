@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE RTL_SXM_FULL
iverilog -g2012 -Wall -s tb_sxm_full ^
  -o sim\rtl\tb_sxm_full.vvp ^
  rtl\sxm_command_decode.v ^
  rtl\sxm_transpose_superlane_leaf.v ^
  rtl\sxm_transpose_control_column.v ^
  rtl\sxm_transpose_result_buffer_array.v ^
  rtl\sxm_permute_engine.v ^
  rtl\sxm_slice.v ^
  rtl\sxm_full.v ^
  tb\tb_sxm_full.v ^
  > sim\logs\sxm_full_rtl_compile.log 2>&1
if errorlevel 1 goto fail

vvp sim\rtl\tb_sxm_full.vvp ^
  > sim\logs\sxm_full_rtl_regression.log 2>&1
if errorlevel 1 goto fail
type sim\logs\sxm_full_rtl_regression.log
findstr /C:"RTL_SXM_FULL_REGRESSION FAIL" ^
  sim\logs\sxm_full_rtl_regression.log >nul
if not errorlevel 1 goto fail
findstr /X /C:"RTL_SXM_FULL_REGRESSION PASS" ^
  sim\logs\sxm_full_rtl_regression.log >nul
if errorlevel 1 goto fail

echo ================================
echo SXM_FULL_REGRESSION TEST_PASS
echo ================================
popd
exit /b 0

:fail
echo SXM_FULL_REGRESSION FAILED
popd
exit /b 1
