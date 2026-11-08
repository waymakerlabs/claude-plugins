#!/usr/bin/env bash
# herdr-stall-watch.sh — 호환 래퍼 (2.3.x 동안만 유지)
# 2.3.0에서 agent-stall-watch.sh로 이름이 바뀌었다. 옛 경로를 가리키는 Monitor 명령·문서가
# 깨지지 않게 같은 인자·환경 변수로 새 스크립트를 그대로 실행한다. 새 문서는 agent-stall-watch.sh를 쓴다.
exec "$(cd "$(dirname "$0")" && pwd)/agent-stall-watch.sh" "$@"
