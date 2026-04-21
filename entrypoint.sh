#!/bin/bash
set -e

# Banner
cat << 'EOF'

$$$$$$$\                      $$\                                  $$$$$$\   $$$$$$\   $$$$$$\ $$$$$$$$\ $$\   $$\ $$$$$$$\  $$$$$$\  $$$$$$\        $$$$$$\ $$$$$$$\  $$$$$$$$\
$$  __$$\                     $$ |                                $$  __$$\ $$  __$$\ $$  __$$\\__$$  __|$$ |  $$ |$$  __$$\ \_$$  _|$$  __$$\       \_$$  _|$$  __$$\ $$  _____|
$$ |  $$ | $$$$$$\   $$$$$$$\ $$ |  $$\  $$$$$$\   $$$$$$\        $$ /  \__|$$ /  \__|$$ /  \__|  $$ |   $$ |  $$ |$$ |  $$ |  $$ |  $$ /  $$ |        $$ |  $$ |  $$ |$$ |
$$ |  $$ |$$  __$$\ $$  _____|$$ | $$  |$$  __$$\ $$  __$$\       $$ |      $$ |      \$$$$$$\    $$ |   $$ |  $$ |$$ |  $$ |  $$ |  $$ |  $$ |$$$$$$\ $$ |  $$ |  $$ |$$$$$\
$$ |  $$ |$$ /  $$ |$$ /      $$$$$$  / $$$$$$$$ |$$ |  \__|      $$ |      $$ |       \____$$\   $$ |   $$ |  $$ |$$ |  $$ |  $$ |  $$ |  $$ |\______|$$ |  $$ |  $$ |$$  __|
$$ |  $$ |$$ |  $$ |$$ |      $$  _$$<  $$   ____|$$ |            $$ |  $$\ $$ |  $$\ $$\   $$ |  $$ |   $$ |  $$ |$$ |  $$ |  $$ |  $$ |  $$ |        $$ |  $$ |  $$ |$$ |
$$$$$$$  |\$$$$$$  |\$$$$$$$\ $$ | \$$\ \$$$$$$$\ $$ |            \$$$$$$  |\$$$$$$  |\$$$$$$  |  $$ |   \$$$$$$  |$$$$$$$  |$$$$$$\  $$$$$$  |      $$$$$$\ $$$$$$$  |$$$$$$$$\
\_______/  \______/  \_______|\__|  \__| \_______|\__|             \______/  \______/  \______/   \__|    \______/ \_______/ \______| \______/       \______|\_______/ \________|

                                                                                                   Texas Instruments CCStudio(tm) for Docker
                                                                                                                          Creative by Uoohyo
                                                                                                                   https://github.com/uoohyo

EOF

# Variables
CCS_URL="https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-J1VdearkvK/"
VER="${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}"
# v20+: installs to /opt/ti/ccs/eclipse; v12-: installs to /opt/ti/ccsv<MAJOR>/eclipse
if [ "${MAJOR_VER}" -ge 20 ]; then
    CCS_ECLIPSE_DIR="/opt/ti/ccs/eclipse"
else
    CCS_ECLIPSE_DIR="/opt/ti/ccsv${MAJOR_VER}/eclipse"
fi
export PATH="${CCS_ECLIPSE_DIR}:${PATH}"

# Download and Install CCS
# v20+: zip package, CCS_ prefix, URL path: MAJOR.MINOR.PATCH
# v12-: tar.gz package, CCS prefix, URL path: MAJOR.MINOR.PATCH.BUILD
# v20+: udev stubs required — BlackHawk installer calls udev/kernel commands unavailable in Docker
#       Ref: https://e2e.ti.com/support/tools/code-composer-studio-group/ccs/f/code-composer-studio-forum/1532443
echo "=== CCS Installation ==="
echo "Version    : ${VER}"
echo "Components : ${COMPONENTS}"
echo ""

# Create temporary directory for installation
INSTALL_LOG="/tmp/ccs_install.log"
mkdir -p /ccs_install
cd /ccs_install

_show_install_logs() {
    echo ""
    echo "=== Installer Output ==="
    cat "${INSTALL_LOG}" 2>/dev/null || echo "(no output captured)"
    echo ""
    echo "=== TI Installer Logs ==="
    find /root/.ti /tmp /opt/ti -name "*.log" 2>/dev/null | while read -r f; do
        echo "--- ${f} ---"
        cat "${f}"
    done
    echo "========================"
}

# Download and Install CCS
echo ">>> Downloading CCS ${VER}..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    ln -sf /bin/true /usr/local/bin/udevadm
    ln -sf /bin/true /sbin/start_udev
    ln -sf /bin/true /sbin/udevd
    ln -sf /bin/true /sbin/modprobe
    ln -sf /bin/true /sbin/insmod
    ln -sf /bin/true /sbin/rmmod
    mkdir -p /etc/udev/rules.d /run/udev /lib/modules

    wget --timeout=300 --tries=3 "${CCS_URL}${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}/CCS_${VER}_linux.zip"
    echo ">>> Extracting..."
    unzip "CCS_${VER}_linux.zip"
    chmod -R 755 "CCS_${VER}_linux"
    echo ">>> Installing CCS ${VER} (this may take a while)..."
    cd "CCS_${VER}_linux"
    chmod +x "ccs_setup_${VER}.run"
    "./ccs_setup_${VER}.run" --mode unattended --enable-components "${COMPONENTS}" --prefix /opt/ti 2>&1 | tee "${INSTALL_LOG}"
else
    # v12: URL path is 3-part (MAJOR.MINOR.PATCH); v11 and below: 4-part (MAJOR.MINOR.PATCH.BUILD)
    if [ "${MAJOR_VER}" -ge 12 ]; then
        CCS_DL_PATH="${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}"
    else
        CCS_DL_PATH="${VER}"
    fi
    wget --timeout=300 --tries=3 "${CCS_URL}${CCS_DL_PATH}/CCS${VER}_linux-x64.tar.gz"
    echo ">>> Extracting..."
    tar -zxf "CCS${VER}_linux-x64.tar.gz"
    chmod -R 755 "CCS${VER}_linux-x64"
    echo ">>> Installing CCS ${VER} (this may take a while)..."
    "./CCS${VER}_linux-x64/ccs_setup_${VER}.run" \
        --mode unattended --enable-components "${COMPONENTS}" --prefix /opt/ti \
        --install-BlackHawk false --install-Segger false 2>&1 | tee "${INSTALL_LOG}"
fi

# Verify Installation
echo ">>> Verifying CCS installation..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    if ! test -x "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh"; then
        echo "[ERROR] CCS installation failed: ccs-server-cli.sh not found"
        _show_install_logs
        exit 1
    fi
else
    if ! test -x "${CCS_ECLIPSE_DIR}/eclipsec"; then
        echo "[ERROR] CCS installation failed: eclipsec not found"
        _show_install_logs
        exit 1
    fi
fi
echo ">>> CCS ${VER} installation complete."

# Cleanup
echo ">>> Cleaning up..."
cd /home
rm -rf /ccs_install

echo ""
echo "=== CCS ${VER} is ready. ==="
echo ""

# Run Command
exec "$@"
