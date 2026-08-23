#!/usr/bin/env bash
# Trigger PollerFunction to backfill completed games over a date range.
#
# Usage:
#   infra/scripts/backfill.sh [--prod] [--start-date MM/DD/YYYY] [--end-date MM/DD/YYYY]
#
# Defaults to a local sam local invoke covering 2026 season-to-date
# (03/01/2026 through today). Pass --prod to invoke the deployed Lambda
# via the `baseball-lake` AWS profile instead.
set -euo pipefail
cd "$(dirname "$0")/../.."

MODE="local"
START_DATE="03/01/2026"
END_DATE="$(date +%m/%d/%Y)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod) MODE="prod"; shift ;;
    --start-date) START_DATE="$2"; shift 2 ;;
    --end-date) END_DATE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

PAYLOAD=$(printf '{"start_date":"%s","end_date":"%s"}' "$START_DATE" "$END_DATE")
echo "Backfilling $START_DATE -> $END_DATE ($MODE)"

if [[ "$MODE" == "prod" ]]; then
  aws lambda invoke \
    --profile baseball-lake \
    --function-name baseball-datalake-poller \
    --payload "$PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    /tmp/poller-backfill-response.json
  cat /tmp/poller-backfill-response.json
else
  EVENT_FILE=$(mktemp)
  echo "$PAYLOAD" > "$EVENT_FILE"
  trap 'rm -f "$EVENT_FILE"' EXIT

  make sam-build
  sam local invoke PollerFunction \
    -t .aws-sam/build/template.yaml \
    -e "$EVENT_FILE" \
    --env-vars src/events/local-env-vars.json
fi
