cmake_minimum_required(VERSION 3.10)

# ONNX Runtime and OpenCV are downloaded/extracted by the Flutter plugin's
# android/build.gradle into android/OnnxRuntime/ and android/OpenCV/. These paths
# are resolved relative to this CMakeLists.txt (which sits at android/src/main/cpp/).
set(OnnxRuntime_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../OnnxRuntime")
include_directories(${OnnxRuntime_DIR}/headers)

set(OpenCV_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../OpenCV/sdk/native/jni")
find_package(OpenCV REQUIRED)
include_directories(${OpenCV_INCLUDE_DIRS})

aux_source_directory(. SOURCES)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffast-math -Ofast -Os")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility=hidden -fvisibility-inlines-hidden -fdata-sections -ffunction-sections")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--gc-sections")

add_library(Native SHARED ${SOURCES})

find_library(log-lib log)

add_library(onnxruntime SHARED IMPORTED)
set_target_properties(
        onnxruntime
        PROPERTIES IMPORTED_LOCATION
        ${OnnxRuntime_DIR}/jni/${ANDROID_ABI}/libonnxruntime.so)

target_link_libraries(
        Native
        onnxruntime
        ${OpenCV_LIBS}
        jnigraphics
        ${log-lib})

# Copy the runtime next to libNative.so so Gradle packages it into the AAR.
add_custom_command(TARGET Native POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
        ${OnnxRuntime_DIR}/jni/${ANDROID_ABI}/libonnxruntime.so
        ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libonnxruntime.so)
