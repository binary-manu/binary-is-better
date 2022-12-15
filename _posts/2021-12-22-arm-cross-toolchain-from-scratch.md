---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan spelllang=en:
title: ARM cross-toolchain from scratch
category: ELF
---

A _cross toolchain_ is a set of tools (such as compiler, assembler,
linker and related libraries) that run on a kind of system (such as an
AMD64 machine) but produce programs that will run on a different
architecture (ARM, MIPS, ...). Typically, a toolchain installed on one's
system is, conversely, configured to produce programs that run on the
same systems as the toolchain itself: this is called a _native
toolchain_.

Cross toolchains are often needed when building software for embedded or
heavily constrained systems, usually because of two main reasons:

* the target system does not have the ability to run a native toolchain
  for its own architecture, as its CPU, memory, storage or OS
  environment (if any) are too limited;
* the target system can run a native toolchain, but the CPU speed makes
  compiling even moderately large programs painfully slow. Think about
  the earliest Raspberry Pi models.

A cross toolchain allows using a separate system with plenty of memory,
CPU cores, storage and a powerful OS to run the build.  The outputs will
then be copied to the target using a programmer, an SD card or whatever
the target boots from, and run.

A typical scenario involves using an x86-64 system to build software for
some low-power ARM system. And often, this software will consist of a
Linux-based system especially crafted for the task at hand. Many steps
are required to build such complete, albeit small, system. We need:

* a bootloader to take off after the hardware has initialized itself, to
  load the kernel, device tree blobs and initial ramdisks into memory;
* a Linux kernel supporting the target architecture and the devices
  present on the board;
* a set of basic libraries, such as standard C and C++ libraries;
* standard tools that make up the skeleton of the system: an init
  system, a shell, utilities like `cp`, `ls`, …;
* essential files used by libraries and tools and runtime, such as
  `/etc/fstab`, `/etc/passwd`, `/etc/inittab`.

However, the first step to be able to build any of the above for an
embedded system is to grab a cross-toolchain that targets it.

While there are many resources about building cross-compiled kernels,
bootloaders and basic utilities, there is not much information about
building a cross-toolchain. The usual recommendations given by books and
tutorials boils down to:

* grab a precompiled cross-toolchain from one of major providers on the
  net: both [ARM][arm-toolchains] and [Bootlin][bootlin-toolchains]
  release high-quality cross toolchains that run on x86-64 hosts and
  produce code for ARM processors;
* use specialized tools like [buildroot][buildroot] or
  [crosstool-ng][crosstool-ng], which automate the creation of the
  toolchain, starting from a user-defined configuration that can even be
  edited graphically.

Now, there is no doubt that, for anything serious and unless _very
special_ needs arise, using a tried and tested product like the ones
above is by far the best option. They are made by people who know and
are both optimized and free of trivial but subtle errors one could make
while building itself. But...

But using an automated tool takes away the experience (and thus the
knowledge) about building one of the fundamental blocks of your embedded
project. I don't like the idea of blindly using a tool without some
understanding of how it works, so for me building my own cross toolchain
is a must, even if the next step is to throw it away and use a
precompiled one.

Unfortunately, finding accurate information on this topic seems a little
difficult. Your best bet seems to be the [Cross Linux From
Scratch][clfs] book. It shows the steps required to build a cross
toolchain, but it has a number of limitations:

* the latest stable version dates back to 2014;
* it is written for many architectures, but there is no ARM;
* the explanations about why you need certain options are, at least in
  my eyes, a little terse.

So I decided to try and make my own, mixing instructions and tips from
various sources with my own experimentation. Touching problems with your
own hands and finding a solution is invaluable. This document explains
the process I followed and, more importantly, the rationale of each
option or choice.

A warning is due here. While the output toolchain _seems to work_ (it
successfully compiled a bootable Linux system for a Raspberry Pi made by
U-Boot, the Linux kernel, Busybox and an Hello World C++ sample running
on top of that), the whole process is about _learning_. This means that
there are no guarantees that the toolchain does not contain some subtle
bugs that may break specific packages. Also, it is likely not as well
optimized as it could and output code could be suboptimal.  You should
definitely _not_ use it for anything serious.

That being said, let's roll up our sleeves and start building.

## Intro

We will build a cross-toolchain targeting 32-bit ARM processors, but
hosted on a AMD64 system. The latest available versions of GCC, glibc
and the GNU binutils are used. The host system is Arch Linux and we'll
use some of its libraries when building GCC (such as MPFR and GMP). The
final toolchain will be relocatable, meaning you can move it whereever
you like and it will still find include and library folders correctly.

## Prepare the compilation tree and an isolated shell

The very first thing to do is ensuring that the host system has
essential development packages installed:

```bash
sudo pacman -S --noconfirm --needed base-devel
```

