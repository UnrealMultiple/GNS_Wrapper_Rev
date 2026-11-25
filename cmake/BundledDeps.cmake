# Builds the pinned third_party/protobuf (and, when USE_CRYPTO=OpenSSL,
# third_party/openssl) submodules.
#
# GameNetworkingSockets runs find_package() and check_symbol_exists() during
# its configure step, so the bundled libraries must already exist when it is
# added.  Everything is built below ${CMAKE_BINARY_DIR}, exactly like the
# Linux build: the dependencies are built in build/third_party/ and installed
# into build/deps.
#
# On Windows GNS uses BCrypt (see GNS_WRAPPER_CRYPTO), so only protobuf is
# built, as a static library with the static CRT.

include_guard( GLOBAL )

include( ProcessorCount )
ProcessorCount( _gns_cpu_count )
if( _gns_cpu_count EQUAL 0 )
    set( _gns_cpu_count 1 )
endif()

set( GNS_WRAPPER_DEPS_DIR "${CMAKE_BINARY_DIR}/deps"
     CACHE PATH "Install prefix for the bundled dependencies" )

# ---------------------------------------------------------------------------
# protobuf (CMake-based)
# ---------------------------------------------------------------------------

set( _gns_pb_src "${CMAKE_CURRENT_LIST_DIR}/../third_party/protobuf" )
set( _gns_pb_build "${CMAKE_BINARY_DIR}/third_party/protobuf-build" )

# protobuf's CMake project names the archive "libprotobuf" and adds no further
# prefix, so MSVC produces libprotobuf.lib while other toolchains produce
# libprotobuf.a.
if( MSVC )
    set( _gns_pb_library "${GNS_WRAPPER_DEPS_DIR}/lib/libprotobuf.lib" )
    set( _gns_protoc "${GNS_WRAPPER_DEPS_DIR}/bin/protoc.exe" )
else()
    set( _gns_pb_library "${GNS_WRAPPER_DEPS_DIR}/lib/libprotobuf.a" )
    set( _gns_protoc "${GNS_WRAPPER_DEPS_DIR}/bin/protoc" )
endif()

if( NOT EXISTS "${_gns_pb_src}/cmake/CMakeLists.txt" )
    message( FATAL_ERROR
        "third_party/protobuf is missing. Run: git submodule update --init" )
endif()

if( NOT EXISTS "${_gns_protoc}" OR NOT EXISTS "${_gns_pb_library}" )
    message( STATUS "Building bundled protobuf..." )
    file( MAKE_DIRECTORY "${_gns_pb_build}" )

    # Match the outer build's toolchain.  Without this the dependency can be
    # built for another architecture (or with another runtime) when the outer
    # project does not use the default Visual Studio generator.
    set( _gns_pb_generator_args )
    if( CMAKE_GENERATOR )
        list( APPEND _gns_pb_generator_args -G "${CMAKE_GENERATOR}" )
        if( CMAKE_GENERATOR_PLATFORM )
            list( APPEND _gns_pb_generator_args -A "${CMAKE_GENERATOR_PLATFORM}" )
        endif()
        if( CMAKE_GENERATOR_TOOLSET )
            list( APPEND _gns_pb_generator_args -T "${CMAKE_GENERATOR_TOOLSET}" )
        endif()
    endif()

    set( _gns_pb_config_args
        -DCMAKE_BUILD_TYPE=Release
        "-DCMAKE_INSTALL_PREFIX=${GNS_WRAPPER_DEPS_DIR}"
        -DCMAKE_CXX_STANDARD=11
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -Dprotobuf_BUILD_TESTS=OFF
        -Dprotobuf_BUILD_SHARED_LIBS=OFF
        -Dprotobuf_BUILD_EXAMPLES=OFF
        -Dprotobuf_WITH_ZLIB=OFF
    )
    if( MSVC )
        # Keep the dependency on the same static CRT as GNS and the wrapper.
        list( APPEND _gns_pb_config_args -Dprotobuf_MSVC_STATIC_RUNTIME=ON )
    else()
        list( APPEND _gns_pb_config_args -DCMAKE_POSITION_INDEPENDENT_CODE=ON )
    endif()

    execute_process(
        COMMAND "${CMAKE_COMMAND}"
            -S "${_gns_pb_src}/cmake"
            -B "${_gns_pb_build}"
            ${_gns_pb_generator_args}
            ${_gns_pb_config_args}
        RESULT_VARIABLE _gns_pb_configure
        OUTPUT_FILE "${_gns_pb_build}/configure.log"
        ERROR_FILE "${_gns_pb_build}/configure.log.err"
    )
    if( NOT _gns_pb_configure EQUAL 0 )
        message( FATAL_ERROR "Configuring bundled protobuf failed, see "
                             "${_gns_pb_build}/configure.log.err" )
    endif()

    execute_process(
        COMMAND "${CMAKE_COMMAND}" --build "${_gns_pb_build}"
                --config Release
                --parallel ${_gns_cpu_count} --target install
        RESULT_VARIABLE _gns_pb_build_result
        OUTPUT_FILE "${_gns_pb_build}/build.log"
        ERROR_FILE "${_gns_pb_build}/build.log.err"
    )
    if( NOT _gns_pb_build_result EQUAL 0 )
        message( FATAL_ERROR "Building bundled protobuf failed, see "
                             "${_gns_pb_build}/build.log.err" )
    endif()
