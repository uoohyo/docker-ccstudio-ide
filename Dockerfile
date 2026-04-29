# Base Image
FROM ubuntu:22.04

# Default CCS Version
# Format: <Major>.<Minor>.<Patch>.<Build>
# v12 and below: Eclipse-based / v20 and above: Theia-based
# Override at runtime: docker run -e MAJOR_VER=20 -e MINOR_VER=5 ...
ENV MAJOR_VER=20
ENV MINOR_VER=5
ENV PATCH_VER=0
ENV BUILD_VER=00028

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
    unzip \
    wget \
    aria2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo ">>> Done."

# Working Directory
WORKDIR /home

# CCS CLI Path (v20+ default; v12 path is set dynamically in entrypoint.sh)
ENV PATH="/opt/ti/ccs/eclipse/:${PATH}"

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r//' /entrypoint.sh && chmod 755 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