Both LFS and CLFS create a new unprivileged user that is employed to
build packages, guaranteeing the maximum isolation between the built
packages and the host system. Using our current user may raise issues,
because most build operations react to environment variables.  If by
chance some variables in our environment clash with parameters build
systems expect, we may inadvertently alter the build.

However, creating a new user for that looks a bit overkill to me. A
simpler approach involves `env` and appropriate shell options to run a
new shell in a clean environment.

Sources and compiled artifacts are kept under a single directory tree.
You can place it everywhere you like, although it should be on a POSIX
filesystem with at least 10GiB of free space. I used
`~/projects/embedded`. This directory will be referenced as `$CROSSDIR`.

Inside this folder, create a new file `activate.bash`, make it
executable, and paster the following code inside:

```bash
#!/usr/bin/env bash

CROSSDIR="$PWD"
TOOLS="$CROSSDIR/mytoolchain/tools"
SYSROOT="$TOOLS/sysroot"
TARGET_TRIPLET=arm-none-linux-gnueabihf
HOST_TRIPLET="$(gcc -dumpmachine)"

exec env -i \
  `: Copy some vars from the current environment` \
  USER="$USER" LOGNAME="$LOGNAME" TERM="$TERM" HOME="$HOME" \
  `: Some other vars are set to specific values` \
  CROSSDIR="$CROSSDIR" TOOLS="$TOOLS" SYSROOT="$SYSROOT" \
  HOST_TRIPLET="$HOST_TRIPLET" TARGET_TRIPLET="$TARGET_TRIPLET" \
  ARCH='arm' CROSS_COMPILE="$TARGET_TRIPLET-" \
  PATH="$TOOLS/bin:/usr/local/bin:/usr/bin" PS1='[\u@(cross)\h \W]\$ ' \
  `: Launch a new instance of bash` \
  bash --norc +h
```

What this file does is launching a new instance of `bash` while purging
the current environment of unwanted items:

* `env` is a tool that modifies the environment before launching a
  process, effectively causing the new process to see an altered
  environment w.r.t. the parent;
* `-i` causes `env` the create an initially empty environment for the
  new process;
* variable definitions in the form `VAR=VALUE`, like `HOME="$HOME"`,
  simply add some variables into the new process environment.  A
  completely empty environment is not functional: most applications
  expect a minimal set of standard variables to be available, such as
  `HOME` and `USER`. They are either copied them from the current
  environment (so that the new shell sees the same values as the current
  shell) or set to specific values.  Some of this variables, like `ARCH`
  or `TARGET_TRIPLET`, will be used and explained later;
* `bash --norc +h` launches a new instance of `bash`, which is asked to
  avoid executing its usual startup files `/etc/bash.bashrc` and
  `~/.bashrc` by means of `--norc`. Without this option, even if the
  environment is clear, stuff could still be added by code contained in
  those files.  `+h` disables command hashing as recommended by LFS
  [environment setup][lfs-envsetup].

Start a new, pristine shell by running:

```bash
./activate.bash
```

A call to `printenv` will confirm that the environment is almost empty.
There are a few thing to note here:

* the `PS1` prompt contains the `(cross)` marker as a reminder that this
  is not our usual environment;
* there is no `DISPLAY`, so X apps will not work; use a regular terminal for
  that;
* there is no `/bin` in the `PATH`, as we assume that our host system
  (Arch Linux) is [usrmerged][usrmerge];
* a custom variable `TOOLS` is initialized to point to the subdirectory
  `mytoolchain/tools`. This is where the compiled cross-toolchain will
  be placed. Its `bin` subdirectory is also added to the `PATH`.

## Grab the sources

To build a complete toolchain, we need the following:

* the [GNU binutils][binutils], which comprise the assembler (`as`), the
  link editor (`ld`) and a bunch of useful extras;
* the [GNU Compiler Collection (GCC)][gcc], providing C and C++
  compilers, as well as an implementation of the C++ standard library;
* a C standard library. Unlike the C++ library, this is not bundled with
  GCC and we get to choose one among a number of choices (glibc, musl,
  …).  To keep things simple, we'll be using the GNU C Library,
  [glibc][glibc], although it will not result in the smallest programs
  for our target system. Other C libraries can help producing smaller
  final executables, but such level of optimization is beyond the scope
  of this article.
* the [Linux kernel][linux] headers, since glibc depends on them when
  built to run on a Linux system.

The following snippet downloads the versions that I tested to
successfully build and place them under `sources`, giving each archive
its own folder:

```bash
mkdir -p "$CROSSDIR/mytoolchain/sources"
cd "$CROSSDIR/mytoolchain/sources"
download_sources() {
  local dirs=(binutils gcc glibc linux)
  local urls=(
    'https://mirror.easyname.at/gnu/binutils/binutils-2.37.tar.xz'
    'https://ftp.nluug.nl/languages/gcc/releases/gcc-11.2.0/gcc-11.2.0.tar.xz'
    'https://ftp.gnu.org/gnu/glibc/glibc-2.34.tar.xz'
    'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.15.7.tar.xz'
  )
  for (( i=0; i < ${#dirs[@]}; i++ )) {
    mkdir -p "${dirs[i]}"
    ( cd "${dirs[i]}" && curl -LO "${urls[i]}" )
  }
}
download_sources
```

