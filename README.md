# GNS_Wrapper

C ABI wrapper (12 `GNS_*` functions) around GameNetworkingSockets, reconstructed from the original Linux `libGNS_Wrapper.so` and Windows `GNS_Wrapper.dll`. Details: [docs/README.md](docs/README.md).

## Build (Linux)

Requires CMake ≥ 3.16, a C++11 compiler, protobuf (with `protoc`) and OpenSSL. Clone GNS `v1.4.1` into `reference/gamenetworkingsockets` first:

```sh
git clone --branch v1.4.1 https://github.com/ValveSoftware/GameNetworkingSockets.git \
    reference/gamenetworkingsockets
cmake -S . -B build -DGNS_WRAPPER_BUILD_GNS=ON -DGNS_WRAPPER_LINK_STATIC=ON
cmake --build build -j
```

Produces `build/libGNS_Wrapper.so`.

## Build (Windows)

MSVC x86, against Valve's `steamnetworkingsockets.lib` (open-source GNS exports a different DLL name):

```bat
cl /nologo /LD /O2 /MT /EHsc /I<gns>\include GNS_API.cpp ^
   /link /DEF:PluginSource\GNS_Wrapper.def steamnetworkingsockets.lib
```

Or with CMake: `-DGNS_WRAPPER_BUILD_GNS=OFF -DGNS_WRAPPER_GNS_LIBRARY=<gns>\steamnetworkingsockets.lib`.
