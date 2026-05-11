# ============================================
# Stage 1: Download CCS Installer
# ============================================
FROM ubuntu:22.04 AS downloader

# CCS Version (can be overridden at build time)
ARG CCS_VERSION=20.5.0.00028

# Parse version components
ARG MAJOR_VER=20
ARG MINOR_VER=5
ARG PATCH_VER=0
ARG BUILD_VER=00028

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
# Comprehensive dependency installation for CCS v7-v20 support
# Ref: https://software-dl.ti.com/ccs/esd/documents/ccsv{7,8,9,10,11,12}_linux_host_support.html
RUN echo ">>> Installing system dependencies..." && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    # Apply security updates
    apt-get upgrade -y && \
    # Install CCS runtime dependencies
    apt-get install --no-install-recommends -y \
    # 32-bit libraries (required by all CCS versions)
    libc6:i386 \
    libc6-i386 \
    libusb-0.1-4:i386 \
    libusb-0.1-4 \
    libgconf-2-4:i386 \
    libgconf-2-4 \
    libncurses5:i386 \
    libncurses5 \
    libtinfo5:i386 \
    libtinfo5 \
    # Core system libraries
    libudev1 \
    libasound2 \
    libatk1.0-0 \
    libcairo2 \
    libgtk-3-0 \
    libgtk2.0-0 \
    libxi6 \
    libxtst6 \
    libxrender1 \
    libxt6 \
    # USB and device support
    libusb-1.0-0-dev \
    # GNOME/GTK dependencies
    libdbus-glib-1-2 \
    libcanberra0 \
    # Python 2.7 libraries (required by v9-v12)
    libpython2.7 \
    # v7-v8 specific packages
    binutils \
    libxss1 \
    # Utilities
    ca-certificates \
    unzip && \
    # Cleanup to reduce image size
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo ">>> Done."

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