We should end up with a file tree like this:

    /home/manu/projects/embedded/mytoolchain/sources
    |-- binutils
    |   `-- binutils-2.37.tar.xz
    |-- gcc
    |   `-- gcc-11.2.0.tar.xz
    |-- glibc
    |   `-- glibc-2.34.tar.xz
    `-- linux
        `-- linux-5.15.7.tar.xz

## Understand the build order

The sources being available, all pieces must be built in the correct
order.  Ideally, there should be a linear build order so that each item
is compiled only once.

This looks simple in theory:

1. first, the cross-binutils. These tools will handle the binary format
   of the _target_ (ARM), but will otherwise run and use libraries from
   the _host_ (x86-64). Only a native x86-64 compiler is required to
   build them, so we can do this right away with our local system
   compiler;
2. Linux kernel headers do not need to be built at all, they are simply
   copied somewhere the cross-compiler will find them, so again
   we can do this step right away;
3. at this point we _could_ build the cross-GCC: again, ideally this
   package emits code for the target but only depends on libraries and
   headers from the host;
4. use the cross-GCC to build glibc for the target.

Unfortunately, this is not possible.

As explained by [LFS][how-lfs] and [crosstool-ng][how-crosstool-ng],
there is a circular dependency between GCC and glibc: glibc is a _target
library_, so it must be compiled with a cross compiler for the target
system and obviously depends on cross-GCC. However, some components
of GCC (such as `libgcc` and `libstdc++`) depend on the C library of the
target. This creates a dependency loop: we need a cross-GCC to build
glibc, but without a built glibc we cannot build a cross-GCC. This
situation is depicted in the following picture:

[![](https://mermaid.ink/img/eyJjb2RlIjoiZ3JhcGggXG4gICAgR0NDW0dDQ10gLS0-IExEW2JpbnV0aWxzXVxuICAgIEdDQyAtLT58Q2lyY3VsYXIgZGVwLnwgQ1tDIExpYnJhcnldXG4gICAgQyAtLT4gR0NDXG4gICAgQyAtLT4gS1tMaW51eCBrZXJuZWwgaGVhZGVyc11cbiAgIiwibWVybWFpZCI6eyJ0aGVtZSI6ImRhcmsifSwidXBkYXRlRWRpdG9yIjpmYWxzZSwiYXV0b1N5bmMiOnRydWUsInVwZGF0ZURpYWdyYW0iOmZhbHNlfQ)](https://mermaid.live/edit/#eyJjb2RlIjoiZ3JhcGggXG4gICAgR0NDW0dDQ10gLS0-IExEW2JpbnV0aWxzXVxuICAgIEdDQyAtLT58Q2lyY3VsYXIgZGVwLnwgQ1tDIExpYnJhcnldXG4gICAgQyAtLT4gR0NDXG4gICAgQyAtLT4gS1tMaW51eCBrZXJuZWwgaGVhZGVyc11cbiAgIiwibWVybWFpZCI6IntcbiAgXCJ0aGVtZVwiOiBcImRhcmtcIlxufSIsInVwZGF0ZUVkaXRvciI6ZmFsc2UsImF1dG9TeW5jIjp0cnVlLCJ1cGRhdGVEaWFncmFtIjpmYWxzZX0)

How do we escape this? Thankfully, by passing certain options to the GCC
build system, it is possible to eliminate the reliance on the target
glibc, and thus build GCC _before_ glibc. The price we pay for this is
that the compiler produced this way is not complete: it cannot be used
to build hosted C or C++ code (since GCC's C++ standard library depends
on the target C library, and regular C apps expect a working C library
as well) and `libgcc`, an internal component of GCC which is linked to
pretty _anything_ GCC builds and provides some low-level services, lacks
certain features.  This reduced compiler, called the _bootstrap
compiler_, can however be used to build C code that does not depend on
the missing features and that does not require a C library in place.
Fortunately, glibc fits this scenario.

Therefore, we can break free by first building a bootstrap compiler,
using it to compile glibc, then _recompiling GCC again_, this time by
telling it that a target C library is available, thus building the full
thing. This second GCC build is called the _final compiler_, and is what
will become part of our toolchain. The bootstrap compiler will be thrown
away as soon as the final compiler is ready. Here the dependency graph,
updated:

[![](https://mermaid.ink/img/eyJjb2RlIjoiZ3JhcGggXG4gICAgYkdDQ1tCb290c3RyYXAgR0NDXSAtLT4gTERbYmludXRpbHNdXG4gICAgR0NDIC0tPiBDW0MgTGlicmFyeV1cbiAgICBDIC0tPiBiR0NDXG4gICAgR0NDIC0tPiBMRFxuICAgIEMgLS0-IEtbTGludXgga2VybmVsIGhlYWRlcnNdXG4gICIsIm1lcm1haWQiOnsidGhlbWUiOiJkYXJrIn0sInVwZGF0ZUVkaXRvciI6ZmFsc2UsImF1dG9TeW5jIjp0cnVlLCJ1cGRhdGVEaWFncmFtIjpmYWxzZX0)](https://mermaid.live/edit/#eyJjb2RlIjoiZ3JhcGggXG4gICAgYkdDQ1tCb290c3RyYXAgR0NDXSAtLT4gTERbYmludXRpbHNdXG4gICAgR0NDIC0tPiBDW0MgTGlicmFyeV1cbiAgICBDIC0tPiBiR0NDXG4gICAgR0NDIC0tPiBMRFxuICAgIEMgLS0-IEtbTGludXgga2VybmVsIGhlYWRlcnNdXG4gICIsIm1lcm1haWQiOiJ7XG4gIFwidGhlbWVcIjogXCJkYXJrXCJcbn0iLCJ1cGRhdGVFZGl0b3IiOmZhbHNlLCJhdXRvU3luYyI6dHJ1ZSwidXBkYXRlRGlhZ3JhbSI6ZmFsc2V9)

Building glibc with the bootstrap compiler does not impact its level of
completeness or optimization. From [LFS, Toolchain Technical
Notes][how-lfs]:

> Now, there is more about cross-compiling: the C language is not just a
> compiler, but also defines a standard library. In this book, the GNU C
> library, named glibc, is used. This library must be compiled for the
> lfs machine, that is, using the cross compiler cc1. But the compiler
> itself uses an internal library implementing complex instructions not
> available in the assembler instruction set. This internal library is
> named libgcc, and must be linked to the glibc library to be fully
> functional! Furthermore, the standard library for C++ (libstdc++) also
> needs being linked to glibc. The solution to this chicken and egg
> problem is to first build a degraded cc1 based libgcc, lacking some
> functionalities such as threads and exception handling, then build
> glibc using this degraded compiler **(glibc itself is not degraded)**, then
> build libstdc++. But this last library will lack the same
> functionalities as libgcc. 

Our final build order therefore is:

1. binutils;
2. bootstrap GCC;
3. Linux kernel headers;
4. glibc;
5. final GCC.

## Build the binutils

Let's start with the first package.

```bash
cd $CROSSDIR/mytoolchain/sources/binutils
tar -xf binutils-2.37.tar.xz
mkdir -p build
cd build

