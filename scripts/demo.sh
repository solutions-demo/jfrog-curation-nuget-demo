#!/usr/bin/env bash
# Restore one scenario through Artifactory with a disposable NuGet cache.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-baseline}"
case "$SCENARIO" in
    baseline|immaturity|cvs|vulnerability|license) ;;
    *) echo "Usage: $0 [baseline|immaturity|cvs|vulnerability|license]" >&2; exit 2 ;;
esac

: "${JFROG_SERVER_ID:?Set JFROG_SERVER_ID to a configured JFrog CLI server ID.}"
: "${JFROG_BASE_URL:?Set JFROG_BASE_URL to your platform URL, for example https://example.jfrog.io.}"
: "${NUGET_VIRTUAL_REPO:?Set NUGET_VIRTUAL_REPO to your NuGet virtual repository key.}"
JFROG_BASE_URL="${JFROG_BASE_URL%/}"
if [[ ! "$JFROG_BASE_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
    echo "JFROG_BASE_URL must be an HTTPS platform URL without a path." >&2
    exit 2
fi
if [[ ! "$NUGET_VIRTUAL_REPO" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "NUGET_VIRTUAL_REPO must be a repository key." >&2
    exit 2
fi

NUGET_V2_URL="$JFROG_BASE_URL/artifactory/api/nuget/$NUGET_VIRTUAL_REPO"
NUGET_V3_URL="$JFROG_BASE_URL/artifactory/api/nuget/v3/$NUGET_VIRTUAL_REPO"

NUGET_V2=true
if [[ "$SCENARIO" == cvs ]]; then
    NUGET_V2=false
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nuget-curation.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

export NUGET_PACKAGES="$WORK/packages"
export NUGET_HTTP_CACHE_PATH="$WORK/http-cache"
export DOTNET_CLI_HOME="$WORK/dotnet-home"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
mkdir -p "$NUGET_PACKAGES" "$NUGET_HTTP_CACHE_PATH" "$DOTNET_CLI_HOME" "$ROOT/demo-logs"

LOG="$ROOT/demo-logs/$(date +%Y%m%d-%H%M%S)-$SCENARIO.log"
echo "Scenario: $SCENARIO"
echo "Artifactory virtual: $NUGET_VIRTUAL_REPO"
echo "NuGet V3 (CVS) enabled: $([[ "$NUGET_V2" == false ]] && echo yes || echo no)"
echo "Isolated NuGet packages: $NUGET_PACKAGES"
echo "Isolated NuGet HTTP cache: $NUGET_HTTP_CACHE_PATH"
echo "Log: $LOG"

cd "$ROOT"
if [[ "$SCENARIO" == cvs ]]; then
    "$ROOT/scripts/setup.sh" v3
else
    "$ROOT/scripts/setup.sh" v2
fi

if jf dotnet restore NuGetDemo.csproj --no-cache --force --verbosity normal \
    "-p:DemoScenario=$SCENARIO" \
    "-p:BaseIntermediateOutputPath=$WORK/obj/" 2>&1 | tee "$LOG"; then
    if grep -Eq 'https://(api|www)\.nuget\.org' "$LOG"; then
        echo "Restore contacted nuget.org directly. Inspect $LOG." >&2
        exit 1
    fi
    if ! grep -Fq "$NUGET_V2_URL" "$LOG" && ! grep -Fq "$NUGET_V3_URL" "$LOG"; then
        echo "No Artifactory package request is visible in $LOG." >&2
        exit 1
    fi
    echo "Restore succeeded. Packages came through the configured Artifactory virtual."
    if [[ "$SCENARIO" == baseline ]]; then
        echo "Run $ROOT/scripts/demo.sh immaturity to test the immaturity policy."
    fi
else
    if [[ "$SCENARIO" == cvs ]] && grep -Fq 'registration-semver2/Download/' "$LOG" && grep -Fq 'NotFound ' "$LOG"; then
        echo "CVS selected a compliant version, but this Artifactory V3 feed returned 404 for its package download URL." >&2
        echo "Inspect the GET .../Download/<package>/<version> line in $LOG; the V3 feed must be fixed for an end-to-end CVS restore." >&2
    fi
    echo "Restore failed. Inspect $LOG and Curation Audit Events for the package and policy." >&2
    exit 1
fi
