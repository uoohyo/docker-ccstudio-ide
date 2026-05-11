# CCS Version Dependencies Matrix

## Official Requirements by Version

### v7-v8 (Ubuntu 18.04 base)

**Required packages (per TI official docs):**
- `libc6:i386` - 32-bit C library (compiler support)
- `libusb-0.1-4` - USB support
- `libgconf-2-4` - GNOME configuration (32-bit installer UI)
- `libxss1` - X11 Screen Saver extension (Ubuntu 12.04 requirement)
- `binutils` - Provides `strings` command (dependency checker requirement)
- `build-essential` - Development tools (optional but recommended)

**NOT required:**
- ❌ Python 2.7 - Not mentioned in v7/v8 docs
- ❌ GTK 2.0 - Not required for v7-v8

**Source:** 
- https://software-dl.ti.com/ccs/esd/documents/ccsv7_linux_host_support.html
- https://software-dl.ti.com/ccs/esd/documents/ccsv8_linux_host_support.html

### v9 (Ubuntu 20.04 base)

**Required packages:**
- `libc6:i386`
- `libusb-0.1-4`
- `libgconf-2-4`
- `libgtk2.0-0` - GTK 2.x (for UI components)
- `libncurses5`
- `libpython2.7` - **Required for Python scripting**
- `libtinfo5`

**Source:**
- https://software-dl.ti.com/ccs/esd/documents/ccsv9_linux_host_support.html

### v10-v11 (Ubuntu 20.04 base)

**Required packages:**
- `libc6:i386` (v10) → `libc6-i386` (v11)
- `libusb-0.1-4`
- `libgconf-2-4`
- `libncurses5`
- `libpython2.7` - **Required**
- `libtinfo5`

**Source:**
- https://software-dl.ti.com/ccs/esd/documents/ccsv10_linux_host_support.html
- https://software-dl.ti.com/ccs/esd/documents/ccsv11_linux_host_support.html

### v12-v19 (Ubuntu 22.04 base)

**Required packages:**
- `libc6-i386` - **Changed from libc6:i386**
- `libusb-0.1-4`
- `libgconf-2-4`
- `libncurses5`
- `libpython2.7` - **Required**
- `libtinfo5`

**Source:**
- https://software-dl.ti.com/ccs/esd/documents/ccsv12_linux_host_support.html

### v20+ (Ubuntu 22.04 base)

**Required packages:**
- `libc6-i386`
- `libusb-0.1-4`
- `libgconf-2-4`
- `libncurses5`
- `libtinfo5`

**NOT required:**
- ❌ Python 2.7 - **Dropped in v20**

**Source:**
- https://software-dl.ti.com/ccs/esd/documents/users_guide_ccs_20.0.0/ccs_overview.html

## Common Core Libraries (All Versions)

These are required by ALL CCS versions:

- `libudev1` - udev device management
- `libasound2` - ALSA sound support
- `libatk1.0-0` - Accessibility toolkit
- `libcairo2` - Cairo graphics
- `libgtk-3-0` - GTK 3.x (for UI)
- `libxi6` - X11 Input extension
- `libxtst6` - X11 Testing extension
- `libxrender1` - X11 Render extension
- `libxt6` - X11 toolkit
- `libusb-1.0-0-dev` - Modern USB support
- `libdbus-glib-1-2` - D-Bus GLib bindings
- `ca-certificates` - SSL certificates
- `unzip` - Archive extraction

## Optimization Strategy

### Current (Wasteful)
Install ALL dependencies for ALL versions → ~150MB

### Optimized (Recommended)
Install only version-specific dependencies based on BASE_IMAGE/MAJOR_VER → Save ~30-50MB

### Implementation
Use ARG MAJOR_VER to conditionally install packages in Dockerfile
