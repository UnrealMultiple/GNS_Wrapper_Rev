# GNS_Wrapper — 逆向重建

本目录是根据 `../GNS_Wrapper_bins/` 中的两个二进制重建的 C ABI 包装层源码。

结论先行：

- **Linux `libGNS_Wrapper.so`**：把 Valve 的 `steamnetworkingsockets`（GameNetworkingSockets，接口版本 `SteamNetworkingSockets012`）**静态链入**了 `.so`，只动态依赖 `libprotobuf.so.3.15.3.0`、`libssl.so.1.1`、`libcrypto.so.1.1` 和系统 C++ 运行库。
- **Windows `GNS_Wrapper.dll`**：只是一个很薄的导入层，从 `steamnetworkingsockets.dll` 导入 5 个符号，自身导出同样的 12 个 `GNS_*` 函数。
- 两边包装层的业务逻辑几乎一致；唯一可观测的实现差异是 `GNS_Recieve` 的缓冲区写入：Windows 用 MSVC 的 `memcpy_s`，Linux 用不受长度约束的 `memcpy`。

---

## 1. 产物信息

| | Linux | Windows |
|---|---|---|
| 文件 | `GNS_Wrapper_bins/linux/libGNS_Wrapper.so` | `GNS_Wrapper_bins/windows/GNS_Wrapper.dll` |
| 格式 | ELF64 x86-64, DYN | PE32 i386 |
| 大小 | 1,236,120 B | 121,856 B |
| Build ID / 时间 | `deac35d716b2beae6dd0d309046bc10b200926ef` | `Fri Oct 16 10:18:18 2026` |
| 调试信息 | 有 DWARF（`-g1`），未 strip | 有 PDB 路径 |
| 依赖 | protobuf 3.15.3 / OpenSSL 1.1 / libstdc++ / libc | `steamnetworkingsockets.dll`, `KERNEL32.dll` |
| 关键字符串 | `opensource Oct 12 2026 14:28:25` | `opensource Jun 21 2024 15:57:17`（在 `steamnetworkingsockets.dll` 中） |

Windows PDB 路径：

```
C:\Projects\Terraria\GameNetworkingSockets\PluginSource\Win32\Release\GNS_Wrapper.pdb
```

Linux DWARF 中的源码路径：

```
/projects/GNS_Wrapper/PluginSource/GNS_API.cpp
/projects/GNS_Wrapper/PluginSource/LinuxProject/GNS_Wrapper/main.cpp
```

Linux 编译参数（DWARF `DW_AT_producer`）：

```
GNU C++11 8.3.0 -mtune=generic -march=x86-64 -g1 -O3 -std=c++11
-fno-strict-aliasing -fomit-frame-pointer -fpic
-fthreadsafe-statics -fexceptions -frtti
```

Linux 动态段：`RUNPATH=$ORIGIN`、`BIND_NOW`、无 SONAME。因此原包把 `libprotobuf`/`libssl`/`libcrypto` 放在 `.so` 同目录。

---

## 2. 导出/导入接口

### 2.1 12 个导出（两边完全一致）

| 名称 | 返回 | 参数 | 说明 |
|---|---|---|---|
| `GNS_Startup` | `void` | — | 初始化 GNS、设置 localhost 身份、创建 poll group |
| `GNS_Shutdown` | `void` | — | 销毁 poll group、`GameNetworkingSockets_Kill()` |
| `GNS_Recieve` | `uint32` | `uint8* buf, int& resultSize, int maxTransportSize` | 接收 1 条消息；返回来源连接句柄 |
| `GNS_ConnectionEvents` | `int` | `uint32* eventBuffer, int maxEventSize` | 驱动回调并取走事件；返回事件对数 |
| `GNS_Listen` | `uint32` | `int port` | 监听 `[::]:port`（全零 IPv6 = 通配） |
| `GNS_ListenIPPort` | `uint32` | `const char* addr` | 解析 `ip:port` 后监听 |
| `GNS_CloseListen` | `void` | `uint32 socket` | 关闭监听 socket |
| `GNS_ConnectString` | `uint32` | `const char* addr` | 解析 `ip:port` 后连接 |
| `GNS_Connect` | `uint32` | `const SteamNetworkingIPAddr&` | 直接按地址连接 |
| `GNS_CloseSocket` | `void` | `uint32 socket` | `CloseConnection(socket, 0, "Closed", true)` |
| `GNS_SocketSend` | `void` | `uint32 socket, const void* buf, int len` | reliable 发送（flags = 8） |
| `GNS_GetSocketAddress` | `bool` | `uint32 socket, char* out, int outSize` | 取远端地址，带端口格式化 |

