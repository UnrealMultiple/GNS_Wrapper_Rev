# GNS_Wrapper

## Getting the sources

```sh
git clone --depth 1 https://github.com/UnrealMultiple/GNS_Wrapper_Rev.git
cd GNS_Wrapper_Rev
git submodule update --init
```

## Linux

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGNS_WRAPPER_BUILD_GNS=ON -DGNS_WRAPPER_LINK_STATIC=ON
cmake --build build -j
```

## Windows

Run from an x64 Visual Studio developer prompt (CMake 3.16+, Ninja):

```bat
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```
