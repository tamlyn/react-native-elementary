cmake_minimum_required(VERSION 3.4.1)
project(Elementary)

set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 17)  # Updated to C++17

add_library(react-native-elementary SHARED
            ../cpp/react-native-elementary.cpp
            ../cpp/audioengine.cpp
            ../cpp/AudioResourceLoader.cpp
            cpp-adapter.cpp
)

set_target_properties(react-native-elementary PROPERTIES
  LINK_FLAGS "-Wl,-z,max-page-size=16384")

include_directories(
            ../cpp
            ../cpp/vendor/elementary/runtime
)
