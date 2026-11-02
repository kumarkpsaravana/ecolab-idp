# Vendor Evaluation Matrix — CIAM Feedback

## Purpose

This document provides feedback on the vendor evaluation questionnaire to ensure it adequately covers our CIAM (Customer Identity and Access Management) use case. The original matrix is oriented toward workforce/enterprise IAM. This feedback identifies what to keep, what to reframe, what to remove, and what's missing entirely.

## Context

We are replacing Azure AD B2C (end-of-support 2030) for a **customer-facing** identity platform. Key facts:

- ~64 federation partners (SAML + OIDC), growing 5-10/year
- ~150-200k sign-ins/day
- External customers and business partners authenticate — not employees
- Authorization is handled by a separate system (CDM); this platform is authentication + claims brokering only
- Must support multi-year coexistence with B2C during migration

---

## Section 1: Relevant As-Is (Keep)

These questions apply to our CIAM use case without modification:

| ID | Requirement |
|----|-------------|
| G.1 | Single Sign-On capabilities across applications |
| G.5 | Customizable, reusable policies that adapt to changing business needs |
| G.6 | Support for B2B and CIAM use cases |
| ARC.3 | High availability — minimum 99.9% uptime SLA with disaster recovery |
| ARC.4 | Horizontal/vertical scalability for high transaction volumes |
| ARC.6 | RESTful APIs and SDKs for integration, automation, and extensibility |
| ARC.7 | OpenAPI-conformant APIs |
| APP.1 | SAML 2.0, OAuth 2.0, OIDC, and SCIM support |
| APP.5 | Custom application integration via API/SDK |
| APP.6 | Automatic user provisioning/de-provisioning via SCIM or custom APIs |
| FED.4 | Federation using SAML 2.0, OpenID Connect, and OAuth 2.0 |
| SEC.3 | Data encryption at rest and in transit (AES-256) |
| SEC.4 | Compliance certifications (GDPR, SOC 2, ISO 27001) |
| LOG.1 | Comprehensive logging of authentication events and admin actions |
| LOG.3 | Audit trails for administrative actions |
| LOG.5 | Integration with external SIEM solutions |
| SUP.1 | 24/7 support for critical issues |
| SUP.2 | Dedicated account management |
| SUP.3 | Clear SLAs with defined response/resolution times |
| MISC.1-9 | Implementation services, SOX/SOC reporting, security assessments |

---

## Section 2: Partially Relevant (Reword for CIAM)

These questions address real concerns but are framed for workforce IAM. Suggested rewording:

| ID | Original Focus | Suggested Reframe |
|----|---------------|-------------------|
| G.2 | MFA with FIDO2, SMS, TOTP, push | "Support configurable verification methods including email OTP and SMS. Advanced methods (FIDO2, push) are optional/future." |
| G.3 | Adaptive risk-based authentication | Reclassify as nice-to-have. Relevant for fraud detection on customer logins but not a blocking requirement today. |
| G.4 | Fine-grained authorization policies (RBAC/ABAC) | "Must support claims-based token enrichment sourced from external authorization systems. The platform does NOT need to be the authorization policy decision point." |
| ARC.1 | Cloud + on-premises deployment | "Cloud-hosted solution required. Not locked to a single cloud provider. On-premises deployment is not required." |
| ARC.5 | Modular architecture (deploy auth/authz independently) | "Authentication must be separable from authorization. Platform must not force bundling of authz features we don't use." |
| APP.4 | AD, Azure AD, LDAP directory integration | "Must support inbound federation with Entra ID (Azure AD). Does NOT require Active Directory or LDAP synchronization for user stores." |
| SELF.1 | Self-service account management portal | "End-users must be able to reset passwords and manage MFA enrollment. Full account/profile management is handled by an external system." |
| SELF.2 | Self-service password reset | Keep, but note: only applies to local account users, not federated users. |
| UX.2 | Customizable branding | Keep as lower priority. Login pages should be brandable but this is not a differentiator. |
| UX.8 | Passwordless authentication | "Must support email OTP as a primary passwordless method. FIDO2/biometric support is optional." |
| UA.3 | Bulk user management (CSV, API, directory sync) | "Must support high-volume programmatic user creation and management via API. CSV import is not required." |
| REP.1 | Customizable reports | Keep but deprioritize — basic sign-in success/failure reporting and federation usage is sufficient. |
| REP.2 | Authentication success/failure reporting | Keep — useful for operational monitoring. |
| LOG.4 | Configurable log retention | Keep — but confirm retention needs with compliance team. |

---

## Section 3: Not Relevant (Remove or Deprioritize)

These sections address workforce/enterprise IAM concerns that do not apply to our CIAM use case:

### Remove Entirely

| Section | Reason |
|---------|--------|
| **ANIOT.1-5** (IoT Authentication) | No IoT devices in our use case. All users are humans authenticating via browser. |
| **AZIOT.1-4** (IoT Authorization) | Same — no IoT. |
| **CDM.1-7** (Cross-Domain SSO) | This addresses employees SSO-ing across corporate AD forests/domains. Our customers authenticate to one platform and receive one token. |
| **FED.1-3, FED.5** (Federated Session Management) | Addresses maintaining sessions across multiple internal corporate domains. Our users log in once and access one application per session. |

### Deprioritize (Not Blocking)