../binutils-2.37/configure --prefix='' --enable-initfini-array \
  --with-sysroot='${exec_prefix}/sysroot' --target="$TARGET_TRIPLET" 
```

First, we extract the sources and then create a `build` directory where
the build system will create the binaries. Often, when building from a
tarball, we can run the `configure` script directly from the sources
folder, doing what is called an _in-tree_ build, with object files being
placed alongside the sources. The GNU build system also supports
_out-of-tree_ builds, where basically we execute `configure && make` from
a different folder than the one holding the sources. However, depending
on the package, doing an out-of-tree build can be either recommended or
mandatory, and notably GCC falls in this category. As GCC docs say:

> First, we highly recommend that GCC be built into a separate directory
> from the sources which does not reside within the source tree. This is
> how we generally build GCC; building where srcdir == objdir should
> still work, but doesn’t get extensive testing; building where objdir
> is a subdirectory of srcdir is unsupported. 

Since there should be no negative effects in doing an out-of-tree build
even when there is no explicit requirement to do so, I opted to build
every package this way. The `build` folder is a sibling of the sources
folder.

Now, let's break down the `configure` options and the reasons behind them.

`--prefix=''` determines the usual installation prefix that all
autotools-based builds expect. It serves two main purposes:
* it defines the path under which `make install` will place the newly
  built files (although we can add a prefix to that path using the
  `DESTDIR` variable);
* it can be hardcoded into applications so that they know where to look
  for related components.

The second point can be problematic because it means that, once built,
an app will expect to be installed under a specific path and therefore
it cannot be moved elsewhere on the filesystem, because it will still
look for its bits and pieces under the original path.

Thankfully, binutils (but also GCC) developers have gone through lengths
to ensure that we can build _relocatable_ toolchains. A program is
relocatable if it does not depend on its installation prefix, but
instead locate its parts by obtaining the absolute path to its own
executable and them moving from there using relative paths.

`ld` uses the following technique (implemented in
`binutils-2.37/libiberty/make-relative-prefix.c`):
* it takes the name of the executable as passed to the command
  invocation (its `argv[0]`);
* if it's just a program name (i.e. `ld`), it looks for it in the `PATH`
  to get the full path;
* if it's a relative path, it resolves it to the full path using the
  current working directory;
* otherwise it's used verbatim;
* resolve links to get the pathname of the real executable. This is
  essential to reach the real place where the app is placed, even if the
  program is called through a link.

If an applications is relocatable, the prefix is not that important
anymore. However, when running `make install DESTDIR="$DESTDIR"`, it is
still used to compute paths, so that things gets installed under
`$DESTDIR/$PREFIX` An empty prefix ('') (which I copied from the configuration
switches used for the official [ARM toolchain][arm-toolchains]) means
that no prefix at all is used and files would be placed under `$DESTDIR/bin`,
`$DESTDIR/lib ` and so on.

Now, to `with-sysroot`. A _sysroot_ is a prefix under which a toolchain
program (`ld` in this case, but it also applies to `gcc`) expects to be
able to find include files and libraries for the target, in our case,
for ARM.  This is where we will install things, like the C library,
which pertain to the target.

For the linker to know where the sysroot is, we have two options:

* we can pass the `--sysroot="/path/to/sysroot"` option to every `ld`
  invocation. This must also include any calls made to `ld` by other
  tools higher in the toolchain and is easy to forget about;
* we can specify the default sysroot at build time and have `ld`
  remember it. It can always be overridden on a per-call basis using
  `--sysroot`, but at least the default behavior will be sane even
  without it. This is what `--with-sysroot` does.

Forgetting to pass `--with-sysroot` when building _and_ also forgetting
to use `--sysroot` when calling the cross-linker will cause it to search
for target libraries under default paths _on the host_, like `/usr/lib/`.
This is not what we want as libraries there are compiled for the host
architecture.

We can pass `--with-sysroot` any path, but the binutils support a
special case that is essential to make the toolchain relocatable: if the
sysroot is located under the `exec-prefix` for the build (which defaults
to `prefix`if not overridden), `ld` will automatically compute its path
using the executable path. This means that effectively the sysroot moves
along with the rest of the toolchain. Without this behaviour, we would
end up with a toolchain that is not actually relocatable, because it
would search for libraries under a fixed sysroot path.

The build system accepts various forms for the sysroot path for it to be
considered _under the exec-prefix_ and thus relocatable, which can be
found by looking at `binutils-2.37/ld/configure` (an excerpt follows):

```bash
# Check whether --with-sysroot was given.
if test "${with_sysroot+set}" = set; then :
  withval=$with_sysroot;
 case ${with_sysroot} in
 yes) TARGET_SYSTEM_ROOT='${exec_prefix}/${target_alias}/sys-root' ;;
 *) TARGET_SYSTEM_ROOT=$with_sysroot ;;
 esac

 TARGET_SYSTEM_ROOT_DEFINE='-DTARGET_SYSTEM_ROOT=\"$(TARGET_SYSTEM_ROOT)\"'
 use_sysroot=yes

 if test "x$prefix" = xNONE; then
  test_prefix=/usr/local
 else
  test_prefix=$prefix
 fi
 if test "x$exec_prefix" = xNONE; then
  test_exec_prefix=$test_prefix
 else
  test_exec_prefix=$exec_prefix
 fi
 case ${TARGET_SYSTEM_ROOT} in
