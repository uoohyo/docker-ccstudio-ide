# CCS Studio IDE 지원 버전

이 문서는 자동으로 업데이트됩니다.

**최종 업데이트:** Initial version - will be auto-updated

## 📦 사용 가능한 버전

<!-- VERSION_TABLE_START -->

*이 테이블은 첫 빌드 완료 후 자동으로 채워집니다.*

<!-- VERSION_TABLE_END -->

## 💡 사용 방법

```bash
# 특정 버전 실행
docker run -it --rm \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v $(pwd):/workspace \
  uoohyo/ccstudio-ide:{VERSION}
```

## 🔗 관련 링크

- [메인 README](../README.md)
- [Docker Hub](https://hub.docker.com/r/uoohyo/ccstudio-ide)
- [TI CCS 공식 사이트](https://www.ti.com/tool/CCSTUDIO)
