# ============================================
# Stage 1: Download CCS Installer
# ============================================
FROM ubuntu:22.04 as downloader

# CCS Version (can be overridden at build time)
ARG CCS_VERSION=20.5.0.00028

# Parse version components
ARG MAJOR_VER=20
ARG MINOR_VER=5
ARG PATCH_VER=0
ARG BUILD_VER=00028

# Install download tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    aria2 \
    ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Download CCS installer
RUN echo ">>> Downloading CCS ${CCS_VERSION}..." && \
    mkdir -p /ccs_download && \
    cd /ccs_download && \
    CCS_URL="https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-J1VdearkvK/" && \
    if [ "${MAJOR_VER}" -ge 20 ]; then \
        aria2c -x 16 -s 16 \
            --file-allocation=none \
            --timeout=300 \
            --max-tries=3 \
            --console-log-level=error \
            --summary-interval=0 \
            -o "CCS_${CCS_VERSION}_linux.zip" \
            "${CCS_URL}${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}/CCS_${CCS_VERSION}_linux.zip" && \
        echo ">>> Download complete: $(du -h CCS_${CCS_VERSION}_linux.zip | cut -f1)"; \
    else \
        if [ "${MAJOR_VER}" -ge 12 ]; then \
            CCS_DL_PATH="${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}"; \
        else \
            CCS_DL_PATH="${CCS_VERSION}"; \
        fi && \
        aria2c -x 16 -s 16 \
            --file-allocation=none \
            --timeout=300 \
            --max-tries=3 \
            --console-log-level=error \
            --summary-interval=0 \
            -o "CCS${CCS_VERSION}_linux-x64.tar.gz" \
            "${CCS_URL}${CCS_DL_PATH}/CCS${CCS_VERSION}_linux-x64.tar.gz" && \
        echo ">>> Download complete: $(du -h CCS${CCS_VERSION}_linux-x64.tar.gz | cut -f1)"; \
    fi

# ============================================
# Stage 2: Runtime Image
# ============================================
FROM ubuntu:22.04

# Metadata
LABEL maintainer="uoohyo <https://github.com/uoohyo>"
LABEL description="TI Code Composer Studio IDE for Docker with pre-downloaded installer"

# CCS Version Environment Variables
ARG CCS_VERSION=20.5.0.00028
ARG MAJOR_VER=20
ARG MINOR_VER=5
ARG PATCH_VER=0
ARG BUILD_VER=00028

ENV MAJOR_VER=${MAJOR_VER}
ENV MINOR_VER=${MINOR_VER}
ENV PATCH_VER=${PATCH_VER}
ENV BUILD_VER=${BUILD_VER}
ENV CCS_VERSION=${CCS_VERSION}

# Default Components
ENV COMPONENTS=PF_C28

# System Dependencies
RUN echo ">>> Installing system dependencies..." && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
    libc6:i386 \
    libusb-0.1-4:i386 \
    libgconf-2-4:i386 \
    libncurses5:i386 \
    libtinfo5:i386 \
    libpython2.7 \
    libudev1 \
    libasound2 \
    libatk1.0-0 \
    libcairo2 \
    libgtk-3-0 \
    libxi6 \
    libxtst6 \
    libxrender1 \
    libusb-1.0-0-dev \
    libgconf-2-4 \
    libncurses5 \
    libtinfo5 \
    libusb-0.1-4 \
    libdbus-glib-1-2 \
    libgtk2.0-0 \
    libxt6 \
    libcanberra0 \
    ca-certificates \
    build-essential \
    unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo ">>> Done."

# Copy pre-downloaded CCS installer from downloader stage
COPY --from=downloader /ccs_download /opt/ccs-installer

# Working Directory
WORKDIR /home

# CCS CLI Path (v20+ default; older versions set dynamically in entrypoint.sh)
ENV PATH="/opt/ti/ccs/eclipse/:${PATH}"

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r//' /entrypoint.sh && chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
