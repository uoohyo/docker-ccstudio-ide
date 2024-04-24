# Base Image
FROM ubuntu:22.04

# Code Composer Studio Version Variables
# <Major Version> . <Minor Version> . <Patch Version> . <Build Version>
# As of the last update to this project, the latest version of Code Composer Studio is "12.7.0.00007"
ENV MAJOR_VER 12
ENV MINOR_VER 7
ENV PATCH_VER 0
ENV BUILD_VER 00007

# Installable Product families Variables
ENV COMPONENTS PF_C28

# Adding support for i386 architecture
RUN dpkg --add-architecture i386

# Update package lists and upgrade packages
RUN apt-get update
RUN apt-get upgrade -y

# Install essential packages
RUN apt-get install -y libc6:i386
RUN apt-get install -y libusb-0.1-4:i386
RUN apt-get install -y libgconf-2-4:i386
RUN apt-get install -y libncurses5:i386
RUN apt-get install -y libtinfo5:i386
RUN apt-get install -y libpython2.7
RUN apt-get install -y build-essential
RUN apt-get install -y wget

# Clear APT cache to reduce image size
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory for CCS installation
WORKDIR /ccs_install

# Download and extract CCS installation package
RUN wget https://software-dl.ti.com/ccs/esd/CCSv${MAJOR_VER}/CCS_${MAJOR_VER}_${MINOR_VER}_${PATCH_VER}/exports/CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64.tar.gz
RUN tar -zxvf CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64.tar.gz

# Install CCS in unattended mode
RUN /ccs_install/CCS${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}_linux-x64/ccs_setup_${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}.run --mode unattended --enable-components ${COMPONENTS} --prefix /opt/ti --install-BlackHawk false --install-Segger false

# Clean up installation directory
RUN rm -r /ccs_install

# Set working directory to home
WORKDIR /home

# Update PATH environment variable
ENV PATH="/opt/ti/ccs/eclipse/:${PATH}"