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
VER="${MAJOR_VER}.${MINOR_VER}.${PATCH_VER}.${BUILD_VER}"
# v9+: installs to /opt/ti/ccs/eclipse; v8-: installs to /opt/ti/ccsv<MAJOR>/eclipse
if [ "${MAJOR_VER}" -ge 9 ]; then
    CCS_ECLIPSE_DIR="/opt/ti/ccs/eclipse"
else
    CCS_ECLIPSE_DIR="/opt/ti/ccsv${MAJOR_VER}/eclipse"
fi
export PATH="${CCS_ECLIPSE_DIR}:${PATH}"

# v7-v8 specific dependencies
# These older versions require additional packages for dependency checker to pass
# Ref: https://software-dl.ti.com/ccs/esd/documents/ccsv7_linux_host_support.html
if [ "${MAJOR_VER}" -lt 9 ]; then
    echo "=== Installing v7-v8 Dependencies ==="
    echo "Version ${VER} requires additional packages for compatibility"
    apt-get update > /dev/null 2>&1
    apt-get install -y --no-install-recommends \
        binutils \
        libxss1 \
        > /dev/null 2>&1
    echo ">>> binutils and libxss1 installed"
    echo ""
fi

# Download and Install CCS
# v20+:  zip package, CCS_ prefix, URL path: MAJOR.MINOR.PATCH
# v12-:  tar.gz package, CCS prefix, URL path: MAJOR.MINOR.PATCH (v12) or MAJOR.MINOR.PATCH.BUILD (v11-)
# v10+:  installer binary is ccs_setup_<VER>.run, supports --enable-components (PF_* IDs)
# v9-:   installer binary is ccs_setup_linux64_<VER>.bin, --enable-components not supported
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

# Install CCS from pre-downloaded and extracted files
echo ">>> Using pre-downloaded and extracted CCS ${VER} installer..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    ln -sf /bin/true /usr/local/bin/udevadm
    ln -sf /bin/true /sbin/start_udev
    ln -sf /bin/true /sbin/udevd
    ln -sf /bin/true /sbin/modprobe
    ln -sf /bin/true /sbin/insmod
    ln -sf /bin/true /sbin/rmmod
    mkdir -p /etc/udev/rules.d /run/udev /lib/modules

    echo ">>> Installing CCS ${VER} (this may take a while)..."
    cd "/opt/ccs-installer/CCS_${VER}_linux"
    chmod +x "ccs_setup_${VER}.run"
    "./ccs_setup_${VER}.run" --mode unattended --enable-components "${COMPONENTS}" --prefix /opt/ti 2>&1 | tee "${INSTALL_LOG}"
else
    # Driver install scripts (bh_driver_install.sh for v7-v9, ti_permissions_install.sh for v10-v12)
    # copy udev rules then try to restart the udev service, which doesn't exist in Docker:
    #   v7-v9:   'service udev restart'  → "udev: unrecognized service"
    #   v10-v12: 'systemctl restart udev' → "not booted with systemd"
    # Either failure causes the BitRock/Run installer to roll back the full installation.
    # Fix: create required dirs, stub udev init script, and redirect udev-related commands to /bin/true.
    # /root/.ti is read by the installer's fs --clean step; missing it causes a boost::filesystem crash.
    mkdir -p /etc/init.d /etc/udev/rules.d /root/.ti
    printf '#!/bin/sh\nexit 0\n' > /etc/init.d/udev && chmod 755 /etc/init.d/udev
    ln -sf /bin/true /usr/local/bin/udevadm
    ln -sf /bin/true /usr/local/bin/systemctl

    echo ">>> Installing CCS ${VER} (this may take a while)..."
    # v10+: new installer (.run, supports --enable-components with PF_* IDs)
    # v9-:  old BitRock installer; binary name varies (linux64_*.bin or *.run), use find to detect
    if [ "${MAJOR_VER}" -ge 10 ]; then
        "/opt/ccs-installer/CCS${VER}_linux-x64/ccs_setup_${VER}.run" \
            --mode unattended --enable-components "${COMPONENTS}" --prefix /opt/ti \
            --install-BlackHawk false --install-Segger false 2>&1 | tee "${INSTALL_LOG}"
    else
        echo ">>> Note: --enable-components is not supported for CCS v9 and below. Installing all components."
        INSTALLER_BIN=$(find "/opt/ccs-installer/CCS${VER}_linux-x64" -maxdepth 1 \( -name "*.bin" -o -name "*.run" \) | sort | head -1)
        "${INSTALLER_BIN}" \
            --mode unattended --prefix /opt/ti \
            --install-BlackHawk false --install-Segger false 2>&1 | tee "${INSTALL_LOG}"
    fi
fi

# Verify Installation
# v20+: Theia-based, check ccs-server-cli.sh
# v19-: Eclipse-based, binary is always named 'eclipse' (not 'eclipsec')
echo ">>> Verifying CCS installation..."
if [ "${MAJOR_VER}" -ge 20 ]; then
    if ! test -x "${CCS_ECLIPSE_DIR}/ccs-server-cli.sh"; then
        echo "[ERROR] CCS installation failed: ccs-server-cli.sh not found"
        _show_install_logs
        exit 1
    fi
else
    if ! test -x "${CCS_ECLIPSE_DIR}/eclipse"; then
        echo "[ERROR] CCS installation failed: eclipse not found"
        _show_install_logs
        exit 1
    fi
fi
echo ">>> CCS ${VER} installation complete."

# Cleanup
echo ">>> Cleaning up..."
cd /home
rm -rf /opt/ccs-installer

echo ""
echo "=== CCS ${VER} is ready. ==="
echo ""

# Run Command
exec "$@"