# <====== These are the interesting lines
 "${test_prefix}"|"${test_prefix}/"*|\
 "${test_exec_prefix}"|"${test_exec_prefix}/"*|\
 '${prefix}'|'${prefix}/'*|\
 '${exec_prefix}'|'${exec_prefix}/'*)
# <====== End
   t="$TARGET_SYSTEM_ROOT_DEFINE -DTARGET_SYSTEM_ROOT_RELOCATABLE"
   TARGET_SYSTEM_ROOT_DEFINE="$t"
   ;;
 esac

else

 use_sysroot=no
 TARGET_SYSTEM_ROOT=
 TARGET_SYSTEM_ROOT_DEFINE='-DTARGET_SYSTEM_ROOT=\"\"'

fi
```

I chose to use the form that starts with the literal `${exec_prefix}`.
The sysroot will be placed under the `sysroot` folder under the
exec-prefix and thus will be relocated with the rest of the tools.

`--target="$TARGET_TRIPLET"` is simple: it specifies the _machine
triplet_ that defines the target system. We have specified it in an
environment variable in our `activate.bash` file while setting up the
environment. [LFS][how-lfs] explains triplets, as well as [this OSDev
page][osdev-triplets]. Please note that "triplets" can actually have
four fields, like in our case.

Finally, `--enable-initfini-array` tells the binutils to enable support
for a feature of the target system binary file format
([ELF][elf-format]) that cannot be detected automatically when
cross-compiling.

Now it's time tun run make:

```bash
make -j`nproc`
```

After many lines of output you should be back to the terminal, hopefully
without errors. Double check that the sysroot was detected as
relocatable by checking the contents of `ld/Makefile`:

```bash
grep TARGET_SYSTEM_ROOT_RELOCATABLE ld/Makefile | head -n1

