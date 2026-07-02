FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG LOCAL_UID=1000
ARG LOCAL_GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
    asciidoc \
    bash \
    bc \
    binutils \
    bison \
    build-essential \
    bzip2 \
    ca-certificates \
    ccache \
    clang \
    cmake \
    cpio \
    curl \
    file \
    flex \
    g++ \
    g++-multilib \
    gawk \
    gcc-multilib \
    gettext \
    git \
    help2man \
    intltool \
    libelf-dev \
    libglib2.0-dev \
    libncurses-dev \
    libssl-dev \
    libtool \
    libzstd-dev \
    make \
    nano \
    ninja-build \
    patch \
    perl \
    pkg-config \
    procps \
    python3 \
    python3-dev \
    python3-pip \
    python3-ply \
    python3-setuptools \
    quilt \
    rsync \
    subversion \
    swig \
    texinfo \
    time \
    unzip \
    wget \
    xxd \
    xz-utils \
    zlib1g-dev \
    zstd \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${LOCAL_GID}" builder \
    && useradd --uid "${LOCAL_UID}" --gid "${LOCAL_GID}" --create-home --shell /bin/bash builder

USER builder
WORKDIR /workspace

ENV FORCE_UNSAFE_CONFIGURE=1 \
    USE_CCACHE=1 \
    CCACHE_DIR=/workspace/ccache \
    CCACHE_BASEDIR=/workspace/source

CMD ["/bin/bash"]
