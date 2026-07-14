cmake_minimum_required(VERSION 3.16)
project(emacs_cpp_demo LANGUAGES CXX)

# Modern C++ and a compile_commands.json so clangd understands the project.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Turn on a healthy set of warnings (great for testing clangd/clang-tidy).
add_compile_options(-Wall -Wextra -Wpedantic)

add_executable(demo
  src/main.cpp
  src/mathutils.cpp)

target_include_directories(demo PRIVATE include)
