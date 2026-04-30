# docker-ccstudio-ide

[![Build](https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/docker-publish.yml)

<!-- markdownlint-disable MD033 -->
<table>
  <tr>
    <td><img src="./.github/docker-ccstudio-ide.jpg" width="256" height="256" alt="docker-ccstudio-ide" /></td>
    <td valign="top">
      <b>CCS™ Version Test Status</b>
      <table>
        <tr><th>Version</th><th>Status</th></tr>
        <tr><td>v20.5.0.00028</td><td><a href="https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/test-v20.yml"><img src="https://img.shields.io/github/actions/workflow/status/uoohyo/docker-ccstudio-ide/test-v20.yml?branch=main&label=&style=flat-square" alt="v20.5.0" /></a></td></tr>
        <tr><td>v12.8.1.00005</td><td><a href="https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/test-v12.yml"><img src="https://img.shields.io/github/actions/workflow/status/uoohyo/docker-ccstudio-ide/test-v12.yml?branch=main&label=&style=flat-square" alt="v12.8.1" /></a></td></tr>
        <tr><td>v11.2.0.00007</td><td><a href="https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/test-v11.yml"><img src="https://img.shields.io/github/actions/workflow/status/uoohyo/docker-ccstudio-ide/test-v11.yml?branch=main&label=&style=flat-square" alt="v11.2.0" /></a></td></tr>
        <tr><td>v10.4.0.00006</td><td><a href="https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/test-v10.yml"><img src="https://img.shields.io/github/actions/workflow/status/uoohyo/docker-ccstudio-ide/test-v10.yml?branch=main&label=&style=flat-square" alt="v10.4.0" /></a></td></tr>
        <tr><td>v9.3.0.00012</td><td><a href="https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/test-v9.yml"><img src="https://img.shields.io/github/actions/workflow/status/uoohyo/docker-ccstudio-ide/test-v9.yml?branch=main&label=&style=flat-square" alt="v9.3.0" /></a></td></tr>
        <tr><td>v8.3.1.00004</td><td><a href="https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/test-v8.yml"><img src="https://img.shields.io/github/actions/workflow/status/uoohyo/docker-ccstudio-ide/test-v8.yml?branch=main&label=&style=flat-square" alt="v8.3.1" /></a></td></tr>
        <tr><td>v7.4.0.00015</td><td><a href="https://github.com/uoohyo/docker-ccstudio-ide/actions/workflows/test-v7.yml"><img src="https://img.shields.io/github/actions/workflow/status/uoohyo/docker-ccstudio-ide/test-v7.yml?branch=main&label=&style=flat-square" alt="v7.4.0" /></a></td></tr>
      </table>
    </td>
  </tr>
</table>
<!-- markdownlint-enable MD033 -->

The [`docker-ccstudio-ide`](https://github.com/uoohyo/docker-ccstudio-ide) Docker image provides a CI/CD environment for projects developed in the Code Composer Studio IDE from Texas Instruments. Code Composer Studio is an integrated development environment (IDE) for TI's microcontrollers and processors, comprising a suite of tools used to develop and debug embedded applications.

> **Note:** CCS is downloaded and installed when the container starts, not at image build time. An internet connection is required at runtime.

## Build

To create the [`uoohyo/ccstudio-ide`](https://hub.docker.com/r/uoohyo/ccstudio-ide) Docker image, execute the following command inside the `docker-ccstudio-ide` directory:

    docker build -t uoohyo/ccstudio-ide .

## Run

Pull the [`uoohyo/ccstudio-ide`](https://hub.docker.com/r/uoohyo/ccstudio-ide) image from Docker Hub using the following command:

    docker pull uoohyo/ccstudio-ide:latest

Run the pulled image. By default, the image is configured with the latest version of [Code Composer Studio](https://www.ti.com/tool/CCSTUDIO) available at the time of the image update. The development tools are set to support `C2000 real-time MCUs`:

    docker run -it uoohyo/ccstudio-ide:latest

> **Estimated startup time:** Expect **~5 minutes** on first run with optimized parallel download (download ~2 min + installation ~3 min). Time may vary depending on network speed and system performance.

### Performance

The download process is optimized using [aria2](https://aria2.github.io/) with 16 parallel connections, providing **73.5% faster** installation compared to traditional single-connection downloads:

- **Traditional (wget)**: 17m 40s
- **Optimized (aria2)**: 4m 41s
- **Improvement**: 73.5% faster, saving 12m 59s

### Environments

You can modify environment variables when running the [`uoohyo/ccstudio-ide`](https://hub.docker.com/r/uoohyo/ccstudio-ide) image to specify the version and development tools configuration of Code Composer Studio to be installed. Here is how you can customize it:

    docker run -it \
    -e MAJOR_VER=20 \
    -e MINOR_VER=5 \
    -e PATCH_VER=0 \
    -e BUILD_VER=00028 \
    -e COMPONENTS=PF_C28 \
    uoohyo/ccstudio-ide:latest

#### Version

The structure of the [Code Composer Studio](https://www.ti.com/tool/CCSTUDIO) version is as follows:

    <MAJOR_VER> . <MINOR_VER> . <PATCH_VER> . <BUILD_VER>

The default environment variables are set to the latest version available at the time of the image update:

    ENV MAJOR_VER=20
    ENV MINOR_VER=5
    ENV PATCH_VER=0
    ENV BUILD_VER=00028

For the latest version information, visit [this link](https://www.ti.com/tool/download/CCSTUDIO).

#### Components

Component selection via the `COMPONENTS` variable is supported on **CCS v10 and above**. For CCS v9 and below, the `COMPONENTS` variable is ignored and all product families are installed.

When installing [Code Composer Studio](https://www.ti.com/tool/CCSTUDIO), you can choose from various [Texas Instruments Inc.](https://www.ti.com/) product families. Below is a list of installable product families:

| Product family    | Description                                                                  |
| ----------------- | ---------------------------------------------------------------------------- |
| PF_MSP430         | MSP430 ultra-low power MCUs                                                  |
| PF_MSP432         | SimpleLink™ MSP432™ low power + performance MCUs                             |
| PF_CC2X           | SimpleLink™ CC13xx and CC26xx Wireless MCUs                                  |
| PF_CC3X           | SimpleLink™ Wi-Fi® CC32xx Wireless MCUs                                      |
| PF_CC2538         | CC2538 IEEE 802.15.4 Wireless MCUs                                           |
| PF_C28            | C2000 real-time MCUs                                                         |
| PF_TM4C           | TM4C12x ARM® Cortex®-M4F core-based MCUs                                     |
| PF_PGA            | PGA Sensor Signal Conditioners                                               |
| PF_HERCULES       | Hercules™ Safety MCUs                                                        |
| PF_SITARA         | Sitara™ AM3x, AM4x, AM5x and AM6x MPUs (will also include AM2x for CCS 10.x) |
| PF_SITARA_MCU     | Sitara™ AM2x MCUs (only supported in CCS 11.x and greater)                   |
| PF_OMAPL          | OMAP-L1x DSP + ARM9® Processor                                               |
| PF_DAVINCI        | DaVinci (DM) Video Processors                                                |
| PF_OMAP           | OMAP Processors                                                              |
| PF_TDA_DRA        | TDAx Driver Assistance SoCs & Jacinto DRAx Infotainment SoCs                 |
| PF_C55            | C55x ultra-low-power DSP                                                     |
| PF_C6000SC        | C6000 Power-Optimized DSP                                                    |
| PF_C66AK_KEYSTONE | 66AK2x multicore DSP + ARM® Processors & C66x KeyStone™ multicore DSP        |
| PF_MMWAVE         | mmWave Sensors                                                               |
| PF_C64MC          | C64x multicore DSP                                                           |
| PF_DIGITAL_POWER  | UCD Digital Power Controllers                                                |

> **Note:** For CCS v9 and below, the installer does not support component selection. All product families will be installed regardless of the `COMPONENTS` value, which will result in a larger installation size.

Multiple product families can be installed by separating their names with a comma in the `COMPONENTS` variable. Here is an example that installs development tools for both PF_MSP430 and PF_CC2X:

    docker run -it \
    -e COMPONENTS="PF_MSP430,PF_CC2X" \
    uoohyo/ccstudio-ide:latest

## Usage

Once the image is running, you can add projects to the workspace and execute builds based on specific build options. Below are example commands to demonstrate these actions.

**CCS v20 and above (Theia-based):**

Import a project into the workspace:

    ccs-server-cli -noSplash -workspace <workspace_path> -application com.ti.ccs.apps.importProject -ccs.location <project_path>

Build a project using specific configuration:

    ccs-server-cli -noSplash -workspace <workspace_path> -application com.ti.ccs.apps.buildProject -ccs.projects <project_name> -ccs.configuration <build_name>

**CCS v12 and below (Eclipse-based):**

Import a project into the workspace:

    eclipse -noSplash -data <workspace_path> -application com.ti.ccstudio.apps.projectImport -ccs.location <project_path>

Build a project using specific configuration:

    eclipse -noSplash -data <workspace_path> -application com.ti.ccstudio.apps.projectBuild -ccs.projects <project_name> -ccs.configuration <build_name>

These commands manage projects within the Code Composer Studio environment without the need for a graphical interface, making them ideal for automated environments such as continuous integration setups.

For more detailed commands and explanations, visit [this link](https://software-dl.ti.com/ccs/esd/documents/users_guide_ccs_20.0.0/ccs_project-command-line.html).

## License

[MIT License](./LICENSE)

Copyright (c) 2024-2026 [uoohyo](https://github.com/uoohyo)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