| ID | Reason |
|----|--------|
| SELF.3 | Access request/approval workflows — authorization is handled by CDM, not the identity platform |
| SELF.4 | Mobile profile management — end-users don't manage profiles in our system |
| SELF.5 | Multilingual self-service portal — nice-to-have, not blocking |
| UA.1 | RBAC for admins — small team, not a differentiator |
| UA.2 | Delegated administration across departments — not our operating model |
| UA.4 | Workflow automation for onboarding/offboarding — CDM handles user lifecycle |
| UA.5 | Fine-grained authz policy UI — explicitly not this platform's responsibility |
| UX.10 | Personalized user dashboard — users don't have dashboards, they log in and go to an app |
| UX.11 | Session management portal — not relevant for external customers |
| UX.13 | Behavioral analytics — future nice-to-have for fraud, not a requirement |
| APP.3 | M365/Salesforce/VPN integration — those are workforce apps, ours are custom |
| APP.7 | Third-party ML risk scoring — not a current need |
| SEC.1 | Zero Trust model — applies to network-based access; our users are external on the internet |
| SEC.5 | Incident response (auto-lockout, breach revocation) — nice-to-have, not core |
| REP.3 | MFA usage reporting — low priority |
| REP.4 | Adaptive auth reporting — we may not use adaptive auth |
| REP.5 | Login trend reporting — nice-to-have |
| LOG.6 | SIEM/XDR detail question — covered by LOG.5, this is redundant |
| UX.3-7, UX.9, UX.12 | Standard web UX requirements — assume any modern platform meets these |

---

## Section 4: Missing Requirements (Add to Matrix)

These are **critical** to our CIAM use case and completely absent from the current questionnaire. Without these, a vendor could score perfectly on the existing matrix and still be unable to replace Azure AD B2C for us.

### CIAM.1 — Home Realm Discovery at Scale

The product shall support Home Realm Discovery (HRD) to automatically route users to the correct Identity Provider based on their identifier (e.g., email domain). Must support 100+ configured IDPs concurrently without performance degradation.

### CIAM.2 — Mid-Flow External API Calls

The product shall support synchronous calls to external APIs during the authentication flow (e.g., for just-in-time user provisioning or token enrichment). Must include configurable error handling: block sign-in on failure, degrade gracefully, or skip the call entirely based on context.

### CIAM.3 — Custom OIDC Parameters from Relying Parties

The product shall accept custom parameters from relying party applications during authentication requests (beyond standard OIDC parameters) and make those values available within the flow for conditional logic, API calls, or token claims.

### CIAM.4 — Per-App / Per-Partner Conditional Flow Logic

The product shall support conditional branching within authentication flows based on the requesting application, the user's federation partner, or request parameters — without requiring duplication of the entire flow. Examples: skip an API call for a specific partner, include additional claims for a specific app, vary MFA requirements by partner.

### CIAM.5 — Claims Transformation Engine

The product shall provide a claims transformation engine capable of: renaming claims, case conversion, conditional inclusion/exclusion of claims, mapping partner-specific claim names to a standard internal schema, and computed/derived claim values. Must handle heterogeneous claim formats across 100+ federation partners.

### CIAM.6 — Audience-Specific Token Enrichment

The product shall support producing different token claim sets for different relying party applications based on request parameters. For example: application A sends parameter "alignmentType=S" and receives site-based claims; application B sends "alignmentType=A" and receives account-based claims — sourced from the same external API but with different inputs/outputs.

### CIAM.7 — Migration Coexistence with Azure AD B2C

The product shall support a multi-year coexistence period with Azure AD B2C during migration, including:
- Acting as an IDP that B2C federates to (so apps still on B2C can route users to the new platform)
- Consuming B2C as a federated IDP (so users not yet migrated still authenticate against B2C)
- Lazy/seamless credential migration: on a user's first login to the new platform, authenticate them against B2C, then set their credential in the new system transparently (Azure AD B2C does not support password hash export)
- Per-application cutover: apps migrate independently without requiring coordinated big-bang switch

### CIAM.8 — High-Volume Authentication Performance

The product shall demonstrate the ability to handle 200,000+ authentications per day with headroom for growth. High-volume flows that skip mid-flow API calls must not be impacted by other flows that include them. Provide benchmarks or reference architectures for sustained throughput at this scale.

### CIAM.9 — Multiple Credential Types (Externally Determined)

The product shall support multiple credential types within the same user store, where the credential type is determined at user creation time by an external system via API:
- Email + password (with first-login email verification)
- Email OTP-only (passwordless, user never sets a password)
- Single-use password (expires after first use, user sets permanent password)
- Phone number or non-email identifier as username
- Separate contact email for OTP delivery that differs from the sign-in identifier

### CIAM.10 — Infrastructure-as-Code and CI/CD

The product's full configuration (federation partners, flows, claim mappings, environment-specific settings) shall be expressible as code (Terraform, Pulumi, or native DSL) and deployable via CI/CD pipelines. Must support environment promotion (dev -> stage -> prod) with environment-specific variable substitution. API/CLI-first; a portal is acceptable but must not be the only configuration path.

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
| Keep as-is | 20 | No changes needed |
| Reword for CIAM | 14 | Adjust framing from workforce to customer-facing |
| Remove entirely | 16 | IoT, cross-domain SSO, federated session mgmt |
| Deprioritize | 20 | Not blocking — evaluate only if other requirements are met |
| **Add (missing, critical)** | **10** | **CIAM.1-10 — these are the actual differentiators** |

The most important takeaway: **the existing matrix does not ask a single question about the capabilities that actually make or break a CIAM platform for our use case.** A vendor could answer every existing question perfectly and still be completely unable to replace Azure AD B2C for us. The CIAM.1-10 additions are not nice-to-haves — they represent the core of what we need to evaluate.
