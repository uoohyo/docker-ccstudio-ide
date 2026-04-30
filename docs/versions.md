# Supported CCS Versions

This document is automatically updated.

**Last Update:** Initial version - will be auto-updated after first build

## 📦 Available Versions

<!-- VERSION_TABLE_START -->

*This table will be automatically populated after the first build completes.*

<!-- VERSION_TABLE_END -->

## 💡 Usage

```bash
# Run specific version
docker run -it --rm \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v $(pwd):/workspace \
  uoohyo/ccstudio-ide:{VERSION}
```

Replace `{VERSION}` with any version from the table above.

## 🔗 Related Links

- [Main README](../README.md)
- [Docker Hub Repository](https://hub.docker.com/r/uoohyo/ccstudio-ide)
- [TI CCS Official Site](https://www.ti.com/tool/CCSTUDIO)
