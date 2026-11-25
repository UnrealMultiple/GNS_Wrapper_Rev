# GNS_Wrapper

## Build

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGNS_WRAPPER_BUILD_GNS=ON -DGNS_WRAPPER_LINK_STATIC=ON
cmake --build build -j
```

## Windows

```bat
cmake -S . -B build -DGNS_WRAPPER_BUILD_GNS=OFF -DGNS_WRAPPER_GNS_LIBRARY=<gns>\steamnetworkingsockets.lib
cmake --build build --config Release
```