# You should see something like:
# TARGET_SYSTEM_ROOT_DEFINE = -DTARGET_SYSTEM_ROOT=\"$(TARGET_SYSTEM_ROOT)\" -DTARGET_SYSTEM_ROOT_RELOCATABLE
```

If there's no output, check the call to `configure`. As things are, the
sysroot will not move together with the rest of the toolchain.

If everything is fine, let's install binutils:

```bash
make install DESTDIR="$TOOLS"
```

## Build the bootstrap compiler

Now it's time to build the bootstrap compiler.

GCC requires some additional libraries, which are listed in its
[prerequisites page][gcc-prereq]. We will use the versions that ship
with Arch Linux, as they are recent enough.

```bash
sudo pacman -S --noconfirm --needed libmpc mpfr gmp
(
  cd /tmp
  curl -L https://aur.archlinux.org/cgit/aur.git/snapshot/isl.tar.gz | tar -xzf -
  cd isl
  makepkg -si
)
```

Unpack and configure GCC:

```bash
cd $CROSSDIR/mytoolchain/sources/gcc
tar -xf gcc-11.2.0.tar.xz
mv gcc-11.2.0{,-bootstrap}
mkdir -p build-bootstrap
cd build-bootstrap

../gcc-11.2.0-bootstrap/configure \
  --prefix='' \
  --with-sysroot='${exec_prefix}/sysroot' \
  --target="$TARGET_TRIPLET" \
  --enable-initfini-array \
  --enable-languages=c \
  --without-headers \
  --with-newlib \
  --disable-gcov \
  --disable-threads \
  --disable-shared \
  --disable-libada \
  --disable-libssp \
  --disable-libquadmath \
  --disable-libgomp \
  --disable-libatomic \
  --disable-libstdcxx \
  --disable-libvtv
```

`--prefix` and `--with-sysroot` have the same meanings and implications
as for binutils, so we won't repeat them here. It's important to use the
same values used for binutils, otherwise the two sets of tools will have
different ideas about were to install things when `make install` is
called and will look for libraries in different places.  `--target` and
`--enable-initfini-array` also work the same as before.

`--enable-languages` is new and tells GCC which languages should be
supported. Remember that GCC means "GNU Compiler Collection", because it
supports more than just C and C++. However, the bootstrap compiler will
only ever be used to build glibc, which is written in C, so there's no
reason to enable more languages for now.

`--without-headers` and `--with-newlib` are the two options that make
the magic of disabling GCC's reliance on a preexisting target C library.
If we look inside `gcc-11.2.0/gcc/configure`:

```bash
# If this is a cross-compiler that does not
# have its own set of headers then define
# inhibit_libc

# If this is using newlib, without having the headers available now,
# then define inhibit_libc in LIBGCC2_CFLAGS.
# This prevents libgcc2 from containing any code which requires libc
# support.
: ${inhibit_libc=false}
if { { test x$host != x$target && test "x$with_sysroot" = x ; } ||
       test x$with_newlib = xyes ; } &&
     { test "x$with_headers" = xno || test ! -f "$target_header_dir/stdio.h"; } ; then
       inhibit_libc=true
fi
```

Note that we are _not_ going to use the _newlib_ C library: we'll stick
to glibc. But the option is still required to eliminate dependencies on
the (yet to be built) C library.

Finally, the various `--disable-*` options turn off features we don't
want (or can't) build yet.

Now start the build:

```bash
make -j`nproc` all-gcc all-target-libgcc
```

`all-gcc` and `all-target-libgcc` are Makefile targets. They need to be
specified so that only the parts of GCC we actually need are built,
cutting the build time.


This time, we will not install the compiler under `$TOOLS`, but in a
separate `bootstrap` directory. Since this is going to be thrown away as
soon as the final compiler is build, we don't want to risk polluting the
final location with leftovers.

However, under `bootstrap` there is no `sysroot` folder: creating
a symlink to the one under `tools` gives the bootstrap compiler the
same view of the sysroot as the binutils. At the same time, we want to
create `sysroot` under `$TOOLS`, since we haven't done it already and no
files has been placed there by a `make install`. Finally, we also need
to create a link `$TARGET_TRIPLET` under `bootstrap`, pointing to
the folder where the binutils are installed. This is
[required][gcc-build] by GCC to properly locate the assembler and the
linker:

> If you are not building GNU binutils in the same source tree as GCC, you
> will need a cross-assembler and cross-linker installed before
> configuring GCC. Put them in the directory prefix/target/bin.

```bash
mkdir -p "$SYSROOT"
mkdir -p "$TOOLS/../bootstrap"
ln -sf "$SYSROOT" "$TOOLS/../bootstrap/sysroot"
ln -sf "$TOOLS/$TARGET_TRIPLET" "$TOOLS/../bootstrap/$TARGET_TRIPLET"
```

Now install the files:

```bash
make install-gcc install-target-libgcc DESTDIR="$TOOLS/../bootstrap"
```

Confirm that the bootstrap compiler recognizes the sysroot:

```bash
$TOOLS/../bootstrap/bin/arm-none-linux-gnueabihf-gcc -print-sysroot

