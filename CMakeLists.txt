cmake_minimum_required(VERSION 3.16)

# Collect source files
CollectSourceFiles(
    ${CMAKE_CURRENT_SOURCE_DIR}
    PRIVATE_SOURCES
    # Exclude
    ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt
)

# Include directories
CollectIncludeDirectories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    PUBLIC_INCLUDES
)

# Group sources for IDE
GroupSources(${CMAKE_CURRENT_SOURCE_DIR})