> `Recieve` 拼写错误是原样保留的。

Windows 导出表顺序为字母序（.def 风格），且没有 `main`；Linux `.so` 额外包含一个 `main()` 桩（`main.cpp` 仅 3 行）。

### 2.2 Windows 导入

`GNS_Wrapper.dll` 只从 `steamnetworkingsockets.dll` 导入：

```
GameNetworkingSockets_Init
GameNetworkingSockets_Kill
SteamNetworkingSockets_LibV12
SteamNetworkingIPAddr_ToString
SteamNetworkingIPAddr_ParseString
```

其余全部通过 `ISteamNetworkingSockets` 虚表调用，所以包装层不需要链接更多符号。

---

## 3. 虚表索引（由反汇编直接读出）

| 调用 | 偏移 | 接口方法 |
|---|---|---|
| `GNS_Startup` | `+0x140` | `ResetIdentity` |
| `GNS_Startup` | `+0xc0` | `CreatePollGroup` |
| `GNS_Shutdown` | `+0xc8` | `DestroyPollGroup` |
| `GNS_Recieve` | `+0xd8` | `ReceiveMessagesOnPollGroup` |
| `GNS_ConnectionEvents` | `+0x148` | `RunCallbacks` |
| listener/client | `+0x20` | `AcceptConnection` |
| listener/client | `+0x28` | `CloseConnection` |
| listener/client | `+0xd0` | `SetConnectionPollGroup` |
| `GNS_Connect*` | `+0x08` | `ConnectByIPAddress` |
| `GNS_Listen*` | `+0x00` | `CreateListenSocketIP` |
| `GNS_GetSocketAddress` | `+0x78` | `GetConnectionInfo` |
| `GNS_CloseListen` | `+0x30` | `CloseListenSocket` |
| `GNS_SocketSend` | `+0x58` | `SendMessageToConnection` |

这些偏移与公开的 GameNetworkingSockets `SteamNetworkingSockets012`（v1.4.1 及以后）一致。重建源码用公开头文件编译后，`ResetIdentity`/`CreatePollGroup`/`ReceiveMessagesOnPollGroup`/`RunCallbacks` 等偏移逐项相同。

---

## 4. 逐函数语义

### `GNS_Startup`

```cpp
GameNetworkingSockets_Init(nullptr, errMsg);
s_networkSockets = SteamNetworkingSockets();
SteamNetworkingIdentity identity;
identity.SetLocalHost();          // IPAddress ::1, port 0
s_networkSockets->ResetIdentity(&identity);
s_pollGroup = s_networkSockets->CreatePollGroup();
```

`SetLocalHost()` 的内联痕迹很清楚：身份对象 136 字节，前 8 字节写成 `{type=1 (IPAddress), cbSize=18}`，联合体清零后第 23 字节置 1（IPv6 `::1` 的最后一个字节），端口为 0。这说明包装层使用**未认证的 localhost 身份**，不做证书/Steam 身份认证。

初始化失败只调用 `FatalError`，**不会 abort/exit**，随后仍继续执行。

### `GNS_Recieve`

```cpp
resultSize = 0;
if (!s_networkSockets) return 0;
message = nullptr;
if (ReceiveMessagesOnPollGroup(s_pollGroup, &message, 1) <= 0) return 0;
if (message->m_conn) {
    // Linux: memcpy(buf, m_pData, m_cbSize)
    // Windows: memcpy_s(buf, maxTransportSize, m_pData, m_cbSize)
    resultSize = message->m_cbSize;
}
connection = message->m_conn;   // 在 Release 之前取
message->Release();
return connection;
```