# It should output something like:
# /home/manu/projects/embedded/mytoolchain/bootstrap/bin/../sysroot
```

Now we are ready to move to building glibc. But before that, we need to
extract the kernel headers.

## Extract the kernel headers

First we need to ensure we have rsync installed, as it is used by the
build system to copy things:

```bash
sudo pacman -S --noconfirm --needed rsync
```

Then proceed:

```bash
cd $CROSSDIR/mytoolchain/sources/linux
tar -xf linux-5.15.7.tar.xz
cd linux-5.15.7

make mrproper
make headers_install INSTALL_HDR_PATH="$SYSROOT/usr"
```

This step is simpler that the others: there is not `build`
directory because with Linux we do things in-tree.

`make mrproper` ensures that the kernel tree is clean, without leftover
files from previous builds. Technically, we have just unpacked it so
there should be nothing to clean, but LFS recommends this step just in
case something has slipped through the packaging.

`make headers_install INSTALL_HDR_PATH="$SYSROOT/usr"` places the
headers under `$SYSROOT/usr/include` (the `include` is added
automatically). The kernel headers are the first thing placed under the
sysroot, as they belong to the target system, and according to the
[Filesystem Hierarchy Standard][fhs], system include files should go
under `/usr/include`.

The commands above don't show an important element: in order to
extract headers for the appropriate target architecture, the kernel
build system looks for an `ARCH` variable. We didn't explicitly pass
one, however, because it is already defined in our environment via
`activate.bash`. `ARCH` is a convention used by many tools (the kernel,
U-Boot, BusyBox among others) and by placing it in the environment we
can't forget it.

## Build glibc

Ensure your python is up to date, as glibc's build systems checks for
this:

```bash
sudo pacman -S --needed --noconfirm python
```

Unpack and configure:

```bash
cd $CROSSDIR/mytoolchain/sources/glibc
tar -xf glibc-2.34.tar.xz
mkdir -p build
cd build

(
  PATH="$TOOLS/../bootstrap/bin:$PATH"

  # Configure
  ../glibc-2.34/configure \
    --prefix=/usr \
    --host="$TARGET_TRIPLET" \
    --build="$HOST_TRIPLET" \
    --with-headers="$SYSROOT/usr/include" \
    --enable-kernel=3.2

  # Build
  make -j`nproc` CXX=''

  # Install
  make install DESTDIR="$SYSROOT" CXX=''
)
```

First, note that we are injecting a modified `PATH` into the
environment. This is required to find the bootstrap compiler, since the
`bootstrap/bin` folder is not in our default `PATH`.

Unlike previous components, glibc's prefix is `/usr`. Again, glibc is a
target library, so its expected installation path is under the
root filesystem of the target system, which is what it will see at
runtime.

`--host` and `--build` control the actual cross-compilation. There is no
`--target`, because glibc does not emit code for a platform, it _runs_
on a platform, the _host_, which needs to be set to the triplet of the
target ARM system. `--build`, conversely, specifies the system used for
the build, which is our current x86-64 machine.

`--with-headers` merely specifies where the kernel headers are to be
found. `--enable-kernel` defines the _lowest_ Linux kernel version that
this C library will support. The higher the version, the faster and
smaller the code becomes, because it does not need to cater to older
kernels and can drop compatibility stuff. But it also means that if you
ever try to run an application linked against this glibc on a system
whose running kernel is lower than `--enable-kernel`, all you get is an
abort. The value `3.2` is the lowest version still supported by glibc
2.34, which means we are compiling for the widest range of kernels, at
the expense of the largest compatibility bloat.

When doing `make` and `make install`, there's an extra `CXX=''`
variable. If you skim through the output of configure, you'll notice a
warning message saying that the cross-`g++` was found without a target
prefix. What is actually happening is that, since with didn't enable C++
for the bootstrap compiler, there is no `g++` under `bootstrap`, and the
build system ends up finding the `g++` that is installed on the host,
typically at `/usr/bin/g++`. Of course, this compiler cannot handle ARM
code. So when actually calling `make` we override this selection with an
empty value, causing some Makefile code to behave as if no C++ compiler
is installed. This is required to avoid the build phase trying to
compile a C++ file, `./glibc-2.34/support/links-dso-program.cc`,
which also has a C equivalent
`./glibc-2.34/support/links-dso-program-c.c` that will be used instead.

With glibc installed, the last step is to build the final GCC. Before
that, however, we can get rid of the bootstrap compiler, as its work is
over:

```bash
rm -rf "$TOOLS/../bootstrap"
```

## Build the final GCC

```bash
cd $CROSSDIR/mytoolchain/sources/gcc
tar -xf gcc-11.2.0.tar.xz
mv gcc-11.2.0{,-final}
mkdir -p build-final
cd build-final

