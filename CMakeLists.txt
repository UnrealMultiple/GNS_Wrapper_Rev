cmake_minimum_required( VERSION 3.16 )
project( GNS_Wrapper LANGUAGES C CXX )

# ---------------------------------------------------------------------------
# GameNetworkingSockets source / headers
# ---------------------------------------------------------------------------

set( GNS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/reference/gamenetworkingsockets"
     CACHE PATH "GameNetworkingSockets checkout" )

option( GNS_WRAPPER_BUILD_GNS
        "Build GameNetworkingSockets from GNS_ROOT instead of using a prebuilt library"
        ON )

option( GNS_WRAPPER_LINK_STATIC
        "Link GameNetworkingSockets statically (the Linux original did this)"
        ON )

set( GNS_WRAPPER_GNS_LIBRARY ""
     CACHE FILEPATH "Override: prebuilt GNS library or import library (e.g. steamnetworkingsockets.lib)" )

option( GNS_WRAPPER_ORIGINAL_FLAGS
        "Reproduce the observed GCC 8.3 flags (-O3 -g1, non-strict aliasing, etc.)"
        OFF )

# ---------------------------------------------------------------------------
# Build or find GNS
# ---------------------------------------------------------------------------

if( GNS_WRAPPER_BUILD_GNS )
    if( GNS_WRAPPER_LINK_STATIC )
        set( BUILD_STATIC_LIB ON  CACHE BOOL "" FORCE )
        set( BUILD_SHARED_LIB OFF CACHE BOOL "" FORCE )
    else()
        set( BUILD_STATIC_LIB OFF CACHE BOOL "" FORCE )
        set( BUILD_SHARED_LIB ON  CACHE BOOL "" FORCE )
    endif()
    set( BUILD_EXAMPLES OFF CACHE BOOL "" FORCE )
    set( BUILD_TESTS    OFF CACHE BOOL "" FORCE )
    set( BUILD_TOOLS    OFF CACHE BOOL "" FORCE )
    set( CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "" FORCE )

    add_subdirectory( ${GNS_ROOT} ${CMAKE_BINARY_DIR}/GameNetworkingSockets )

    if( GNS_WRAPPER_LINK_STATIC )
        set( GNS_LINK_TARGET GameNetworkingSockets_s )
    else()
        set( GNS_LINK_TARGET GameNetworkingSockets )
    endif()
elseif( GNS_WRAPPER_GNS_LIBRARY )
    set( GNS_LINK_TARGET ${GNS_WRAPPER_GNS_LIBRARY} )
else()
    message( FATAL_ERROR
        "Set GNS_WRAPPER_GNS_LIBRARY to a prebuilt GNS/steamnetworkingsockets "
        "library, or enable GNS_WRAPPER_BUILD_GNS." )
endif()

# ---------------------------------------------------------------------------
# Wrapper
# ---------------------------------------------------------------------------

add_library( GNS_Wrapper SHARED
    PluginSource/GNS_API.cpp
)

# The original Linux .so contains main() (DWARF: main.cpp @ 0xde40);
# the Windows DLL does not.
if( NOT WIN32 )
    target_sources( GNS_Wrapper PRIVATE
        PluginSource/LinuxProject/GNS_Wrapper/main.cpp )
endif()

target_include_directories( GNS_Wrapper PRIVATE "${GNS_ROOT}/include" )

target_link_libraries( GNS_Wrapper PRIVATE ${GNS_LINK_TARGET} )

set_target_properties( GNS_Wrapper PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS ON
    OUTPUT_NAME GNS_Wrapper
)

if( WIN32 )
    # The Windows original imported only KERNEL32 (plus GNS), i.e. static CRT.
    if( MSVC )
        set_property( TARGET GNS_Wrapper PROPERTY
            MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" )
        target_sources( GNS_Wrapper PRIVATE PluginSource/GNS_Wrapper.def )
    endif()
else()
    # Original libGNS_Wrapper.so: RUNPATH $ORIGIN, BIND_NOW, no SONAME.
    set_target_properties( GNS_Wrapper PROPERTIES
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "$ORIGIN"
        NO_SONAME TRUE
    )
    target_link_options( GNS_Wrapper PRIVATE
        "-Wl,-z,now"
        "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/PluginSource/GNS_Wrapper.map"
    )
endif()

if( GNS_WRAPPER_ORIGINAL_FLAGS AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang" )
    target_compile_options( GNS_Wrapper PRIVATE
        -O3
        -g1
        -fno-strict-aliasing
        -fomit-frame-pointer
        -fthreadsafe-statics
        -fexceptions
        -frtti
    )
endif()
