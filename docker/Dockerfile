# Saiyan Trainer - BizHawk Container Image
# Packages BizHawk 2.11 with Xvfb, x11vnc, noVNC, and s6-overlay
# for headless NEAT training with optional browser-based observation.
#
# Usage:
#   docker build -t saiyan-trainer/bizhawk:latest .
#   docker run --rm --shm-size=256m \
#     -e ENABLE_VNC=true -p 6080:6080 \
#     -v $(pwd)/roms:/data/roms:ro \
#     -v $(pwd)/savestates:/data/savestates:ro \
#     -v $(pwd)/lua:/data/lua:ro \
#     -v $(pwd)/output:/data/output \
#     saiyan-trainer/bizhawk:latest

FROM debian:bookworm-slim

ARG S6_OVERLAY_VERSION=3.1.6.2
ARG BIZHAWK_VERSION=2.11

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    mono-complete \
    xvfb \
    x11vnc \
    fluxbox \
    libopenal-dev \
    lua5.4 liblua5.4-dev \
    lsb-release \
    mesa-utils libgtk2.0-0 libsdl2-2.0-0 \
    wget unzip git python3 xz-utils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install s6-overlay for multi-process supervision
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz \
    && rm /tmp/s6-overlay-*.tar.xz

# Install noVNC + websockify for browser-based VNC access
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /usr/share/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify.git /usr/share/novnc/utils/websockify \
    && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Download and install BizHawk
RUN mkdir -p /opt/bizhawk \
    && wget -q "https://github.com/TASEmulators/BizHawk/releases/download/${BIZHAWK_VERSION}/BizHawk-${BIZHAWK_VERSION}-linux-x64.tar.gz" \
       -O /tmp/bizhawk.tar.gz \
    && tar xzf /tmp/bizhawk.tar.gz -C /opt/bizhawk --strip-components=1 \
    && rm /tmp/bizhawk.tar.gz \
    && chmod +x /opt/bizhawk/EmuHawkMono.sh

# Create data directories for volume mounts
RUN mkdir -p /data/roms /data/savestates /data/output /data/lua

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
