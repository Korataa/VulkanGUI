#!/bin/bash

echo "Compiling Vulkan shaders..."

glslc shader2d.vert -o shader2d_vert.spv || exit 1
glslc shader2d.frag -o shader2d_frag.spv || exit 1
glslc ui.vert -o ui_vert.spv || exit 1
glslc ui.frag -o ui_frag.spv || exit 1
glslc ui_sdf.frag -o ui_sdf.spv || exit 1

echo "All shaders compiled successfully!"