endif()

set( Protobuf_INCLUDE_DIR "${GNS_WRAPPER_DEPS_DIR}/include"
     CACHE PATH "" FORCE )
set( Protobuf_LIBRARY "${_gns_pb_library}" CACHE FILEPATH "" FORCE )
set( Protobuf_PROTOC_EXECUTABLE "${_gns_protoc}" CACHE FILEPATH "" FORCE )
set( Protobuf_USE_STATIC_LIBS ON CACHE BOOL "" FORCE )

# ---------------------------------------------------------------------------
# OpenSSL (perl Configure based)
#
# Only needed for the OpenSSL crypto backend.  Windows defaults to BCrypt,
# which uses the OS primitives and therefore has no dependency to build.
# ---------------------------------------------------------------------------

if( GNS_WRAPPER_CRYPTO STREQUAL "OpenSSL" )
    set( _gns_ssl_src "${CMAKE_CURRENT_LIST_DIR}/../third_party/openssl" )
    set( _gns_ssl_build "${CMAKE_BINARY_DIR}/third_party/openssl-build" )

    if( NOT EXISTS "${_gns_ssl_src}/Configure" )
        message( FATAL_ERROR
            "third_party/openssl is missing. Run: git submodule update --init" )
    endif()

    if( NOT EXISTS "${GNS_WRAPPER_DEPS_DIR}/lib/libcrypto.a" )
        message( STATUS "Building bundled OpenSSL..." )
        file( MAKE_DIRECTORY "${_gns_ssl_build}" )

        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E chdir "${_gns_ssl_build}"
                sh "${_gns_ssl_src}/config"
                no-shared no-tests no-zlib
                --prefix=${GNS_WRAPPER_DEPS_DIR}
                --openssldir=${GNS_WRAPPER_DEPS_DIR}/ssl
            RESULT_VARIABLE _gns_ssl_configure
            OUTPUT_FILE "${_gns_ssl_build}/configure.log"
            ERROR_FILE "${_gns_ssl_build}/configure.log.err"
        )
        if( NOT _gns_ssl_configure EQUAL 0 )
            message( FATAL_ERROR "Configuring bundled OpenSSL failed, see "
                                 "${_gns_ssl_build}/configure.log.err" )
        endif()

        foreach( _gns_ssl_target build_libs install_dev )
            execute_process(
                COMMAND "${CMAKE_COMMAND}" -E chdir "${_gns_ssl_build}"
                    make -j${_gns_cpu_count} ${_gns_ssl_target}
                RESULT_VARIABLE _gns_ssl_result
                OUTPUT_FILE "${_gns_ssl_build}/${_gns_ssl_target}.log"
                ERROR_FILE "${_gns_ssl_build}/${_gns_ssl_target}.log.err"
            )
            if( NOT _gns_ssl_result EQUAL 0 )
                message( FATAL_ERROR "OpenSSL target ${_gns_ssl_target} failed, see "
                                     "${_gns_ssl_build}/${_gns_ssl_target}.log.err" )
            endif()
        endforeach()
    endif()

    set( OPENSSL_ROOT_DIR "${GNS_WRAPPER_DEPS_DIR}" CACHE PATH "" FORCE )
    set( OPENSSL_INCLUDE_DIR "${GNS_WRAPPER_DEPS_DIR}/include" CACHE PATH "" FORCE )
    set( OPENSSL_CRYPTO_LIBRARY "${GNS_WRAPPER_DEPS_DIR}/lib/libcrypto.a"
         CACHE FILEPATH "" FORCE )
    set( OPENSSL_SSL_LIBRARY "${GNS_WRAPPER_DEPS_DIR}/lib/libssl.a"
         CACHE FILEPATH "" FORCE )
    set( OPENSSL_USE_STATIC_LIBS ON CACHE BOOL "" FORCE )

    # FindOpenSSL reads pkg-config metadata to discover static link dependencies.
    # Without this the system openssl.pc advertises zlib/brotli/zstd, which the
    # bundled static build does not need (and those targets may not exist).
    set( ENV{PKG_CONFIG_PATH} "${GNS_WRAPPER_DEPS_DIR}/lib/pkgconfig" )
    set( ENV{PKG_CONFIG_LIBDIR} "${GNS_WRAPPER_DEPS_DIR}/lib/pkgconfig" )
endif()
