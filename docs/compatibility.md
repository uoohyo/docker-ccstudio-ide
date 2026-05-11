# CCS Version Compatibility Guide

## Ubuntu Base Image Strategy

This project uses **Ubuntu 22.04 LTS** as the single base image for all CCS versions (v7-v20).

### Why Ubuntu 22.04?

- **Backward compatibility**: Supports packages required by older CCS versions (v7-v8)
- **Forward compatibility**: Compatible with newer CCS versions (v20+)
- **LTS support**: Extended support until 2027
- **Package availability**: All required 32-bit libraries available
- **Build optimization**: Single base image reduces CI/CD complexity

## Version-Specific Requirements

### CCS v7-v8 (2016-2018)

**Officially tested on:**
- Ubuntu 18.04 LTS
- Ubuntu 16.04 LTS
- Ubuntu 12.04 LTS

**Docker implementation:**
- Base: Ubuntu 22.04 LTS
- Additional packages: `binutils`, `libxss1`, `libpython2.7`
- Status: ✅ Fully supported with dependency workarounds

**Key dependencies:**
- `libc6:i386`, `libusb-0.1-4`, `libgconf-2-4`
- `binutils` (provides `strings` command for dependency checker)
- `libxss1` (X11 Screen Saver extension)

**Known issues:**
- Dependency checker requires `binutils` package
- Installation takes longer (~10-15 min) as `--enable-components` not supported

**Official documentation:**
- v7: https://software-dl.ti.com/ccs/esd/documents/ccsv7_linux_host_support.html
- v8: https://software-dl.ti.com/ccs/esd/documents/ccsv8_linux_host_support.html

### CCS v9 (2018-2020)

**Officially tested on:**
- Ubuntu 19.10, 18.04 LTS, 16.04 LTS

**Docker implementation:**
- Base: Ubuntu 22.04 LTS
- All dependencies installed at build time
- Status: ✅ Fully supported

**Key dependencies:**
- `libpython2.7` (required for Python scripting support)
- `libgtk2.0-0` (GTK 2.x for UI)
- `libncurses5`, `libtinfo5`

**Known issues:**
- Permission bugs in v9.2/v9.3 (TI acknowledged)
- Project creation requires X11 (use template approach for automation)

**Official documentation:**
- https://software-dl.ti.com/ccs/esd/documents/ccsv9_linux_host_support.html

### CCS v10-v11 (2020-2022)

**Officially tested on:**
- v10: Ubuntu 21.04, 20.04 LTS, 18.04 LTS
- v11: Ubuntu 20.04 LTS, 18.04 LTS

**Docker implementation:**
- Base: Ubuntu 22.04 LTS
- Dependency naming change: `libc6:i386` → `libc6-i386` (both installed for compatibility)
- Status: ✅ Fully supported

**Key dependencies:**
- `libc6-i386` (note: different package name from v7-v9)
- `libpython2.7`, `libusb-0.1-4`, `libgconf-2-4`
- `libncurses5`, `libtinfo5`

**Official documentation:**
- v10: https://software-dl.ti.com/ccs/esd/documents/ccsv10_linux_host_support.html
- v11: https://software-dl.ti.com/ccs/esd/documents/ccsv11_linux_host_support.html

### CCS v12-v19 (2022-2024)

**Officially tested on:**
- v12: Ubuntu 24.04*, 22.04, 20.04, 18.04 LTS

*24.04 noted as functional but not officially tested

**Docker implementation:**
- Base: Ubuntu 22.04 LTS
- Native support for Ubuntu 22.04
- Status: ✅ Fully supported

**Key dependencies:**
Same as v10-v11

**Official documentation:**
- v12: https://software-dl.ti.com/ccs/esd/documents/ccsv12_linux_host_support.html

### CCS v20+ (2024+)

**Officially tested on:**
- Ubuntu 24.04, 22.04, 20.04 LTS

**Docker implementation:**
- Base: Ubuntu 22.04 LTS
- Python 2.7 no longer required
- Theia-based IDE (different from Eclipse-based v7-v19)
- Status: ✅ Fully supported

**Key changes:**
- No `libpython2.7` dependency
- New CLI: `ccs-server-cli.sh` instead of `eclipse`
- Requires udev stubs (BlackHawk drivers)

**Official documentation:**
- https://software-dl.ti.com/ccs/esd/documents/users_guide_ccs_20.0.0/ccs_overview.html#System-Requirements

## Dependency Matrix

| Package | v7-v8 | v9 | v10-v11 | v12-v19 | v20+ | Notes |
|---------|-------|----|---------|---------| -----|-------|
| libc6:i386 | ✅ | ✅ | ✅ | ✅ | ✅ | 32-bit C library |
| libc6-i386 | ✅ | ✅ | ✅ | ✅ | ✅ | Alternative package name (v11+) |
| libusb-0.1-4 | ✅ | ✅ | ✅ | ✅ | ✅ | USB 0.1 support |
| libgconf-2-4 | ✅ | ✅ | ✅ | ✅ | ✅ | GNOME configuration |
| libncurses5 | ✅ | ✅ | ✅ | ✅ | ✅ | Terminal library |
| libtinfo5 | ✅ | ✅ | ✅ | ✅ | ✅ | Terminal info |
| libpython2.7 | ❌ | ✅ | ✅ | ✅ | ❌ | Python 2.7 libraries |
| libgtk2.0-0 | ❌ | ✅ | ✅ | ✅ | ❌ | GTK 2.x |
| binutils | ✅ | ❌ | ❌ | ❌ | ❌ | Provides `strings` (v7-v8 only) |
| libxss1 | ✅ | ❌ | ❌ | ❌ | ❌ | X11 Screen Saver (v7-v8 only) |

