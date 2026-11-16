# B2C Home Realm Discovery Policy

Azure AD B2C custom policy set that implements Home Realm Discovery (HRD) for federated sign-in. When a user signs in, the policy extracts the domain from their email address, looks it up against a configured list of federation partners, and redirects the user to the appropriate external identity provider (Entra ID, Okta, Ping, OneLogin) via SAML or OIDC. Users whose domains don't match a federation partner fall through to B2C's local account sign-in.

## Environments

| Tenant | Environment | Branch |
|---|---|---|
| wintersnowb2c | Dev | `dev` |
| wintersnowb2c | Stage | `stage` |
| ecolabb2c | Prod | `prod` |

## Query String Parameters

These parameters can be passed to the policy via the authorization request URL:

| Parameter | Description |
|---|---|
| `domain_hint` | Bypasses email-based domain lookup and routes directly to a specific federation partner |
| `email` | Pre-fills the sign-in email field. Also passed as `login_hint` to the federated IdP |
| `allow_jit` | Set to `true` to enable JIT (Just-In-Time) provisioning. The federation partner must also have `jitEnabled` configured |
| `alignment_type` | Controls the JIT alignment type for provisioning |
| `mcp_id` | Passes an MCP identifier through the authentication flow |
| `sspr` | Set to `true` to trigger the self-service password reset flow |

## Policy Inheritance

B2C custom policies use an inheritance chain where each policy builds on its parent. Policies must be uploaded in order from base to leaf.

```
B2C_1A_Connect_Base
└── B2C_1A_Connect_Federations              federation partner technical profiles (SAML + OIDC)
    ├── B2C_1A_Domain_Hint                   domain_hint direct routing (the old version, depricating)
    └── B2C_1A_Connect_Federated_Auth        post-federation orchestration, JIT logic
        └── B2C_1A_Connect_Local_Auth        local account sign-in, password reset
            └── B2C_1A_Connect_Extensions    claims, transformations, API calls, AppInsights
                ├── B2C_1A_Connect_OIDC_SignIn       (relying party: OIDC)
                │   └── B2C_1A_TrueView_OIDC_SignIn  (relying party: TrueView OIDC)
                ├── B2C_1A_Connect_SAML_SignIn        (relying party: SAML)
                ├── B2C_1A_CDMClaims_OIDC_SignIn      (relying party: CDM OIDC)
                ├── B2C_1A_CDMClaims_SAML_SignIn      (relying party: CDM SAML)
                ├── B2C_1A_BillTrust_SAML_SignIn      (relying party: BillTrust SAML)
                └── B2C_1A_Admin_Sign_Up              (relying party: admin signup)
```

**Key files by layer:**

- **Connect_Base** -- Core claims schema, claim types, and content definitions. Do not modify.
- **Connect_Federations** -- Contains a `<ClaimsProvider>` for each federation partner with their SAML/OIDC technical profiles and SubJourney routing entries. This is the primary file modified when adding new federations.
- **Connect_Federated_Auth** -- Orchestrates what happens after federation: account linking, JIT provisioning decision, and the JIT SubJourney.
- **Connect_Local_Auth** -- Local account sign-in, password validation, and SSPR flows.
- **Connect_Extensions** -- Claims transformations (domain parsing, domain lookup, JIT string-to-boolean), REST API calls (CDM JIT register), Application Insights logging, and session management. This is the largest policy file.
- **Relying Party policies** -- Token issuance configuration. Each RP selects an issuer (JWT or SAML) and defines which claims appear in the output token.

## Repository Structure

```
.
├── B2C_1A_*.xml                  Policy templates (contain {Settings:...} placeholders)
├── appsettings.json              Per-environment settings (Dev, Stage, Prod sections)
├── deploy-config.json            Policies to exclude from deployment
├── Environments/
│   ├── Dev/                      Built policies for dev (wintersnowb2c, _dev suffix)
│   ├── Stage/                    Built policies for stage (wintersnowb2c)
│   └── Prod/                     Built policies for prod (ecolabb2c)
├── federationTemplates/          XML templates used by Add-Federation.ps1
│   ├── entra-saml.xmltemplate
│   ├── entra-oidc.xmltemplate
│   ├── ping-saml.xmltemplate
│   ├── onelogin-saml.xmltemplate
│   ├── okta-saml.xmltemplate
│   └── okta-oidc.xmltemplate
├── scripts/
│   ├── Add-Federation.ps1        Interactive script to add a new federation partner
│   ├── DeployEnvironmentFolderToB2C.ps1   Deploys all policies from an environment folder
│   └── DeployToB2c.ps1           Deploys a single policy file
└── pipelines/
    ├── azure-pipelines-dev.yml       Auto-deploy on push to dev
    ├── azure-pipelines-stage.yml     Auto-deploy on push to stage
    ├── azure-pipelines-prod.yml      Auto-deploy on push to prod
    └── promote-federation.yml        Manual trigger: promotes federation files from stage to prod
```

