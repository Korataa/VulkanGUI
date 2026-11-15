@echo off
setlocal

echo Compiling Vulkan shaders...

glslc shader2d.vert -o shader2d_vert.spv || goto :error
glslc shader2d.frag -o shader2d_frag.spv || goto :error
glslc ui.vert -o ui_vert.spv || goto :error
glslc ui.frag -o ui_frag.spv || goto :error
glslc ui_sdf.frag -o ui_sdf.spv || goto :error

echo All shaders compiled successfully.
exit /b 0

:error
echo Shader compilation failed.
exit /b 1