# TODO do not use latest
FROM ghcr.io/openvadl/lcb-test-base@sha256:0c91110246c88996b69bdffae4510f86959fabf57ebda51662a04a23b8b86aae as lcb-base

FROM ubuntu:26.04

EXPOSE 10240
EXPOSE 1234


RUN apt update --assume-yes && \
  apt install --assume-yes \
    neovim \
    rsync \
    curl \
    libglib2.0-0 \
    build-essential \
    make \
    cmake \
    ninja-build \
    ccache \
    python3 \
    git \
    libfmt-dev \
    libc++-dev \
    libc++abi-dev \
    clang \
    lldb

#
# copy toolchain over
#
COPY --from=lcb-base /opt/sccache /opt/sccache
COPY --from=lcb-base /opt/qemu /opt/qemu
COPY --from=lcb-base /opt/riscv /opt/riscv
COPY --from=lcb-base /opt/aarch64-linux /opt/aarch64-linux
COPY --from=lcb-base /opt/aarch64-elf /opt/aarch64-elf

#
# setup sccache
#
ENV PATH=/opt/sccache:$PATH
ENV SCCACHE_DIR=/root/.cache/sccache
ENV SCCACHE_CACHE_SIZE=10G

#
# set up default flags for clang
#
COPY bash_extras /root/.bash_extras
RUN echo 'source /root/.bash_extras' >> /root/.bashrc

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

COPY ./scripts /scripts

CMD bash /scripts/init.sh && bash
