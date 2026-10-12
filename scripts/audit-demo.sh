#!/usr/bin/env bash
# Run a Curation audit against exact-version CVE and license examples.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/env.local.sh" ]]; then
    source "$ROOT/env.local.sh"
fi
: "${JFROG_SERVER_ID:?Set JFROG_SERVER_ID to a configured JFrog CLI server ID.}"
: "${NUGET_VIRTUAL_REPO:?Set NUGET_VIRTUAL_REPO to your NuGet virtual repository key.}"
if [[ ! "$NUGET_VIRTUAL_REPO" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "NUGET_VIRTUAL_REPO must be a repository key." >&2
    exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nuget-curation-audit.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
cp "$ROOT/audit-issues/AuditIssues.csproj" "$WORK/"
export NUGET_PACKAGES="$WORK/packages"
export NUGET_HTTP_CACHE_PATH="$WORK/http-cache"
export DOTNET_CLI_HOME="$WORK/dotnet-home"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
mkdir -p "$NUGET_PACKAGES" "$NUGET_HTTP_CACHE_PATH" "$DOTNET_CLI_HOME"

cd "$WORK"
jf nuget-config "--server-id-resolve=$JFROG_SERVER_ID" \
    "--repo-resolve=$NUGET_VIRTUAL_REPO" --nuget-v2=false
jf ca