关键点：

- 每次只取 **1** 条消息。
- 返回的是 **来源连接句柄**，不是长度；长度通过 `resultSize` 返回。
- `m_conn == 0` 的消息被丢弃（仍然 `Release`）。
- Linux 版本**完全不检查** `maxTransportSize`，存在调用方缓冲区溢出风险；Windows 版本等价于 `memcpy_s`，长度不足会走 CRT invalid-parameter 路径。
- 消息结构偏移与公开头一致：x64 `m_cbSize=+8, m_conn=+0xc, m_pfnRelease=+0xb8`；x86 `m_cbSize=+4, m_conn=+8, m_pfnRelease=+0xb4`。

### `GNS_ConnectionEvents`

```cpp
s_networkSockets->RunCallbacks();
int count = 0;
for (uint32 e : eventData) eventBuffer[count++] = e;
eventData.clear();
return count / 2;
```

- `maxEventSize` 被忽略，不做任何边界检查。
- 返回事件**对数**（写入的 uint32 数量除以 2）。
- 每个事件是 `{ type, connection }` 两个 uint32：
  - `1` = 已连接
  - `2` = 已断开

### 回调

监听端 `OnListenerConnectionStatusChanged`：

- `Connecting`：`AcceptConnection`；如果返回不是 `k_EResultOK`，关闭连接；否则 `SetConnectionPollGroup`，失败也关闭。
- `Connected`：压入 `{1, hConn}`。
- `ClosedByPeer` / `ProblemDetectedLocally`：
  - 旧状态是 `Connected` → 压入 `{2, hConn}`；
  - 旧状态是 `Connecting` → 直接 `CloseConnection`（不产生事件）。

客户端 `OnClientConnectionStatusChanged`：

- `Connecting`：`SetConnectionPollGroup`，失败则 `CloseConnection` 并压入 `{2, hConn}`。
- `Connected`：压入 `{1, hConn}`。
- `ClosedByPeer` / `ProblemDetectedLocally`：压入 `{2, hConn}`（不看旧状态）。

`eventData` 是文件级 `static std::vector<uint32>`；两个回调都是 `static` 函数。

### 其余

- `GNS_Listen`：`addr.Clear(); addr.m_port = (uint16)port;` 即 `[::]:port`，再 `CreateListenSocketIP(addr, 1, &opt)`，option 为连接状态回调。
- `GNS_ListenIPPort` / `GNS_ConnectString`：`SteamNetworkingIPAddr::ParseString()` 的返回值被忽略。
- `GNS_CloseSocket`：`CloseConnection(h, 0, "Closed", true)`，即允许 linger。
- `GNS_SocketSend`：`SendMessageToConnection(h, buf, len, k_nSteamNetworkingSend_Reliable /*8*/, nullptr)`。
- `GNS_GetSocketAddress`：`GetConnectionInfo` 成功后对 `info.m_addrRemote` 调 `ToString(out, outSize, true)`；返回 `GetConnectionInfo` 的结果。

### `FatalError`

`vsprintf`/`vsprintf_s` 到 2048 字节栈缓冲，去掉末尾换行，`printf(buffer)`，然后 flush stdout/stderr。它**只是打印**，不终止进程。

---

## 5. Linux 源码行号

DWARF 行表可以精确恢复原文件的分段（用于对照重建）：

| 函数/段落 | 行 |
|---|---|
| `FatalError` | 29–46 |
| `GNS_Startup` | 48–64 |
| `GNS_Shutdown` | 66–79 |
| `GNS_Recieve` | 81–111 |
| `GNS_ConnectionEvents` | 112–128 |
| `OnListenerConnectionStatusChanged` | 130–183 |
| `OnClientConnectionStatusChanged` | 186–222 |
| `GNS_ListenIPPort` | 224–231 |
| `GNS_Listen` | 233–241 |
| `GNS_CloseListen` | 243–245 |
| `GNS_ConnectString` | 248–256 |
| `GNS_Connect` | 258–263 |
| `GNS_GetSocketAddress` | 266–277 |
| `GNS_CloseSocket` | 280–282 |
| `GNS_SocketSend` | 285–287 |

