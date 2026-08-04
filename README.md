# cclibc

基于 [glibc-all-in-one](https://github.com/matrix1001/glibc-all-in-one) 的 **libc 环境一键切换工具** Python 实现，依赖 `patchelf` + `binutils`

- 一条命令把任意 ELF 切到任意 glibc 版本（支持 2.23 ~ 2.43 全系列）
- 自动处理动态链接器、RUNPATH、依赖库、gdb 调试符号
- 支持针对旧 glibc 编译程序、i386 架构

## 安装

```bash
cd cclibc
sudo ./install.sh
```

流程：检查/安装系统依赖 → glibc-all-in-one + glibc-aio → 软链接 `cclibc` 到 `/usr/local/bin`（PATH 仅此一种方式）→ 询问是否下载 libc

下载 libc 时二选一：

| 模式 | 说明 |
|------|------|
| `standard`（推荐） | 仅 LTS 版 amd64 libc：2.23 / 2.27 / 2.31 / 2.35 / 2.39，不下载 old-releases |
| `advanced` | 全量所有 libc 版本（含 old-releases 补全） |

两种模式对同一 glibc 主版本都只下载**最新修订**

手动安装：

```bash
sudo apt install patchelf binutils gcc zstd tar
git clone https://github.com/matrix1001/glibc-all-in-one.git ~/glibc-all-in-one
cd ~/glibc-all-in-one && pip install -e . && glibc-aio mirror update
sudo ln -sf ~/cclibc/cclibc /usr/local/bin/cclibc   # PATH (仅软链接方式)
```

## 命令参数

| 命令 | 说明 |
|------|------|
| `switch <elf> <目标> [-n]` | 切换环境；`-n` 用 replace-needed 方式 |
| `restore <elf>` | 恢复备份 |
| `check <elf>` | 查看 ELF 环境 / libc 版本信息 |
| `list` / `download <版本>` | 已下载环境 / 下载（封装 glibc-aio） |
| `gdb <elf>` / `debug <elf>` | 打印 gdb 命令 / pwndbg 启动调试 (自动带符号) |
| `run <elf>` | 直接运行 |
| `compile <src> [版本] [-o out] [--arch]` | 针对旧 glibc 编译 |
| `fix-dbg <版本>` | 补建调试符号 (build-id + 库目录绑定) |


`cclibc <elf>` = check

`cclibc <elf> <目标>` = switch 简写，如：`cclibc <elf> 2.35` （自动选最接近版本）

目标还可以写成`./libc.so.6`，cclibc会自动识别并切换到目标环境

## 快速上手

```bash
# 1. 识别 libc 版本 
$ cclibc ./libc-2.23.so
文件    : libc-2.23.so
架构    : amd64
版本    : 2.23-0ubuntu11.3
BuildID : 30773be8cf5bfed9d910c8473dd44eaab2e705ab
[+] 已下载的精确环境: 2.23-0ubuntu11.3_amd64

# 2. 一键切换
$ cclibc ./pwn 2.23-0ubuntu11.3_amd64
[*] ELF: ./pwn (amd64)
[+] 已备份原文件 → ./pwn.cclibc.bak
[+] interpreter → /home/kali/glibc-all-in-one/libs/2.23-0ubuntu11.3_amd64/x86_64-linux-gnu/ld-linux-x86-64.so.2
[+] RUNPATH → /home/kali/glibc-all-in-one/libs/2.23-0ubuntu11.3_amd64/x86_64-linux-gnu
[+] 调试符号已绑定 (23 个库)

[+] 切换完成: ./pwn → 2.23-0ubuntu11.3_amd64

# 3. 确认当前环境 
$ cclibc ./pwn
ELF      : ./pwn (amd64)
Interpreter : /home/kali/glibc-all-in-one/libs/2.23-0ubuntu11.3_amd64/x86_64-linux-gnu/ld-linux-x86-64.so.2
RPATH/RUNPATH: /home/kali/glibc-all-in-one/libs/2.23-0ubuntu11.3_amd64/x86_64-linux-gnu
NEEDED    : libc.so.6
[+] → 当前环境: 2.23-0ubuntu11.3_amd64

# 4. gdb 调试
$ cclibc debug ./pwn
pwndbg> p &system
$2 = (int (*)(const char *)) 0x7ffff78453a0 <__libc_system>
pwndbg> p *stdout
$4 = {
  _flags = 0xfbad2887,
  _IO_read_ptr = 0x7ffff7bc56a3 <_IO_2_1_stdout_+131> "\n",
  _IO_read_end = 0x7ffff7bc56a3 <_IO_2_1_stdout_+131> "\n",
  _IO_read_base = 0x7ffff7bc56a3 <_IO_2_1_stdout_+131> "\n",
  _IO_write_base = 0x7ffff7bc56a3 <_IO_2_1_stdout_+131> "\n",
  _IO_write_ptr = 0x7ffff7bc56a3 <_IO_2_1_stdout_+131> "\n",
  _IO_write_end = 0x7ffff7bc56a3 <_IO_2_1_stdout_+131> "\n",
  _IO_buf_base = 0x7ffff7bc56a3 <_IO_2_1_stdout_+131> "\n",
  _IO_buf_end = 0x7ffff7bc56a4 <_IO_2_1_stdout_+132> "",
  _IO_save_base = 0x0,
  _IO_backup_base = 0x0,
  _IO_save_end = 0x0,
  _markers = 0x0,
  _chain = 0x7ffff7bc48e0 <_IO_2_1_stdin_>,
  _fileno = 0x1,
  _flags2 = 0x0,
  _old_offset = 0xffffffffffffffff,
  _cur_column = 0x0,
  _vtable_offset = 0x0,
  _shortbuf = "\n",
  _lock = 0x7ffff7bc6780 <_IO_stdfile_1_lock>,
  _offset = 0xffffffffffffffff,
  _codecvt = 0x0,
  _wide_data = 0x7ffff7bc47a0 <_IO_wide_data_1>,
  _freeres_list = 0x0,
  _freeres_buf = 0x0,
  __pad5 = 0x0,
  _mode = 0xffffffff,
  _unused2 = '\000' <repeats 19 times>
}
```


## gdb 调试

`switch` 时已自动把调试符号绑定到 libc 目录，**直接启动即可**：

```bash
pwndbg ./pwn          # 直接可看 libc 符号, 无需任何参数
cclibc debug ./pwn    # 等价, 用 pwndbg 启动并额外带上符号路径
```

验证符号：`p &system` 应显示 `<__libc_system>`；`ptype struct malloc_chunk` 应展开结构。

## 针对旧 glibc 编译

新 gcc 编译的二进制要求高版本符号（GLIBC_2.34），无法在老 glibc 运行。`compile` 自动下载对应 `libc6-dev` 并修正链接脚本：

```bash
cclibc compile hello.c 2.23
cclibc compile hello.c 2.35 --arch i386    # 需要已下载 i386 环境
```

## 架构与目录

| 架构 | env 后缀 | 库目录 |
|------|----------|--------|
| amd64 | `_amd64` | `x86_64-linux-gnu/` |
| i386 | `_i386` | `i386-linux-gnu/` |

```
~/glibc-all-in-one/libs/<版本ID>_<架构>/
├── x86_64-linux-gnu/     # ld / libc.so.6 / 其他 .so
└── .debug/               # debug symbols + build-id
```

glibc 版本与 Ubuntu 对应：2.23→16.04, 2.27→18.04, 2.31→20.04, 2.35→22.04, 2.39→24.04, 2.41→25.04（无 2.25；非 LTS 版本走 old-releases 镜像）。

## 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `CCLIBC_AIO` | `~/glibc-all-in-one` | glibc-all-in-one 根目录 |
| `CCLIBC_LIBS` | `<AIO>/libs` | 环境存放目录 |
| `CCLIBC_DEV` | `~/cclibc/dev` | libc6-dev 缓存 (compile 用) |