### Build Process

Root-level XML files are **templates** -- they contain `{Settings:...}` placeholders that get resolved during build. The VS Code [Azure AD B2C IEF extension](https://marketplace.visualstudio.com/items?itemName=AzureADB2CTools.aadb2c) "Build All Policies" command reads the templates plus `appsettings.json` and outputs environment-specific XML to `Environments/{Dev,Stage,Prod}/`. These built files are what get uploaded to B2C.

## Supported Federation IdP Types

| IdP | Protocols | Template |
|---|---|---|
| Entra ID (Azure AD) | SAML, OIDC | `entra-saml.xmltemplate`, `entra-oidc.xmltemplate` |
| Okta | SAML, OIDC | `okta-saml.xmltemplate`, `okta-oidc.xmltemplate` |
| Ping Identity | SAML | `ping-saml.xmltemplate` |
| OneLogin | SAML | `onelogin-saml.xmltemplate` |

## Adding a New Federation

### 1. Run the Add-Federation script

```powershell
./scripts/Add-Federation.ps1
```

The script prompts for:
- IdP type (Entra ID, Okta, Ping, OneLogin / SAML or OIDC)
- Display name (e.g., "Kraft")
- IDP value / tenant name (e.g., "kraft.com")
- JIT enabled (y/N)
- Stage metadata URL
- Prod metadata URL (optional -- can be added later)

It auto-detects the next federation partner number, generates the technical profile from a template, inserts it into `B2C_1A_Connect_Federations.xml`, and adds the corresponding settings to `appsettings.json`.

### 2. Build policies

In VS Code with the IEF extension, run **Build All Policies**. This resolves the `{Settings:...}` placeholders and outputs the environment-specific files to `Environments/`.

### 3. Sync the known IdP lookup before manual upload

After building the policies, run the sync for the environment you plan to upload. This updates that environment's `B2C_1A_Connect_Extensions.xml` using its federation policy and the corresponding `PolicySettings` in the root `appsettings.json`:

```powershell
./scripts/Sync-KnownIdP.ps1 -EnvironmentName Dev
./scripts/Sync-KnownIdP.ps1 -EnvironmentName Stage
./scripts/Sync-KnownIdP.ps1 -EnvironmentName Prod
```

Run only the command for the target environment, then review the `LookupKnownIdP` diff in `Environments/<Environment>/B2C_1A_Connect_Extensions.xml` before manually uploading policies. The environment name is required so the script cannot accidentally update the root template instead of the policy files being uploaded.

The Dev, Stage, and Prod deployment pipelines run the sync automatically before deploying, so this manual step is needed only when uploading policies outside the pipelines. If a referenced setting is missing for an environment, the script warns and omits that domain.

### 4. Deploy to stage

Commit and push to the `stage` branch. The stage pipeline automatically deploys all policies to the wintersnowb2c tenant.

```
git checkout stage
git add B2C_1A_Connect_Federations.xml appsettings.json Environments/
git commit -m "Add federation: Kraft (SAML)"
git push
```

### 5. Test

Work with the federation partner to test the sign-in flow in the stage environment.

### 6. Promote to prod

When the federation partner provides prod metadata and testing is complete:

1. If prod metadata wasn't added in step 1, update `appsettings.json` with the prod metadata URL, rebuild, and push to `stage`
2. In Azure DevOps, run the **Promote Federation** pipeline (`promote-federation.yml`). This creates a PR that checks out the federation files from `stage` and targets the `prod` branch.
3. Review the PR diff -- it shows exactly what will change in prod
4. Merge the PR. The prod pipeline automatically deploys to the ecolabb2c tenant.

### Pipelines

| Pipeline | Trigger | Action |
|---|---|---|
| `azure-pipelines-dev.yml` | Push to `dev` | Deploy `Environments/Dev/` to wintersnowb2c |
| `azure-pipelines-stage.yml` | Push to `stage` | Deploy `Environments/Stage/` to wintersnowb2c |
| `azure-pipelines-prod.yml` | Push to `prod` | Deploy `Environments/Prod/` to ecolabb2c |
| `promote-federation.yml` | Manual | Create PR to promote federation files from `stage` to `prod` |

All deployment pipelines back up the current policies before uploading and will automatically roll back if any policy upload fails.