## Installation Strategy

### Build-Time vs Runtime Installation

**Current approach: Build-time installation**

All dependencies are installed in the Dockerfile during image build:

```dockerfile
RUN apt-get update && \
    apt-get install -y \
    libc6:i386 \
    libc6-i386 \
    libpython2.7 \
    binutils \
    # ... all other packages
```

**Advantages:**
- ✅ Faster container startup (no apt-get update at runtime)
- ✅ No network required at runtime
- ✅ Consistent environment across all versions
- ✅ Simpler entrypoint.sh logic

**Trade-offs:**
- ⚠️ Slightly larger base image (~50-100MB)
- ⚠️ Some packages unused by certain versions (e.g., binutils for v10+)

**Alternative (not used):**
- Runtime installation in entrypoint.sh based on MAJOR_VER
- Would save image size but slow startup and require network

## Docker Environment Stubs

### udev/systemd Compatibility

CCS installers attempt to interact with system services that don't exist in Docker:
- `udevadm` (device management)
- `systemctl` (systemd service management)
- Kernel module loading (`modprobe`, `insmod`, `rmmod`)

**Solution:** Create stub scripts that always return success

```bash
# entrypoint.sh
ln -sf /bin/true /usr/local/bin/udevadm
ln -sf /bin/true /usr/local/bin/systemctl
mkdir -p /etc/udev/rules.d /etc/init.d
printf '#!/bin/sh\nexit 0\n' > /etc/init.d/udev
```

This prevents installer failures while maintaining security (no actual device access needed for headless builds).

## Troubleshooting

### v7-v8: "Failed to find lib: libpython2.7.so.1.0"

**Cause:** Installer's dependency checker looking for Python 2.7
**Solution:** Now installed in Dockerfile - should not occur
**Verify:** `docker exec <container> dpkg -l | grep libpython2.7`

### v7-v8: "strings: not found"

**Cause:** Dependency checker uses `strings` command from binutils
**Solution:** Now installed in Dockerfile
**Verify:** `docker exec <container> which strings`

### Any version: Installation hangs

**Possible causes:**
1. Missing udev stubs (check entrypoint.sh creates them)
2. Insufficient resources (increase Docker memory limit)
3. Network timeout during installation

**Debug:**
```bash
docker exec <container> ps aux  # Check if installer is actually running
docker logs <container>         # Check for errors
```

### v9: Project creation fails

**Cause:** v9 requires X11 display for project creation
**Solution:** Use template-based project creation (not CLI)

## Testing

### Dependency Verification

Test that all required packages are installed:

```bash
# For any version
docker run uoohyo/ccstudio-ide:<version> dpkg -l | grep libc6

# For v7-v8 specifically
docker run uoohyo/ccstudio-ide:7.1.0.00016 which strings

# For v9-v12 (Python 2.7 required)
docker run uoohyo/ccstudio-ide:9.3.0.00012 dpkg -l | grep libpython2.7
```

### Installation Success

Verify CCS installed correctly:

```bash
# v20+
docker run uoohyo/ccstudio-ide:20.5.0.00028 test -f /opt/ti/ccs/eclipse/ccs-server-cli.sh

# v10-v19
docker run uoohyo/ccstudio-ide:12.8.0.00012 test -f /opt/ti/ccs/eclipse/eclipse

# v7-v9
docker run uoohyo/ccstudio-ide:7.1.0.00016 test -f /opt/ti/ccsv7/eclipse/eclipse
```

## Future Considerations

### Ubuntu 22.04 EOL (2027)

When Ubuntu 22.04 reaches end-of-life:
- **Option 1:** Migrate to Ubuntu 24.04 LTS (verify all CCS versions still compatible)
- **Option 2:** Multi-base image strategy (different Ubuntu versions for different CCS ranges)
- **Option 3:** Freeze at Ubuntu 22.04 for archived versions, use newer Ubuntu for new CCS releases

### Python 2.7 Availability

Python 2.7 packages may be removed from future Ubuntu versions:
- **Risk:** Low (v9-v12 are legacy, library-only packages likely to persist)
- **Mitigation:** Consider pre-downloading Python 2.7 .deb files if Ubuntu drops support
- **Timeline:** Monitor Ubuntu 26.04, 28.04 package availability

### 32-bit Library Support

Ubuntu may phase out multilib (i386 architecture) support:
- **Current:** Ubuntu 22.04 fully supports `:i386` packages
- **Risk:** Medium-term (5+ years)
- **Mitigation:** Docker allows using older base images indefinitely

## References

- [CCS v7 Linux Support](https://software-dl.ti.com/ccs/esd/documents/ccsv7_linux_host_support.html)
- [CCS v8 Linux Support](https://software-dl.ti.com/ccs/esd/documents/ccsv8_linux_host_support.html)
- [CCS v9 Linux Support](https://software-dl.ti.com/ccs/esd/documents/ccsv9_linux_host_support.html)
- [CCS v10 Linux Support](https://software-dl.ti.com/ccs/esd/documents/ccsv10_linux_host_support.html)
- [CCS v11 Linux Support](https://software-dl.ti.com/ccs/esd/documents/ccsv11_linux_host_support.html)
- [CCS v12 Linux Support](https://software-dl.ti.com/ccs/esd/documents/ccsv12_linux_host_support.html)
- [CCS v20 System Requirements](https://software-dl.ti.com/ccs/esd/documents/users_guide_ccs_20.0.0/ccs_overview.html#System-Requirements)
