#!/bin/bash
set -euo pipefail

# 프로젝트 루트의 .env 로드
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
set -a
# shellcheck source=/dev/null
source "${PROJECT_DIR}/.env"
set +a

# .env에 없는 운영 변수 기본값
: "${LITELLM_URL:=http://localhost:8000}"
: "${DATA_DIR:=${PROJECT_DIR}/data}"

mkdir -p "${DATA_DIR}"

litellm_post() {
  local endpoint="$1"
  local payload="$2"
  local full_response http_code body

  full_response=$(curl -s -w "\n%{http_code}" \
    -X POST "${LITELLM_URL}${endpoint}" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload")

  http_code=$(echo "$full_response" | tail -1)
  body=$(echo "$full_response" | head -n -1)

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "ERROR [HTTP $http_code]: $body" >&2
    return 1
  fi
  echo "$body"
}

litellm_get() {
  local endpoint="$1"
  local full_response http_code body

  full_response=$(curl -s -w "\n%{http_code}" \
    -X GET "${LITELLM_URL}${endpoint}" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}")

  http_code=$(echo "$full_response" | tail -1)
  body=$(echo "$full_response" | head -n -1)

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "ERROR [HTTP $http_code]: $body" >&2
    return 1
  fi
  echo "$body"
}

wait_for_litellm() {
  local max_wait="${1:-60}"
  local elapsed=0
  echo -n "LiteLLM 준비 대기 중..."
  until curl -sf "${LITELLM_URL}/health/liveliness" > /dev/null 2>&1; do
    if [[ $elapsed -ge $max_wait ]]; then
      echo " 타임아웃 (${max_wait}s)" >&2
      return 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo -n "."
  done
  echo " 준비 완료"
}

team_id_by_alias() {
  local alias="$1"
  local cache="${DATA_DIR}/teams.json"
  if [[ -f "$cache" ]]; then
    local id
    id=$(jq -r --arg a "$alias" '.[] | select(.team_alias == $a) | .team_id' "$cache" 2>/dev/null || true)
    if [[ -n "$id" ]]; then
      echo "$id"
      return 0
    fi
  fi
  # 캐시에 없으면 API 조회
  local result
  result=$(litellm_get "/team/list")
  echo "$result" | jq -r --arg a "$alias" '.[] | select(.team_alias == $a) | .team_id' 2>/dev/null || true
}