../gcc-11.2.0-final/configure \
  --prefix='' \
  --target="$TARGET_TRIPLET" \
  --with-sysroot='${exec_prefix}/sysroot' \
  --with-build-sysroot="$SYSROOT" \
  --enable-languages=c,c++ \
  --enable-initfini-array
```

Most options should be familiar by now. This time we also enable C++
support and the `--disable-*` options are gone as we want to build the
full thing. The only new stuff is `--with-build-sysroot`, which points
to the full path of our sysroot. As per the docs, a build sysroot works
just like a sysroot, but it is only used while building GCC itself, it
is _not_ remembered by the final cross-compiler. The reason we need this
is allowing the build system to properly find include files and
libraries under the sysroot even if the value of `--with-sysroot` does
not make sense during the build.  Without this option, the build will
fail with errors claiming that header files cannot be found under
`/sysroot/usr/include`. GCC is smart enough to compute the absolute path
to the sysroot using its own executable path, but the build system is
not.

Now build and install:

```bash
make -j`nproc`
make install DESTDIR="$TOOLS"
```

Congrats! This was the last step. Now let's try out the cross compiler.

## Test the cross-toolchain

To test the cross toolchain, we'll build a totally nonsensical C++ app
that calls both some C and C++ functions and uses exceptions to simply
print a string, basically to exert C, C++ features and stack unwinding.
Then we'll use qemu to see if it runs.

Install qemu for ARM:

```bash
sudo pacman -S --needed --noconfirm qemu-arch-extra
```

Place the following code into a `test.cc` file:

```c++
#include <stdio.h>
#include <unistd.h>
#include <sys/utsname.h>
#include <iostream>
#include <stdexcept>

// A couple of functions
void func1() {
  throw std::runtime_error("Hello crossworld");
}

void func() {
  try {
    func1();
  } catch (...) {
    printf("%s\n", "Hello crossworld from C");
    throw;
  }
}

int main() {
  for (size_t i {0}; i < 5; i++) {
    try {
      func();
    } catch (const std::runtime_error &e) {
      std::cout << e.what() << " from C++ too!" << std::endl;
    }
    sleep(1);
  }
  struct utsname un;
  if (!uname(&un)) {
    std::cout << "This little show was hosted by " << un.machine << std::endl;
  }
  return 0;
}
```

Build the code and run it:

```bash
# Dynamically linked build
arm-none-linux-gnueabihf-g++ -o test test.cc

qemu-arm -L "$SYSROOT" -E LD_LIBRARY_PATH="$TOOLS/$TARGET_TRIPLET/lib" ./test

# You should see:
#
# Hello crossworld from C
# Hello crossworld from C++ too!
# Hello crossworld from C
# Hello crossworld from C++ too!
# Hello crossworld from C
# Hello crossworld from C++ too!
# Hello crossworld from C
# Hello crossworld from C++ too!
# Hello crossworld from C
# Hello crossworld from C++ too!
# This little show was hosted by armv7l

# Same code, static build
arm-none-linux-gnueabihf-g++ -static -o test test.cc

qemu-arm ./test
# Same output as above
```

`-L` tells qemu where to find the dynamic linker for the ARM platform,
while `-E` adds an `LD_LIBRARY_PATH` to the environment of our new
process, which the dynamic linker can use to locate the standard C++
library (without that you'd get an error about loading `libstdc++.so.6`).
Such switches are not needed for the static build.

<!-- Links -->
[arm-toolchains]: https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-a/downloads
[binutils]: https://www.gnu.org/software/binutils/
[bootlin-toolchains]: https://toolchains.bootlin.com/
[buildroot]: https://buildroot.org/
[clfs]: https://trac.clfs.org/wiki/read
[crosstool-ng]: https://crosstool-ng.github.io/
[elf-format]: http://www.sco.com/developers/gabi/latest/ch4.intro.html
[fhs]: https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard
[gcc-build]: https://gcc.gnu.org/install/build.html
[gcc]: https://gcc.gnu.org/ 
[gcc-prereq]: https://gcc.gnu.org/install/prerequisites.html
[glibc]: https://www.gnu.org/software/libc/
[how-crosstool-ng]: https://crosstool-ng.github.io/docs/toolchain-construction/
[how-lfs]: https://www.linuxfromscratch.org/lfs/view/stable/partintro/toolchaintechnotes.html
[lfs-envsetup]: https://www.linuxfromscratch.org/lfs/view/stable/chapter04/settingenvironment.html
[linux]: https://www.kernel.org/
[osdev-triplets]: https://wiki.osdev.org/Target_Triplet
[usrmerge]: https://www.freedesktop.org/wiki/Software/systemd/TheCaseForTheUsrMerge/
