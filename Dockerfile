# TODO do not use latest
FROM ghcr.io/openvadl/lcb-test-base@sha256:0c91110246c88996b69bdffae4510f86959fabf57ebda51662a04a23b8b86aae as lcb-base

FROM ubuntu:26.04

EXPOSE 10240
EXPOSE 1234

#
# install dependencies / qol tools
#
RUN apt update --assume-yes && \
  apt install --assume-yes \
    tmux \
    neovim \
    rsync \
    curl \
    libglib2.0-0 \
    build-essential \
    make \
    cmake \
    ninja-build \
    python3 \
    git \
    libfmt-dev \
    libc++-dev \
    libc++abi-dev \
    clang

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
# set up bashrc with helpers
#
COPY bash_extras /root/
RUN echo 'source /root/bash_extras/banner.sh' >> /root/.bashrc
RUN echo 'source /root/bash_extras/clang-flags.sh' >> /root/.bashrc
RUN echo 'source /root/bash_extras/alias.sh' >> /root/.bashrc

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
