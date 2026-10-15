#!/usr/bin/env bash
# Configure this checkout for .NET restore and JFrog Curation audit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/env.local.sh" ]]; then
    source "$ROOT/env.local.sh"
fi
PROTOCOL="${1:-v2}"
case "$PROTOCOL" in
    v2) NUGET_V2=true ;;
    v3) NUGET_V2=false ;;
    *) echo "Usage: $0 [v2|v3]" >&2; exit 2 ;;
esac

: "${JFROG_SERVER_ID:?Set JFROG_SERVER_ID to a configured JFrog CLI server ID.}"
: "${JFROG_BASE_URL:?Set JFROG_BASE_URL to your HTTPS JFrog platform URL.}"
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

SOURCE_URL="$JFROG_BASE_URL/artifactory/api/nuget/$NUGET_VIRTUAL_REPO"
if [[ "$PROTOCOL" == v3 ]]; then
    SOURCE_URL="$JFROG_BASE_URL/artifactory/api/nuget/v3/$NUGET_VIRTUAL_REPO/index.json"
fi

cd "$ROOT"
cat > NuGet.Config <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="Artifactory" value="$SOURCE_URL" />
  </packageSources>
</configuration>
EOF

jf dotnet-config "--server-id-resolve=$JFROG_SERVER_ID" \
    "--repo-resolve=$NUGET_VIRTUAL_REPO" "--nuget-v2=$NUGET_V2"
jf nuget-config "--server-id-resolve=$JFROG_SERVER_ID" \
    "--repo-resolve=$NUGET_VIRTUAL_REPO" "--nuget-v2=$NUGET_V2"

# Configure each scenario so `jf ca` works directly from its directory.
for SCENARIO in baseline immaturity vulnerability license cvs; do
    (
        cd "$ROOT/scenarios/$SCENARIO"
        jf nuget-config "--server-id-resolve=$JFROG_SERVER_ID" \
            "--repo-resolve=$NUGET_VIRTUAL_REPO" --nuget-v2=false
    )
done
(
    cd "$ROOT/audit-issues"
    jf nuget-config "--server-id-resolve=$JFROG_SERVER_ID" \
        "--repo-resolve=$NUGET_VIRTUAL_REPO" --nuget-v2=false
)

echo "Configured .NET, NuGet Curation audit, and local NuGet.Config for $NUGET_VIRTUAL_REPO ($PROTOCOL)."
echo "Baseline audit: jf ca (0 blocked packages expected)"
echo "Scenario audits: (cd scenarios/<scenario> && jf ca)"
echo "Combined CVE and license audit: (cd audit-issues && jf ca)"
