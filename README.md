# OpenVADL LCB Development Container

This repository contains a Dockerfile for a personal development container, which is targeted at easing the development of the LCB and testing with embench.

The container provides 
- `ccb`: helper script to compile and link (individual or all) embench benchmarks, using the identical infrastructure as the associated embench CI/CD tests of openvadl
- `ccr`: helper script to run and debug embench benchmarks inside of qemu
- a preconfigured compiler-explorer instance
    - configurations for the locally built LCB are provided
    - --||-- for preconfigured invocations of clang, identical to embench's setup, are provided
    - TODO easier access to embench benchmarks (through `examples`)
- toolchains for aarch64 and riscv-32 / 64, which are in the PATH by default
- aliases for all LCB generated binaries, prefixed with `lcb-` (e.g. `lcb-clang` points to the locally compiled clang)
- clang config files for aarch64temp / riscv, which can be extended

## Getting started

The container relies on the openvadl repository being present at `/openvadl`. Therefore, it must be mounted on container startup. Furthemore, to speed up the repeated compilation of the LCB generated compiler, one should mount a docker-volume for sccache.

Finally, the container exposes ports `10240` and `1234` for compiler-explorer and qemu-remote debugging.

One can start the container as follows:
```
docker run -it --rm \
    -v lcb-dev-sccache:/root/.cache/sccache \
    -v <local path to openvadl>:/openvadl \
    -p 1234:1234 \
    -p 10240:10240 \
    lcb-dev:0.0.1
```

Inside container, following directory structure is available:

- /openvadl
    - locally mapped openvadl repository
- /src
    - symlink to the lcb output directory. Equivalent to openvadl's `output/lcb`, when generating the lcb.
- /embench
    - symlink to the embench directory
- /compiler-explorer


### Embench benchmark 

#### Compilation

```
ccb --help
```

#### Execution

```
ccr --help
```

### LCB 

Binaries, which are compiled from the lcb generated compiler (e.g. clang, llc, etc.) are symlinked with the prefix `lcb-` and in PATH. This allows easier access to the generated binaries, without having to specify the exact location:

```
lcb-clang --help
lcb-llc --help
...
```

### Compiler explorer

Compiler explorer is running on localhost:10240 on startup. Compilers are configured for

- the local LCB generated clang
- embench-riscv-{32,64} {lcb,clang} O{0,3} (total of 8 compilers)
    - these compilers mimic embench's invocation of the LCB / upstream compiler, duplicating the used flags
    - allows easier compilation of benchmark files with "the same setup as benchmark"

### Clang config files

`/root` contains clang config files for riscv and aarch64. The goal is to collect common flags, which are needed most of the time and ease the compilation of test programs:

```
lcb-clang --config ~/aarch64.cfg ...
```
