glslangValidator.exe -V shader.vert
glslangValidator.exe -V shader.frag
glslc.exe shader.vert -o vert.spv
glslc.exe shader.frag -o frag.spv
pause