`main.cpp` 的 `main` 在源码第 3 行。

> 重建文件的 `FatalError`、`GNS_Startup`、`GNS_Shutdown` 与上表行号一致；`GNS_Recieve` 及之后因注释/空行排布有少量偏移。行为与二进制一致，行号仅作为原始格式证据。

---

## 6. 重建文件

```
GNS_Wrapper_Rev/
├── CMakeLists.txt
├── PluginSource/
│   ├── GNS_API.cpp                    # 重建的包装层（主要产物）
│   ├── GNS_Wrapper.def                # Windows 12 个导出
│   ├── GNS_Wrapper.map                # Linux 只导出 GNS_* + main
│   └── LinuxProject/GNS_Wrapper/
│       └── main.cpp                   # 原 .so 中的 main() 桩
└── reference/gamenetworkingsockets/   # clone 的公开 GNS 源码（pinned v1.4.1 / 505c697）
```

参考源码固定在 `v1.4.1`（commit `505c697d0abef5da2ff3be35aa4ea3687597c3e9`），接口版本同样是 `SteamNetworkingSockets012`。直接 `git checkout` 到其他 tag 也可以编译本包装层。

`GNS_API.cpp` 用公开 GNS 头文件 + 原编译参数做过编译验证：

```sh
g++ -std=c++11 -O3 -g1 -fno-strict-aliasing -fomit-frame-pointer -fpic \
    -fthreadsafe-statics -fexceptions -frtti \
    -Ireference/gamenetworkingsockets/include \
    -c PluginSource/GNS_API.cpp -o GNS_API.o
```

12 个 `GNS_*` 符号全部生成，且虚表偏移与原 `.so` 一致（`ResetIdentity +0x140`、`CreatePollGroup +0xc0`、`ReceiveMessagesOnPollGroup +0xd8`、`RunCallbacks +0x148`、`AcceptConnection +0x20`、`CloseConnection +0x28`、`SetConnectionPollGroup +0xd0` 等逐项相同）。

另外用公开 **GNS v1.4.1** 静态库把重建源码编译成 `.so`，跑了本机回环端到端测试：

```sh
g++ -std=c++11 -O3 -g1 -fno-strict-aliasing -fomit-frame-pointer -fpic \
    -fthreadsafe-statics -fexceptions -frtti -I/tmp/gns141/include -shared \
    PluginSource/GNS_API.cpp PluginSource/LinuxProject/GNS_Wrapper/main.cpp \
    /tmp/gns141/build/src/libGameNetworkingSockets_s.a \
    -lprotobuf -lssl -lcrypto -lpthread \
    -Wl,-rpath,'$ORIGIN' -Wl,-z,now -o libGNS_Wrapper.so
```

测试覆盖：

1. `GNS_Startup()` → `GNS_Listen(37123)` → `GNS_ConnectString("127.0.0.1:37123")`；
2. 轮询 `GNS_ConnectionEvents`，收到两条 `{1, handle}`（客户端与监听端各一条）；
3. `GNS_GetSocketAddress(client, ...)` 返回 `127.0.0.1:37123`；
4. `GNS_SocketSend(client, "hello-gns-wrapper", 17)`；
5. `GNS_Recieve(...)` 返回**服务端连接句柄**、`resultSize=17`、内容一致；
6. 关闭服务端连接后，客户端收到 `{2, clientHandle}`；
7. `GNS_CloseSocket` / `GNS_CloseListen` / `GNS_Shutdown` 正常退出。

结果：`PASS`。

一个值得注意的可观测行为：**本地主动关闭的一侧不一定会产生断开事件**，只有收到对端关闭/本地检测到问题的那一侧会压入 `{2, handle}`。重建代码保留了这一逻辑。

