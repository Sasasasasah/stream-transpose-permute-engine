@echo off
setlocal EnableExtensions

call "%~dp0run_sxm_transpose_leaf_regression.bat"
if errorlevel 1 goto fail

call "%~dp0run_sxm_transpose_control_regression.bat"
if errorlevel 1 goto fail

call "%~dp0run_sxm_result_buffer_regression.bat"
if errorlevel 1 goto fail

call "%~dp0run_sxm_permute_regression.bat"
if errorlevel 1 goto fail

call "%~dp0run_sxm_slice_regression.bat"
if errorlevel 1 goto fail

call "%~dp0run_sxm_32x32_regression.bat"
if errorlevel 1 goto fail

call "%~dp0run_sxm_slice_cmodel_regression.bat"
if errorlevel 1 goto fail

call "%~dp0run_sxm_full_regression.bat"
if errorlevel 1 goto fail

echo ================================
echo SXM_ALL_REGRESSION TEST_PASS
echo ================================
exit /b 0

:fail
echo ================================
echo SXM_ALL_REGRESSION FAILED
echo ================================
exit /b 1
