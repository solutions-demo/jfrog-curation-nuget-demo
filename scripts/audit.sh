#!/usr/bin/env bash
# Show recent NuGet Curation download or CVS events.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/env.local.sh" ]]; then
    source "$ROOT/env.local.sh"
fi
: "${JFROG_SERVER_ID:?Set JFROG_SERVER_ID to a configured JFrog CLI server ID.}"
: "${NUGET_REMOTE_REPO:?Set NUGET_REMOTE_REPO to your curated NuGet remote repository key.}"

MODE=downloads
if [[ "${1:-}" == --cvs ]]; then
    MODE=cvs
    shift
fi
PACKAGE="${1:-}"
if (( $# > 1 )); then
    echo "Usage: $0 [--cvs] [package]" >&2
    exit 2
fi
OUT="$(mktemp "${TMPDIR:-/tmp}/nuget-curation-audit.XXXXXX")"
cleanup() { rm -f "$OUT"; }
trap cleanup EXIT

if [[ "$MODE" == cvs ]]; then
    jf api --server-id "$JFROG_SERVER_ID" \
        '/xray/api/v1/curation/audit/compliant-versions?num_of_rows=100&offset=0&direction=desc&package_type=NuGet&include_versions=true' > "$OUT"
    jq --arg package "$PACKAGE" --arg repo "$NUGET_REMOTE_REPO" '
        [.data[]
          | select(.curated_repo_name == $repo)
          | . as $event
          | .packages[]
          | select($package == "" or (.package_name | ascii_downcase) == ($package | ascii_downcase))
          | {
              id: $event.id,
              created_at: $event.created_at,
              curated_repo_name: $event.curated_repo_name,
              package_name,
              inspection_results,
              latest_inspected_version,
              versions: [.versions[] | {package_version, action, reason, policies: [.policies[]? | {policy_name, condition_name}]}]
            }
        ] | .[0:20]
    ' "$OUT"
    exit 0
fi

jf api --server-id "$JFROG_SERVER_ID" \
    '/xray/api/v1/curation/audit/packages?num_of_rows=500&offset=0&direction=desc' > "$OUT"

jq --arg package "$PACKAGE" --arg repo "$NUGET_REMOTE_REPO" '
    [.data[]
      | select(.package_type == "NuGet")
      | select(.curated_repository_name == $repo)
      | select($package == "" or (.package_name | ascii_downcase) == ($package | ascii_downcase))
      | {
          id,
          created_at,
          action,
          package_name,
          package_version,
          curated_repository_name,
          reason,
          policies: [.policies[]? | {policy_name, condition_name, result}]
        }
    ]
    | group_by([.package_name, .package_version, .action])
    | map(max_by(.id))
    | sort_by(.id)
    | reverse
    | .[0:20]
' "$OUT"
