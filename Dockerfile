# ============================================
# Global Build Arguments
# ============================================
# These must be declared before any FROM statement

# CCS Version (can be overridden at build time)
ARG CCS_VERSION=20.5.0.00028

# Parse version components
ARG MAJOR_VER=20
ARG MINOR_VER=5
ARG PATCH_VER=0
ARG BUILD_VER=00028

# Base image for runtime stage
# Automatically determined based on CCS major version:
# v7-v8:   Ubuntu 16.04 (BitRock installer compatibility)
# v9-v11:  Ubuntu 20.04 (officially tested)
# v12-v19: Ubuntu 22.04 (officially tested)
# v20+:    Ubuntu 24.04 (officially supported)
# Note: Can be overridden at build time with --build-arg BASE_IMAGE=...
ARG BASE_IMAGE=ubuntu:24.04

# ============================================
# Stage 1: Download CCS Installer
# ============================================
FROM ubuntu:24.04 AS downloader

# Re-declare args needed in this stage
ARG CCS_VERSION
ARG MAJOR_VER
ARG MINOR_VER
ARG PATCH_VER
ARG BUILD_VER

# Install download and extraction tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    aria2 \
    unzip \
    ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Download and extract CCS installer
RUN echo ">>> Downloading CCS ${CCS_VERSION}..." && \
    mkdir -p /ccs_download /ccs_installer && \
    cd /ccs_download && \
    CCS_URL="https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-J1VdearkvK/" && \
    if [ "${MAJOR_VER}" -ge 20 ]; then \
        aria2c -x 16 -s 16 \
            --file-allocation=none \
            --timeout=600 \
            --max-tries=5 \
            --retry-wait=3 \
            --console-log-level=notice \
            --summary-interval=10 \
            -o "CCS_${CCS_VERSION}_linux.zip" \
            "${CCS_URL}${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}/CCS_${CCS_VERSION}_linux.zip" && \
        echo ">>> Download complete: $(du -h CCS_${CCS_VERSION}_linux.zip | cut -f1)" && \
        echo ">>> Extracting installer..." && \
        unzip -q "CCS_${CCS_VERSION}_linux.zip" -d /ccs_installer && \
        chmod -R 755 "/ccs_installer/CCS_${CCS_VERSION}_linux" && \
        echo ">>> Extraction complete. Cleaning up archive..." && \
        rm -f "CCS_${CCS_VERSION}_linux.zip"; \
    else \
        if [ "${MAJOR_VER}" -ge 12 ]; then \
            CCS_DL_PATH="${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}"; \
        else \
            CCS_DL_PATH="${CCS_VERSION}"; \
        fi && \
        DOWNLOAD_URL="${CCS_URL}${CCS_DL_PATH}/CCS${CCS_VERSION}_linux-x64.tar.gz" && \
        echo ">>> Download URL: ${DOWNLOAD_URL}" && \
        aria2c -x 16 -s 16 \
            --file-allocation=none \
            --timeout=600 \
            --max-tries=5 \
            --retry-wait=3 \
            --console-log-level=notice \
            --summary-interval=10 \
            -o "CCS${CCS_VERSION}_linux-x64.tar.gz" \
            "${DOWNLOAD_URL}" && \
        echo ">>> Download complete: $(du -h CCS${CCS_VERSION}_linux-x64.tar.gz | cut -f1)" && \
        echo ">>> Extracting installer..." && \
        tar -zxf "CCS${CCS_VERSION}_linux-x64.tar.gz" -C /ccs_installer && \
        chmod -R 755 "/ccs_installer/CCS${CCS_VERSION}_linux-x64" && \
        echo ">>> Extraction complete. Cleaning up archive..." && \
        rm -f "CCS${CCS_VERSION}_linux-x64.tar.gz"; \
    fi

# ============================================
# Stage 2: Runtime Image
# ============================================
FROM ${BASE_IMAGE}

# Metadata
LABEL maintainer="uoohyo <https://github.com/uoohyo>"
LABEL description="TI Code Composer Studio IDE for Docker with pre-downloaded installer"

# Re-declare args needed in this stage
ARG CCS_VERSION
ARG MAJOR_VER
ARG MINOR_VER
ARG PATCH_VER
ARG BUILD_VER

ENV MAJOR_VER=${MAJOR_VER}
ENV MINOR_VER=${MINOR_VER}
ENV PATCH_VER=${PATCH_VER}
ENV BUILD_VER=${BUILD_VER}
ENV CCS_VERSION=${CCS_VERSION}

# Default Components
ENV COMPONENTS=PF_C28

