# TODO do not use latest
FROM ghcr.io/openvadl/lcb-test-base@sha256:0c91110246c88996b69bdffae4510f86959fabf57ebda51662a04a23b8b86aae as lcb-base

FROM ubuntu:26.04

EXPOSE 10240
EXPOSE 1234

#
# install dependencies / qol tools
#
# riscv64-...-gdb needs libpython3.10
RUN apt update --assume-yes && \
  apt install --assume-yes software-properties-common && \
  add-apt-repository ppa:deadsnakes/ppa && \
  apt update --assume-yes && \
  apt install --assume-yes \
    build-essential \
    make \
    cmake \
    ninja-build \
    clang \
    ccache \
    libpython3.10 \
    libglib2.0-0 \
    libfmt-dev \
    libc++-dev \
    libc++abi-dev \
    libpixman-1-0 \
    libfdt1 \
    python3 \
    openjdk-25-jdk \
    rsync \
    curl \
    git \
    tmux \
    neovim


#
# copy toolchain over
#
COPY --from=lcb-base /opt/sccache /opt/sccache
COPY --from=lcb-base /opt/qemu /opt/qemu
COPY --from=lcb-base /opt/riscv /opt/riscv
COPY --from=lcb-base /opt/aarch64-linux /opt/aarch64-linux
COPY --from=lcb-base /opt/aarch64-elf /opt/aarch64-elf
ENV PATH=/opt/aarch64-elf/bin:$PATH
ENV PATH=/opt/aarch64-linux/bin:$PATH
ENV PATH=/opt/riscv/bin:$PATH
ENV PATH=/opt/qemu/bin:$PATH

#
# setup sccache
#
ENV PATH=/opt/sccache:$PATH
ENV SCCACHE_DIR=/root/.cache/sccache
ENV SCCACHE_CACHE_SIZE=10G

#
# install nvm / node / compiler explorer
#
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
RUN git clone https://github.com/compiler-explorer/compiler-explorer compiler-explorer
WORKDIR /compiler-explorer
RUN . "/root/.nvm/nvm.sh" && nvm install 22.23.1 && make prebuild
# copy c compiler config
COPY compiler-explorer/c.local.properties /compiler-explorer/etc/config/c.local.properties
WORKDIR /

# too invasive, is added on every clang invocation => config
# 
# setup default flags for clang
#
# riscv
# ENV CCC_OVERRIDE_OPTIONS="^--sysroot=/opt/riscv/riscv64-unknown-elf"
# aarch64
# ENV CCC_OVERRIDE_OPTIONS="$CCC_OVERRIDE_OPTIONS ^-isystem/opt/aarch64-linux/aarch64-none-linux-gnu/libc/usr/include/ ^--sysroot=/opt/aarch64-linux/aarch64-none-linux-gnu/"


#
# set up bashrc with helpers
#
RUN mkdir /root/bash-extras
COPY bash-extras /root/bash-extras
RUN echo 'source /root/bash-extras/banner.sh' >> /root/.bashrc

COPY scripts /usr/local/bin
CMD /usr/local/bin/init.sh && bash