### 构建 Linux `.so`（静态链入 GNS）

```sh
cmake -S . -B build -DGNS_WRAPPER_BUILD_GNS=ON -DGNS_WRAPPER_LINK_STATIC=ON
cmake --build build -j
```

该流程已在本机用 pinned GNS v1.4.1 + protobuf 3.21 + OpenSSL 3 完整构建通过；`GNS_Wrapper.map` 把动态导出限制为 12 个 `GNS_*` 加 `main`，与原 `.so` 一致。原二进制使用 protobuf 3.15.3 / OpenSSL 1.1，复刻发布包时需要换成对应版本并把三个 `.so` 放到同目录。

需要 GNS 的构建依赖（protobuf 开发包 + `protoc`、OpenSSL 1.1+）。要复刻原二进制，还需要：

- 把 `libprotobuf.so.3.15.3.0`、`libssl.so.1.1`、`libcrypto.so.1.1` 放在 `.so` 同目录；
- `-Wl,-rpath,$ORIGIN -Wl,-z,now`（CMake 已配置）；
- 打开 `-DGNS_WRAPPER_ORIGINAL_FLAGS=ON`。

### 构建 Windows DLL（薄封装）

原版链接的是 Valve 的 `steamnetworkingsockets.dll`（不是开源构建的 `GameNetworkingSockets.dll`）。使用 MSVC x86 编译 `GNS_API.cpp`，链接对应 `.lib`：

```bat
cl /nologo /LD /O2 /MT /EHsc /I<gns>\include GNS_API.cpp ^
   /link /DEF:GNS_Wrapper.def steamnetworkingsockets.lib
```

或通过 CMake 的 `GNS_WRAPPER_GNS_LIBRARY` 指向导入库。

---

## 7. 版本与不确定性

- Linux/Windows 二进制都对应 **`SteamNetworkingSockets012`** 接口。公开仓库中 v1.4.1 起使用该接口，v1.5.x 仍为 012。
- 原二进制的 GNS 头文件来自 `/projects/steamnetworkingsockets/include/steam/`，且包含 `SteamNetworkingSockets_Poll`、`SetManualPollMode`、`PreFormatDebugOutput` 等 Steam 内部扩展；其头文件行号与公开 tag 不完全一致，说明构建时用的是 Valve 内部快照，而非某个公开 tag。
- 包装层本身只依赖稳定的公开 C++ 接口，因此重建源码可直接对公开 `GameNetworkingSockets` 编译。本次已用 clone 下来的公开源码头文件验证编译。
- `GNS_Recieve` 的 `memcpy_s`/`memcpy` 差异通过 `_WIN32` 条件编译保留；原 Linux 二进制确实没有长度检查。
- `FatalError` 不终止进程这一点容易被误判，重建时按二进制行为保留。

---

## 8. 二次核对结果（与二进制的偏差）

逐项对照了反汇编、DWARF 行表、导出/导入表和重建后的目标文件：

