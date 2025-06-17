# Base Image
FROM ubuntu:22.04

# Code Composer Studio URL
ARG CCS_URL="https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-J1VdearkvK/"

# Code Composer Studio Version Variables
# <Major Version> . <Minor Version> . <Patch Version> . <Build Version>
# As of the last update to this project, the latest version of Code Composer Studio is "20.2.0.00012"
ENV MAJOR_VER=20
ENV MINOR_VER=2
ENV PATCH_VER=0
ENV BUILD_VER=00012

# Installable Product families Variables
ENV COMPONENTS=PF_C28

# Adding support for i386 architecture
RUN dpkg --add-architecture i386

# Update package lists and upgrade packages
RUN apt-get update && \
    apt-get upgrade -y

# Install essential packages
RUN apt-get install --no-install-recommends -y \
    libc6:i386 \
    libusb-0.1-4:i386 \
    libgconf-2-4:i386 \
    libncurses5:i386 \
    libtinfo5:i386 \
    libpython2.7 \
    build-essential \
    unzip \
    wget

# Clear APT cache to reduce image size
RUN apt-get clean && rm -rf /var/lib/apt/lists/*s

# Set working directory for CCS installation
WORKDIR /ccs_install

# Download and extract CCS installation package
# For versions 20 and above
RUN if [ "$MAJOR_VER" -ge 20 ]; then \
    wget --no-check-certificate ${CCS_URL}${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}/CCS_${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux.zip && \
    unzip CCS_${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux.zip && \
    chmod -R 755 CCS_${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux; \
    fi

# For versions equal to 12
RUN if [ "$MAJOR_VER" -eq 12 ]; then \
    wget --no-check-certificate ${CCS_URL}${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}/CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64.tar.gz && \
    tar -zxvf CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64.tar.gz && \
    chmod -R 755 CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64; \
    fi

# For versions below 12
RUN if [ "$MAJOR_VER" -lt 12 ]; then \
    wget --no-check-certificate ${CCS_URL}${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}/CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64.tar.gz && \
    tar -zxvf CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64.tar.gz && \
    chmod -R 755 CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64; \
    fi

# Install CCS
# For versions 20 and above
RUN if [ "$MAJOR_VER" -ge 20 ]; then \
    cd CCS_${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux && \
    chmod +x ccs_setup_${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}.run && \
    ./ccs_setup_${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}.run --mode unattended --enable-components ${COMPONENTS} --prefix /opt/ti || true && \
    cd ..; \
    fi

# For versions below 20
RUN if [ "$MAJOR_VER" -lt 20 ]; then \
    ./CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64/ccs_setup_${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}.run --mode unattended --enable-components ${COMPONENTS} --prefix /opt/ti --install-BlackHawk false --install-Segger false; \
    fi

# Clean up installation directoryAdd commentMore actions
RUN rm -r /ccs_install

# Set working directory to home
WORKDIR /home

# Update PATH environment variable
ENV PATH="/opt/ti/ccs/eclipse/:${PATH}"