# System Dependencies
# Version-aware dependency installation based on CCS version and base image
# Ref: https://software-dl.ti.com/ccs/esd/documents/ccsv{7,8,9,10,11,12}_linux_host_support.html
RUN echo ">>> Installing system dependencies for CCS v${MAJOR_VER}..." && \
    # Enable i386 architecture only for v7-v19 (32-bit libraries needed)
    if [ "${MAJOR_VER}" -le 19 ]; then \
        dpkg --add-architecture i386; \
    fi && \
    apt-get update && \
    apt-get upgrade -y && \
    \
    # ============================================
    # Common dependencies (ALL versions)
    # ============================================
    apt-get install --no-install-recommends -y \
    # USB/Debug probe support
    libusb-1.0-0-dev \
    # Core system libraries
    libudev1 \
    ca-certificates \
    unzip && \
    \
    # 32-bit USB libraries (v7-v19 only - for legacy debug probes)
    if [ "${MAJOR_VER}" -le 19 ]; then \
        apt-get install --no-install-recommends -y libusb-1.0-0:i386; \
    fi && \
    \
    # ============================================
    # Eclipse-specific dependencies (v7-v19 only)
    # ============================================
    if [ "${MAJOR_VER}" -le 19 ]; then \
        echo ">>> Installing Eclipse dependencies (v7-v19)..." && \
        apt-get install --no-install-recommends -y \
            libasound2 \
            libatk1.0-0 \
            libcairo2 \
            libgtk-3-0 \
            libxi6 \
            libxtst6 \
            libxrender1 \
            libxt6; \
    fi && \
    \
    # Old Ubuntu (16.04/18.04) packages for v7-v11
    if [ "${MAJOR_VER}" -le 11 ]; then \
        echo ">>> Installing legacy packages (v7-v11)..." && \
        (apt-get install --no-install-recommends -y \
            libusb-0.1-4:i386 \
            libusb-0.1-4 \
            libgconf-2-4:i386 \
            libgconf-2-4 \
            libncurses5:i386 \
            libncurses5 \
            libtinfo5:i386 \
            libtinfo5 || \
        apt-get install --no-install-recommends -y \
            libncurses6:i386 \
            libncurses6 \
            libtinfo6:i386 \
            libtinfo6); \
    fi && \
    \
    # ============================================
    # Version-specific dependencies
    # ============================================
    # v7-v8: Full 32-bit GUI stack for BitRock installer (Ubuntu 16.04 base required)
    # BitRock installer requires 32-bit GTK libraries (ref: sirde/ccs-v7-ci, commit bd35839)
    # Xvfb provides virtual display for headless Docker environment
    if [ "${MAJOR_VER}" -le 8 ]; then \
        echo ">>> Installing v7-v8 specific packages..." && \
        apt-get install --no-install-recommends -y \
            libc6:i386 \
            libpython2.7 \
            libgtk2.0-0 \
            libgtk2.0-0:i386 \
            libgtk-3-0:i386 \
            libcanberra-gtk-module:i386 \
            gtk2-engines-murrine:i386 \
            libgdk-pixbuf2.0-0:i386 \
            libx11-6:i386 \
            libstdc++6:i386 \
            libasound2:i386 \
            libatk1.0-0:i386 \
            libcairo2:i386 \
            libcups2:i386 \
            libgcrypt20:i386 \
            libice6:i386 \
            libsm6:i386 \
            libxt6:i386 \
            libxtst6:i386 \
            binutils \
            libxss1 \
            xvfb \
            x11-utils \
            libdbus-glib-1-2 \
            libcanberra0; \
    fi && \
    \
    # v9-v19: Eclipse-based IDE (requires GUI libraries, D-Bus)
    # Python 2.7 only for v9-v11 (removed from Ubuntu 22.04+)
    if [ "${MAJOR_VER}" -ge 9 ] && [ "${MAJOR_VER}" -le 19 ]; then \
        echo ">>> Installing v9-v19 Eclipse dependencies..." && \
        apt-get install --no-install-recommends -y \
            libdbus-glib-1-2 \
            libcanberra0; \
        if [ "${MAJOR_VER}" -le 11 ]; then \
            apt-get install --no-install-recommends -y libpython2.7 || true; \
        fi; \
    fi && \
    \
    # v9-v11: GTK 2.0 + libc6:i386 (TI official docs)
    if [ "${MAJOR_VER}" -ge 9 ] && [ "${MAJOR_VER}" -le 11 ]; then \
        echo ">>> Installing v9-v11 specific packages..." && \
        apt-get install --no-install-recommends -y \
            libc6:i386 \
            libgtk2.0-0; \
    fi && \
    \
    # v12-v19: libc6-i386 (package name changed in Ubuntu 20.04+)
    if [ "${MAJOR_VER}" -ge 12 ] && [ "${MAJOR_VER}" -le 19 ]; then \
        echo ">>> Installing v12-v19 specific packages..." && \
        apt-get install --no-install-recommends -y \
            libc6-i386; \
    fi && \
    \
    # v20+: Theia-based IDE (minimal dependencies, no Python/GTK)
    if [ "${MAJOR_VER}" -ge 20 ]; then \
        echo ">>> Installing v20+ specific packages..." && \
        apt-get install --no-install-recommends -y \
            libc6-i386; \
    fi && \
    \
    # Cleanup to reduce image size
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo ">>> Dependencies installed for CCS v${MAJOR_VER}"

# Copy pre-downloaded and extracted CCS installer from downloader stage
COPY --from=downloader /ccs_installer /opt/ccs-installer

# Working Directory
WORKDIR /home

# CCS CLI Path (v20+ default; older versions set dynamically in entrypoint.sh)
ENV PATH="/opt/ti/ccs/eclipse/:${PATH}"

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r//' /entrypoint.sh && chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