| 检查项 | 二进制行为 | 重建 | 结果 |
|---|---|---|---|
| `GNS_Startup` | `Init(nullptr, err)` → `SteamNetworkingSockets()` → `SetLocalHost()` → `ResetIdentity(+0x140)` → `CreatePollGroup(+0xc0)` | 同序，同一组虚表偏移和身份常量 `{type=1, cbSize=18, ::1}` | 一致 |
| `GNS_Shutdown` | `DestroyPollGroup(+0xc8)` → `GameNetworkingSockets_Kill()`，失败分支不检查 | 同序、同空指针语义 | 一致 |
| `GNS_Recieve` Linux | 取 1 条；`m_conn != 0` 才复制；`memcpy` 不检查 `maxTransportSize`；返回 `m_conn` | 同 | 一致 |
| `GNS_Recieve` Windows | `memcpy_s(buf, maxTransportSize, ...)`；同样返回 `m_conn` | `_WIN32` 分支映射到 `memcpy_s` | 一致 |
| `GNS_ConnectionEvents` | `RunCallbacks(+0x148)`；复制全部元素；清空；返回 `count/2`；忽略 `maxEventSize` | 同 | 一致 |
| 监听回调 | `AcceptConnection`/`SetConnectionPollGroup` 失败即 `CloseConnection`；`Connected`→`{1,h}`；`4/5` 且旧状态 `Connected`→`{2,h}`，旧状态 `Connecting`→关闭 | 同 | 一致 |
| 客户端回调 | `Connecting` 加入 poll group，失败关闭并 `{2,h}`；`Connected`→`{1,h}`；`4/5`→`{2,h}` | 同 | 一致 |
| `GNS_Listen` | `addr.Clear(); m_port=port`；option `{201,5,callback}`；`CreateListenSocketIP(+0x00)` | 同，生成的目标代码与原函数几乎逐指令对应 | 一致 |
| `GNS_ListenIPPort` / `GNS_ConnectString` | `ParseString` 返回值忽略；option 同上；分别走 `+0x00`/`+0x08` | 同 | 一致 |
| `GNS_Connect` | 直接传地址，`ConnectByIPAddress(+0x08)` | 同 | 一致 |
| `GNS_GetSocketAddress` | `GetConnectionInfo(+0x78)` 成功后 `m_addrRemote.ToString(buf,size,true)`，返回原 bool | 同 | 一致 |
| `GNS_CloseSocket` | `CloseConnection(h,0,"Closed",true)` | 同（r8=1） | 一致 |
| `GNS_SocketSend` | `SendMessageToConnection(h,buf,len,8,nullptr)` | 同（r8=8, r9=0） | 一致 |
| `FatalError` | `vsprintf`/`vsprintf_s` → 去尾换行 → `printf(buffer)` → flush stdout/stderr；**不退出** | 同 | 一致 |
| Linux 导出 | 12 个 `GNS_*` + `main` | version script 精确导出这 13 个 | 一致 |
| Windows 导出/导入 | 12 个 `GNS_*`；导入 GNS 5 个符号 + KERNEL32 | `.def` 12 个；源码只用那 5 个导入符号 | 一致 |
| Linux ELF 元数据 | `RUNPATH=$ORIGIN`、`BIND_NOW`、无 SONAME | CMake 已配置 | 一致 |
| Windows CRT | 只导入 KERNEL32，说明静态 CRT (`/MT`) | CMake 设置 `MSVC_RUNTIME_LIBRARY=MultiThreaded` | 一致 |

### 仍然存在的非行为性偏差

1. **GNS 源码版本不同**：原二进制是 Valve 内部 `steamnetworkingsockets` 快照（2024/2026 构建，含 `SteamNetworkingSockets_Poll` 等内部扩展）；重建使用公开 `v1.4.1`。接口版本、虚表布局和包装层行为一致，但内部实现/头文件行号不同。
2. **源码文本不是逐字节相同**：`GNS_VSPRINTF`/`GNS_MEMCPY` 是为同时表达 Linux/Windows 差异而加的薄宏；注释和空行排布也不同。编译出的函数语义一致。
3. **编译器产生的代码形状不同**：现代 GCC 会对 `GNS_ConnectionEvents` 的复制循环做自动向量化，原 GCC 8.3 是标量循环；栈帧大小也略有差异。输入/输出行为相同。
4. **Windows 未在本机用 MSVC 重编**：已按导入表/PDB 证据配置 `/MT`、x86、`.def`；实际二进制仍是对 `steamnetworkingsockets.dll` 的薄封装。
5. **`GNS_Connect` 的参数形式是推断的**：重建用 `const SteamNetworkingIPAddr&`。若原函数按值传参，被调方看到的仍是同一个地址，ABI/行为不变。
6. **`GNS_Recieve` 首参写为 `uint8*`**：IDA 显示为 `void*`；C# 声明为 `byte*`。三者 ABI 相同。

---

## 9. Windows 与 Linux 的行为差异

包装层源码是同一套逻辑，但两边不是同一份 GNS 二进制，且存在 ABI/CRT 差异。按影响排序：

