# Saiyan Trainer - mGBA Container Image
# Builds mGBA from source (Qt frontend for --script support), with
# Xvfb, x11vnc, noVNC, and s6-overlay for headless NEAT training
# with browser-based observation.
#
# Usage:
#   docker build -t saiyan-trainer/mgba:latest .
#   docker run --rm --shm-size=256m \
#     -e ENABLE_VNC=true -p 6080:6080 \
#     -v $(pwd)/roms:/data/roms:ro \
#     -v $(pwd)/savestates:/data/savestates:ro \
#     -v $(pwd)/lua:/data/lua:ro \
#     -v $(pwd)/output:/data/output \
#     saiyan-trainer/mgba:latest

FROM debian:bookworm-slim AS builder

# Build dependencies for mGBA with Qt frontend
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git ca-certificates \
    libsdl2-dev \
    qtbase5-dev qtmultimedia5-dev libqt5opengl5-dev qttools5-dev \
    liblua5.4-dev \
    libpng-dev zlib1g-dev \
    libsqlite3-dev libelf-dev \
    libfreetype-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Clone and build mGBA from master (--script flag requires post-0.10.5 code)
# WARNING: builds from master -- pin to a specific commit for production
ARG MGBA_VERSION=master
RUN git clone --depth 1 --branch ${MGBA_VERSION} \
        https://github.com/mgba-emu/mgba.git /tmp/mgba \
    && mkdir /tmp/mgba/build && cd /tmp/mgba/build \
    && cmake .. \
        -DCMAKE_INSTALL_PREFIX=/opt/mgba \
        -DBUILD_QT=ON \
        -DBUILD_SDL=OFF \
        -DUSE_SQLITE3=ON \
        -DUSE_LIBZIP=OFF \
        -DUSE_PNG=ON \
        -DUSE_LUA=ON \
        -DSKIP_GIT=ON \
    && make -j$(nproc) \
    && make install

# Clone noVNC + websockify in builder so git is not needed in the runtime image
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /usr/share/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify.git /usr/share/novnc/utils/websockify

# --- Runtime stage ---
FROM debian:bookworm-slim

ARG S6_OVERLAY_VERSION=3.1.6.2
ARG TARGETARCH

# Runtime dependencies for mGBA Qt + display stack
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsdl2-2.0-0 \
    libqt5widgets5 libqt5multimedia5 libqt5opengl5 libqt5gui5 \
    liblua5.4-0 \
    libpng16-16 zlib1g \
    libsqlite3-0 libelf1 \
    libfreetype6 \
    xvfb \
    x11vnc \
    fluxbox \
    mesa-utils libgl1-mesa-dri libegl1-mesa libgles2 \
    wget python3 xz-utils ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

# Copy built mGBA from builder
COPY --from=builder /opt/mgba /opt/mgba
ENV PATH="/opt/mgba/bin:${PATH}"

# Install s6-overlay for multi-process supervision
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN S6_ARCH=$(case "${TARGETARCH}" in arm64) echo "aarch64";; amd64) echo "x86_64";; *) echo "${TARGETARCH}";; esac) \
    && wget -q "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
       -O /tmp/s6-overlay-arch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz \
    && rm /tmp/s6-overlay-*.tar.xz

# Copy noVNC + websockify from builder (avoids git in runtime image, saves ~30MB)
COPY --from=builder /usr/share/novnc /usr/share/novnc
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Create data directories for volume mounts
RUN mkdir -p /data/roms /data/savestates /data/output /data/lua

# Bake save states into the image
COPY savestates/ /data/savestates/

# Copy s6-overlay service definitions
COPY rootfs/ /

# Copy utility scripts
COPY scripts/ /opt/scripts/

# Environment variables
ENV DISPLAY=:99 \
    ENABLE_VNC=true \
    VNC_PORT=5900 \
    NOVNC_PORT=6080 \
    XVFB_RESOLUTION=1024x768x24

EXPOSE 6080

ENTRYPOINT ["/init"]
