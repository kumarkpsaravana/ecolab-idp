# B2C Replacement — Core Requirements

## Context

Azure AD B2C end-of-support: 2030. This document captures the requirements for evaluating and selecting a replacement CIAM platform based on our current capabilities and future needs.

**Current state:**
- ~64 federation partners (SAML + OIDC), growing 5-10/year
- ~150-200k sign-ins/day (heavily concentrated on one high-volume flow)
- Three policy sets (HRD, EVD, Walmart/Spark) being consolidated
- CDM team owns user provisioning and authorization; identity team owns authentication and sign-in experience
- JIT provisioning for select partners (inline API call to CDM during sign-in)
- Custom B2C API wrapping Graph for user creation

---

## Authentication & Credential Types

1. Email + password (with first-login email verification before setting password)
2. Email OTP-only / passwordless (user never sets a password)
3. Single-use password at creation, then user sets permanent password
4. Phone number / non-email username support
5. Separate contact email for OTP that differs from the sign-in username

## Federation

6. Inbound SAML 2.0 and OIDC federation (partner-configurable)
7. Support 100+ federation partners concurrently
8. Per-partner claim mapping (rename/transform partner claims to internal schema)
9. "Common endpoint" / multi-tenant federation (e.g., Entra common without specific tenant)
10. Ability to add/remove federations without redeploying the entire configuration

## Home Realm Discovery

11. Route users to the correct IDP based on identifier/domain
12. Support multiple apps sharing the same HRD logic

## Token & Claims

13. Accept custom OIDC parameters from relying parties (e.g., `alignmentType`)
14. Claims transformations (case conversion, conditional logic, mappings)
15. Audience-specific token enrichment (different apps get different claim sets based on input parameters)
16. Ability to call external APIs mid-flow and inject response data into tokens

## API Integration (Mid-Flow)

17. Synchronous API calls during sign-in (JIT provisioning to CDM)
18. Configurable error handling when API calls fail (block sign-in vs degrade gracefully)
19. Ability to skip API calls for specific partners/apps (high-volume flows where app calls CDM separately)
20. Must handle high-volume sign-in without API calls becoming a bottleneck

## User Management

21. API-driven user provisioning (programmatic user creation with type/metadata)
22. Ability to set user type and attributes at creation time (called by CDM)
23. Programmatic user lifecycle management (create, disable, delete)

## Flow Flexibility

24. Per-app or per-partner conditional flow logic (skip steps, vary API calls, branch behavior) without duplicating the entire flow
25. Express variations as configuration within one flow, not separate policy forks
26. Support edge-case flows without requiring entirely separate deployments

## Migration

27. Must coexist with B2C during a multi-year transition period
28. Can act as IDP to B2C AND consume B2C as an IDP (bidirectional federation for gradual cutover)
29. Lazy/seamless credential migration for local users (authenticate against B2C on first login, set credential in new system — B2C does not export password hashes)
30. Per-app cutover (apps migrate independently on their own timelines)

## Performance

31. Must handle 200k+ daily authentications with headroom for growth
32. High-volume flows must remain performant even when other flows include inline API calls

## Operational / Non-Functional

33. Infrastructure-as-code (Terraform, Pulumi, or equivalent)
34. API/CLI-first configuration (portal is optional; automation is mandatory)
35. CI/CD friendly — environment-specific configs (stage/prod) deployable via pipeline
36. Audit logging for federation changes and sign-in events
37. Multi-environment support (dev/stage/prod minimum)

## Nice-to-Have

- Self-service federation onboarding portal for partners
- Off-boarding workflow / automated federation decommissioning
- Built-in authorization claim enrichment (reduce app-side CDM coupling over time)
- Cloud-agnostic (not locked to Azure)

---

## Constraints

- Does NOT need to be Azure-native (External ID likely insufficient)
- Does NOT need to store authorization data (CDM remains source of truth)
- Must be automatable — good API/IaC support is more valuable than a good portal
- Open-source (e.g., Keycloak) is acceptable if operationally viable
- Budget TBD — requirements first, cost comparison second

---

## Evaluation Criteria (suggested)

When comparing platforms, score against:

| Criteria | Weight |
|----------|--------|
| Federation flexibility (SAML + OIDC, claim mapping) | High |
| Mid-flow API call support | High |
| Conditional flow logic per app/partner | High |
| IaC / CI/CD automation | High |
| Migration path (B2C coexistence) | High |
| Performance at scale (200k+/day) | High |
| Local account credential types | Medium |
| Custom OIDC parameter support | Medium |
| Self-service onboarding | Low |
| Portal/UI quality | Low |
