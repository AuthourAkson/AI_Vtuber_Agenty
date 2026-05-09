cmake_minimum_required(VERSION 3.14)
project(ai_vtuber_agent LANGUAGES CXX)

set(BINARY_NAME "ai_vtuber_agent")

cmake_policy(SET CMP0063 NEW)

find_package(Flutter REQUIRED)
include(${FLUTTER_CMAKE_DIR}/flutter_generated.cmake)

add_executable(${BINARY_NAME}
  "flutter/generated_plugin_registrant.cc"
  "runner/flutter_window.cpp"
  "runner/main.cpp"
  "runner/utils.cpp"
  "runner/win32_window.cpp"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_compile_definitions(${BINARY_NAME} PRIVATE "UNICODE" "_UNICODE")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

set_target_properties(${BINARY_NAME} PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
  OUTPUT_NAME "${BINARY_NAME}"
  WIN32_EXECUTABLE TRUE
)

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${INSTALL_BUNDLE_BIN_DIR}"
  COMPONENT Runtime)

install(FILES "${ICU_INITIALIZATION_DATA_PATH}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(DIRECTORY "${FLUTTER_ASSET_DIR_NAME}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${AOT_LIBRARY_PATH}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime
)