### 9.1 实质性差异：`GNS_Recieve` 的越界处理

正常消息（`m_cbSize <= maxTransportSize`）下两边完全一致。差异只在缓冲区不够大时：

| | Linux | Windows |
|---|---|---|
| 写入方式 | `memcpy(buf, m_pData, m_cbSize)` | `memcpy_s(buf, maxTransportSize, m_pData, m_cbSize)` |
| 缓冲区不足 | **越界写**（UB，可能破坏调用方内存） | 不越界；把 `maxTransportSize` 字节清零，`errno=34`，调用 `_invalid_parameter_noinfo()`（默认释放 CRT 下继续；若自定义 handler 终止则进程退出） |
| 后续返回值 | `resultSize = m_cbSize`，返回连接句柄 | 同样 `resultSize = m_cbSize`，返回连接句柄 |

因此：

- Linux 版本必须由调用方保证缓冲区 ≥ 最大消息长度，否则可被远端用大消息触发溢出。
- Windows 版本不会溢出，但仍会报告一个大于缓冲区的 `resultSize`；调用方若盲信该值仍可能读越界。

### 9.2 ABI / 结构体布局差异（源码已用字段访问，逻辑不变）

| 项目 | Linux x64 | Windows x86 |
|---|---|---|
| 调用约定 | SysV AMD64 | cdecl |
| `SteamNetConnectionStatusChangedCallback_t` packing | `VALVE_CALLBACK_PACK_SMALL`（4） | `VALVE_CALLBACK_PACK_LARGE`（8） |
| `m_info.m_eState` 偏移 | `+180` (`0xb4`) | `+184` (`0xb8`) |
| `m_eOldState` 偏移 | `+700` (`0x2bc`) | `+704` (`0x2c0`) |
| `SteamNetworkingMessage_t` | x64 布局（`m_cbSize +8`, `m_conn +0xc`） | x86 布局（`m_cbSize +4`, `m_conn +8`） |

重建源码通过 `pInfo->m_info.m_eState`、`message->m_cbSize` 等字段访问，不依赖硬编码偏移，所以这部分不产生行为差异。

### 9.3 C++ `bool` 返回值的 ABI 细节

`GNS_GetSocketAddress` 原生返回 1 字节 `bool`，而 C# 的 `bool` 默认按 4 字节 Win32 `BOOL` 封送：

- Linux 原实现：`movzx eax, al`，高 24 位为 0，C# 读取正确。
- Windows 原实现：`mov al, bl`，只保证 AL；EAX 高位未清零。

正常路径下（`GetConnectionInfo` 返回 true）只要 AL=1，C# 判为非零即可；失败路径理论上有“假 true”风险，但 C# 侧缓冲区是新分配的 64 字节零初始化数组，最多得到空字符串。这是原版 P/Invoke 声明未加 `[MarshalAs(UnmanagedType.U1)]` 留下的 ABI 隐患，不是包装层逻辑差异。

### 9.4 底层 GNS 引擎不同

| | Linux | Windows |
|---|---|---|
| GNS 形态 | 静态链入 Valve 内部快照 | 导入 Valve 的 `steamnetworkingsockets.dll` |
| 构建字符串 | `opensource Oct 12 2026 14:28:25` | `opensource Jun 21 2024 15:57:17` |
| 依赖 | protobuf 3.15.3 / OpenSSL 1.1 | 由 DLL 自带 |
| 接口版本 | `SteamNetworkingSockets012` | `SteamNetworkingSockets012` |

接口版本相同，包装层看到的 API 相同；但底层实现的默认值、日志、加密/证书细节、协议优化可能随版本不同。**不能仅凭包装层相同就断言两端线缆行为完全一致**。

### 9.5 `FatalError` 的格式化边界

- Linux：`vsprintf` 到 2048 字节，超长会栈溢出。
- Windows：`vsprintf_s` 到 2048 字节，超长走 CRT invalid-parameter 路径。

现有错误消息都很短，正常不会触发。两边都只打印、flush，不退出。
