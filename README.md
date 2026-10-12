# JFrog Curation Demo for NuGet

This .NET 10 console application demonstrates three Curation blocks (immaturity, a named CVE, and a license) plus Compliant Version Selection (CVS). It uses real NuGet packages and a real Artifactory remote repository. The application does not simulate Curation decisions.

This guide is for an operator installing the demo on **their own JFrog environment**. Repository keys, server IDs, URLs, policy IDs, and audit event IDs are local to each environment.

## 1. Prerequisites

- A JFrog Platform deployment with Artifactory, Curation, and permission to create repositories, conditions, and policies.
- .NET 10 SDK, JFrog CLI (`jf`), Bash, and `jq` on the demo machine.
- A JFrog CLI server configuration with permission to resolve from the NuGet repository and read Curation audit events. Creating policies additionally requires Curation administration permission.
- For the CVS scenario, Artifactory **7.143.2+**, Curation/Xray **3.142.3+**, and a working **NuGet V3** feed. [JFrog CVS support matrix](https://docs.jfrog.com/security/docs/compliant-version-selection).

Configure and check the CLI connection using your normal JFrog login method:

```bash
jf config add
jf config show
```

Never put an access token in this project or in `NuGet.Config`.

## 2. Create and connect the repositories

In **Administration → Repositories**, create a NuGet **remote** repository that proxies NuGet Gallery. Use `https://www.nuget.org/` as the remote URL and `https://api.nuget.org/v3/index.json` as its NuGet V3 feed URL. Create a NuGet **virtual** repository that includes this remote. The example values below are keys, not required names:

| Setting | Example |
| --- | --- |
| Remote repository key | `demo-nuget-remote` |
| Virtual repository key | `demo-nuget-virtual` |
| JFrog platform URL | `https://example.jfrog.io` |
| JFrog CLI server ID | `my-jfrog-server` |

In **Administration → Curation → Remote Repositories**, connect the **remote** repository to Curation. The application will resolve through the virtual repository, but Curation policies must be scoped to the remote key. Keep the virtual limited to this remote for a predictable demo. Enable Pass-Through Curation on the remote if you want to run `jf ca`; JFrog lists it as required for NuGet Curation audit. [JFrog repository connection guide](https://docs.jfrog.com/security/docs/connect-remote-repositories-to-curation), [Curation Compliance Check](https://docs.jfrog.com/security/docs/curation-compliance-check), [Artifactory NuGet repository guide](https://docs.jfrog.com/artifactory/docs/nuget-repositories).

Check the V3 feed before demonstrating CVS. A `dotnet restore` against its V3 index must be able to download a baseline package. A V3 feed that lists versions but returns `404` for package content cannot complete the CVS scenario, even when CVS selects a compliant version.

## 3. Create the demo conditions and policies

First inspect existing policies for the remote repository. Global policies also apply and may block a package for additional reasons. Create these three **custom conditions** in **Administration → Curation → Conditions**:

| Condition name | Template | Parameter |
| --- | --- | --- |
| `NuGet Demo - Immaturity 88 Days` | Package version is immature (`isImmature`) | `package_age_days = 88`; leave the optional CVSS relaxation unset |
| `NuGet Demo - CVE-2024-21907` | Package Vulnerable to a Specific CVE (`CVEName`) | `cve_name = CVE-2024-21907` |
| `NuGet Demo - PolyForm Noncommercial` | Block list by License (`BannedLicenses`) | Ban `PolyForm-Noncommercial-1.0.0`; set multiple-license permissive approach to `false` |

JFrog Catalog reported `PolyForm-Noncommercial-1.0.0` for EPPlus 5.0.3 in the reference environment. **Check this version in your own Catalog** before creating the license condition; use the identifier that your Catalog displays.

For each condition, create a policy in **Application → Curation → Policies** with the same name and these settings:

| Policy setting | Value |
| --- | --- |
| Scope | **Specific repositories**: select the NuGet **remote** key only |
| Condition | The matching condition from the table above |
| Action | **Block** |
| Block from cache | **Enabled** |
| Pending Catalog / on-demand analysis | **Skip** |
| Waiver requests | **Forbidden** for this demo |
| Federation sharing | **Disabled** |

The result is three enabled Block policies scoped to one remote repository. They affect every client using that remote, including clients that access it through the virtual. Existing global policies are outside this demo's setup and should be reviewed separately. The [condition API](https://docs.jfrog.com/security/reference/createcondition) and [policy API](https://docs.jfrog.com/security/reference/createpolicy) document the corresponding programmatic operations.

The reference environment also had global 30-day immaturity and malicious-package policies. Its immaturity audit event therefore named **both** the global 30-day policy and the new 88-day policy. If you need an audit event attributable to the 88-day policy alone, use an isolated environment or adjust other applicable policies according to your organization's rules.

## 4. Configure this project for your instance

Clone the repository, then export these four values in the shell that will run the scripts:

```bash
git clone https://github.com/solutions-demo/jfrog-curation-nuget-demo.git
cd jfrog-curation-nuget-demo
export JFROG_SERVER_ID=my-jfrog-server
export JFROG_BASE_URL=https://example.jfrog.io
export NUGET_REMOTE_REPO=demo-nuget-remote
export NUGET_VIRTUAL_REPO=demo-nuget-virtual
./scripts/setup.sh
dotnet nuget list source
jf ca  # Requires a working Curation audit NuGet feed; see the reference-instance note below
```

`JFROG_BASE_URL` is the HTTPS platform URL **without** `/artifactory` or a trailing path. `JFROG_SERVER_ID` must match the ID shown by `jf config show`. Use the exact repository keys created in step 2. The scripts do not contain instance credentials.

`NuGet.Config.example` is the distributed placeholder. `scripts/setup.sh` creates an ignored local `NuGet.Config` with only your Artifactory source and configures both `jf dotnet` and `jf nuget`. The latter is needed by `jf ca`; `jf dotnet-config` alone does not configure it. The setup script does not change global .NET or JFrog CLI configuration. Your local `env.local.sh` can hold the four exports above; it is ignored by Git.

`jf ca` audits the default `baseline` dependencies in `NuGetDemo.csproj`. Use the demo commands below for the policy-block scenarios. For CVS, use `scripts/demo.sh cvs`, which calls `scripts/setup.sh v3`; plain `dotnet restore` after the default setup uses V2 and does not exercise CVS. Rerun `scripts/setup.sh` to restore V2 after a CVS run.

## 5. Run and verify the scenarios

```bash
./scripts/demo.sh baseline        # Expected: restore succeeds
./scripts/demo.sh immaturity      # Expected: FluentValidation 12.2.0 is blocked
./scripts/demo.sh vulnerability   # Expected: Newtonsoft.Json 12.0.1 is blocked
./scripts/demo.sh license         # Expected: EPPlus 5.0.3 is blocked
./scripts/demo.sh cvs             # Expected: V3 selects a compliant FluentValidation 12.x
```

| Scenario | Direct package reference | What to verify |
| --- | --- | --- |
| `baseline` | FluentValidation 12.0.0; Newtonsoft.Json 13.0.3 | Restore succeeds through Artifactory. |
| `immaturity` | FluentValidation 12.2.0 | Download audit shows the 88-day policy, unless the version is now old enough to pass. |
| `vulnerability` | Newtonsoft.Json 12.0.1 | Download audit names the CVE-2024-21907 policy. |
| `license` | EPPlus 5.0.3 | Download audit names the PolyForm license policy. |
| `cvs` | FluentValidation `12.*` | CVS audit shows the blocked version and the compliant version selected. A healthy V3 feed then completes the restore. |

The immaturity example is **time-sensitive**: FluentValidation 12.2.0 was published on October 10, 2026. After it reaches 88 days old, select another recently published NuGet version, update `NuGetDemo.csproj`, and verify its publication date in your Catalog. The CVE and license examples also depend on your Catalog data and any other active policies.

`Version="12.*"` is deliberately floating so NuGet can choose another 12.x version. A `PackageReference` with `Version="12.2.0"` means **at least** 12.2.0, so it cannot fall back to an older 12.x release. Locked versions cannot use CVS as a substitute. CVS supports NuGet V3, not V2. [NuGet version resolution](https://learn.microsoft.com/en-us/nuget/concepts/dependency-resolution), [JFrog CVS behavior](https://docs.jfrog.com/security/docs/behavior-by-package).

Each run uses fresh temporary NuGet package, HTTP, and `obj` directories and requests packages through Artifactory. It does **not** clear Artifactory's remote cache. Logs remain in `demo-logs/`. The script returns a nonzero exit code for an expected policy block; use the audit event to distinguish a Curation block from an unrelated `403`.

To build and execute the baseline after a successful restore:

```bash
jf dotnet build NuGetDemo.csproj -p:DemoScenario=baseline --configuration Release
dotnet run --project NuGetDemo.csproj --no-restore --configuration Release -p:DemoScenario=baseline
```

Expected output: `{"customer":"JFrog Curation demo","quantity":2,"valid":true}`.

## 6. Inspect Curation audit events

```bash
./scripts/audit.sh FluentValidation
./scripts/audit.sh --cvs FluentValidation
./scripts/audit.sh Newtonsoft.Json
./scripts/audit.sh EPPlus
```

The audit script filters results to `NUGET_REMOTE_REPO`. It uses the [download audit API](https://docs.jfrog.com/security/reference/getauditpackages) or, with `--cvs`, the [CVS audit API](https://docs.jfrog.com/security/reference/searchcvsaudit). You can also inspect **Application → Curation → Audit Events → Downloads / CVS**. Match the package, version, repository, policy, and time; a `403` by itself is not proof of Curation.

## Reference-environment result and troubleshooting

On October 12, 2026, the reference instance blocked the three scenario packages and passed the baseline. Its policy IDs were `1043` (88-day immaturity), `1044` (CVE), and `1045` (license); **do not reuse these IDs** in another environment. The CVS audit selected FluentValidation 12.1.1 over 12.2.0, but this instance's V3 registration response supplied a `packageContent` URL under `.../registration-semver2/Download/...` that returned `404`. The V2 scenarios worked. This is a limitation of that instance's V3 download flow, not evidence that CVS is unsupported for NuGet.

After the setup fix, `jf ca` detects this project, reads `nuget.yaml`, and selects `soleng-dev-nuget`. On this reference instance, its dependency restore still fails through the Curation audit V3 feed at `/artifactory/api/curation/audit/api/nuget/v3/soleng-dev-nuget/index.json`: it lists the baseline packages but cannot download their `.nupkg` files. The same failure occurred when `jf ca` detected the native Artifactory source instead of `nuget.yaml`. Fixing this feed is required for an end-to-end CLI Curation audit here; the Downloads and CVS audit views remain available for the policy demonstrations.

| Symptom | Check |
| --- | --- |
| `403` on a demo package | Match the package, version, and policy in Downloads audit. Check for other global policies. |
| `404` or “feed lists package, download failed” in `cvs` | Check the V3 index, registration response, and `packageContent` URL of your virtual repository. |
| `cvs` selects no alternative | Confirm CVS is enabled, V3 is used, the requested version range allows an older release, and one such version passes all policies. |
| A blocking scenario succeeds | Verify remote-repository Curation connection, policy scope and action, Catalog data, package age, and cache enforcement. |
| Direct nuget.org request appears | Check your local NuGet sources and run through `scripts/demo.sh`; the generated `NuGet.Config` clears inherited sources. |
| `jf ca` says no NuGet config or source | Run `./scripts/setup.sh`, then confirm `dotnet nuget list source` shows your Artifactory virtual URL. |
| `jf ca` detects NuGet but cannot download packages | Inspect the Curation audit V3 feed and its package download URLs. A working V2 restore does not verify this V3 audit path. |

The demo scripts configure the local project and read audit data. Policy and repository creation are the explicit administration steps in sections 2 and 3.
