#!/usr/bin/env bash
# herdr-spawn-worker.sh — 호환 래퍼 (2.3.x 동안만 유지)
# 2.3.0에서 spawn-pane-worker.sh로 이름이 바뀌었다. 진행 중인 체인의 handoff·가이드·상태 파일이
# 옛 경로를 가리켜도 깨지지 않게 같은 인자·환경 변수·종료 코드로 새 스크립트를 그대로 실행한다.
# 새 문서·지시서는 spawn-pane-worker.sh를 쓴다.
exec "$(cd "$(dirname "$0")" && pwd)/spawn-pane-worker.sh" "$@"
