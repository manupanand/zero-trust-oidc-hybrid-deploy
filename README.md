# Hybrid On-Prem ↔ Cloud OIDC Connect with Workload Identity (Zero-Trust Deployment Model)

> A production-grade reference implementation demonstrating how to securely deploy code from a cloud control plane (GCP) to on-premise infrastructure with **zero inbound connectivity, zero standing credentials, and zero VPN** — using OIDC, Workload Identity Federation, self-hosted JWKS, and pull-based Ansible automation.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GCP](https://img.shields.io/badge/Cloud-GCP-4285F4?logo=google-cloud&logoColor=white)](https://cloud.google.com)
[![Python](https://img.shields.io/badge/API-Python_3.12-3776AB?logo=python&logoColor=white)](https://www.python.org)
[![FastAPI](https://img.shields.io/badge/Framework-FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Next.js](https://img.shields.io/badge/UI-Next.js_14-000000?logo=next.js&logoColor=white)](https://nextjs.org)
[![Go](https://img.shields.io/badge/Agent-Go_1.22-00ADD8?logo=go&logoColor=white)](https://go.dev)
[![Ansible](https://img.shields.io/badge/Automation-Ansible-EE0000?logo=ansible&logoColor=white)](https://www.ansible.com)
[![Postgres](https://img.shields.io/badge/DB-PostgreSQL-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org)

---

## 📌 Project Overview

This project simulates a real-world enterprise hybrid deployment scenario where a centralized cloud platform must securely deploy configuration and code to on-premise servers that have **no public IP, no inbound ports open, and no VPN connection** to the cloud.

It implements a modern **zero-trust deployment pattern** with full user management, using:

- **OpenID Connect (OIDC)** for human authentication (Google as IdP)
- **Self-hosted JWKS issuer** built into the API for machine identity (your own micro-IdP)
- **GCP Workload Identity Federation** for keyless cloud access from on-prem
- **PostgreSQL-backed user management** (users, sessions, roles, audit log)
- **Pull-based Ansible automation** triggered by user actions in a web UI
- **Outbound-only network model** (HTTPS 443 only, no inbound to on-prem)
- **Job-scoped, short-lived tokens** with automated key rotation

This pattern mirrors how production systems like Google Anthos, AWS Systems Manager, Azure Arc, GitHub Actions OIDC, and HashiCorp Boundary operate.

---

## 🎯 Why This Project Matters

Traditional infrastructure automation tools (Ansible push, SSH-based deployment) require **inbound network access** to managed nodes — a non-starter for:

- **Compliance-regulated environments** (PCI-DSS, HIPAA, ISO 27001, SOC 2)
- **Air-gapped or segmented networks** (banking, healthcare, OT/ICS)
- **Multi-cloud or edge deployments** behind corporate NAT
- **Zero-trust architectures** where identity is the perimeter

This project demonstrates the modern alternative: **the on-prem server pulls from the cloud, authenticated via short-lived OIDC tokens issued only when an authorized human triggers a deploy.**

---

## 🏗️ System Architecture (Top-Level View)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  GCP                                         │
│                                                                              │
│  ┌──────────────────────────┐         ┌────────────────────────────────┐     │
│  │   Cloud Run: UI          │         │   Cloud Run: API               │     │
│  │   ───────────────        │         │   ──────────────               │     │
│  │   Next.js 14 (App Router)│ ───────▶│   Python 3.12 + FastAPI        │     │
│  │   • Login page           │  HTTPS  │   • Google OIDC user auth      │     │
│  │   • Dashboard            │         │   • User management CRUD       │     │
│  │   • Deploy button        │         │   • JWKS endpoint (machine IdP)│     │
│  │   • Job status (SSE)     │         │   • JWT minting (deploy)       │     │
│  │   URL: ui-xxx.run.app    │         │   • Pub/Sub publisher          │     │
│  │                          │         │   URL: api-xxx.run.app         │     │
│  │   TLS: Auto (Google)     │         │   TLS: Auto (Google)           │     │
│  └──────────────────────────┘         └────────────────────────────────┘     │
│         ▲                                       │       │       │            │
│         │                                       ▼       ▼       ▼            │
│         │                              ┌─────────┐ ┌────────┐ ┌──────────┐   │
│         │                              │ Cloud   │ │ Secret │ │  Cloud   │   │
│         │                              │ SQL     │ │Manager │ │ Pub/Sub  │   │
│         │                              │(Postgres)│ │       │ │(trigger) │   │
│         │                              │         │ │ • RSA  │ │          │   │
│         │                              │ • users │ │   keys │ │ • topic: │   │
│         │                              │ • sess. │ │ • OAuth│ │   deploy │   │
│         │                              │ • jobs  │ │   secret│ │          │   │
│         │                              │ • audit │ │ • DB pw│ │          │   │
│         │                              └─────────┘ └────────┘ └──────────┘   │
│         │                                                          │         │
│         │       ┌────────────────────────────────────┐              │         │
│         │       │  Workload Identity Federation Pool │              │         │
│         │       │  Provider Issuer:                  │              │         │
│         │       │  https://api-xxx.run.app           │ ◀────────────┘         │
│         │       │  (fetches /.well-known/jwks.json)  │                        │
│         │       └────────────────────────────────────┘                        │
│         │                                                                    │
│         │       ┌────────────────────────────────────┐                       │
│         │       │  GCP Source Repository             │                       │
│         │       │  (Ansible playbooks)               │                       │
│         │       └────────────────────────────────────┘                       │
│         │                                                                    │
│         │       ┌────────────────────────────────────┐                       │
│         │       │  Cloud Logging                     │                       │
│         │       │  • User actions   • Agent logs     │                       │
│         │       │  • API requests   • Audit events   │                       │
│         │       └────────────────────────────────────┘                       │
│         │                                                                    │
└─────────┼────────────────────────────────────────────────────────────────────┘
          │
          │  Browser session (HTTPS cookie)
          │
       ┌──┴───┐
       │ USER │
       └──────┘                                    ┌─ HTTPS 443 (Pub/Sub pull)
                                                   ├─ HTTPS 443 (git clone)
                                                   ├─ HTTPS 443 (STS exchange)
                                                   └─ HTTPS 443 (log shipping)
                                                            ▲
═════════════════════════════════ NAT GATEWAY (one-way) ═════│════════════════
                                                            │
                                                            │ outbound only
                                                            │
┌────────────────────────────────────────────────────────────┼─────────────────┐
│                          AWS (On-Prem Sim)                 │                 │
│                                                            │                 │
│  ┌────────────────────────────────────────────────────────────────────┐      │
│  │          Private Subnet (no public IP)                             │      │
│  │                                                                    │      │
│  │   ┌────────────────────────────────────────────────────────────┐   │      │
│  │   │   Single EC2 VM (t3.small Ubuntu)                          │   │      │
│  │   │                                                            │   │      │
│  │   │   ┌──────────────────────────────────────────────────┐     │   │      │
│  │   │   │   Go Agent (systemd service)                     │     │   │      │
│  │   │   │   ─────────────────────────                      │     │   │      │
│  │   │   │   • Subscribes to Pub/Sub topic                  │     │   │      │
│  │   │   │   • Receives: {jwt, repo_url, job_id, user}      │     │   │      │
│  │   │   │   • Exchanges jwt → GCP access_token via STS     │     │   │      │
│  │   │   │   • git clone + ansible-pull                     │     │   │      │
│  │   │   │   • Streams logs to Cloud Logging                │     │   │      │
│  │   │   └──────────────────────────────────────────────────┘     │   │      │
│  │   │                                                            │   │      │
│  │   │   Ansible installed locally                                │   │      │
│  │   └────────────────────────────────────────────────────────────┘   │      │
│  └────────────────────────────────────────────────────────────────────┘      │
│                                                                              │
│  Security Group: outbound 443 only, NO inbound                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔍 GCP Internal Workflow (Detailed Component Interactions)

The diagrams below show **what happens inside GCP** during the two key flows: user login and deploy trigger. Every storage component, every API call, every read/write is annotated.

### Flow 1: User Login Workflow Inside GCP

```
                            ┌──────────────────────────────────────────────────┐
                            │                  GCP PROJECT                     │
                            │                                                  │
   ┌────────┐               │                                                  │
   │  USER  │               │                                                  │
   │Browser │───[1] HTTPS GET / ──┐                                             │
   └────────┘               │     ▼                                             │
                            │  ┌───────────────────┐                            │
                            │  │  Cloud Run: UI    │                            │
                            │  │  (Next.js)        │                            │
                            │  └────────┬──────────┘                            │
                            │           │                                       │
                            │       [2] /auth/login (server-side fetch)         │
                            │           ▼                                       │
                            │  ┌───────────────────┐                            │
                            │  │  Cloud Run: API   │                            │
                            │  │  (FastAPI)        │                            │
                            │  └────────┬──────────┘                            │
                            │           │                                       │
                            │   [3] Build OAuth URL (state + PKCE challenge)    │
                            │           │                                       │
                            │      ┌────┼─────┐                                 │
                            │      │    │     │                                 │
                            │      ▼    ▼     ▼                                 │
                            │   ┌─────┐ ┌─────┐ ┌─────────┐                     │
                            │   │Redis│ │Secret│ │Cloud SQL│                    │
                            │   │     │ │Mgr  │ │         │                     │
                            │   │SET  │ │GET  │ │INSERT   │                     │
                            │   │state│ │OAuth│ │login_   │                     │
                            │   │+ver │ │client│ │attempt  │                    │
                            │   │TTL5m│ │secret│ │         │                    │
                            │   └─────┘ └─────┘ └─────────┘                     │
                            │           │                                       │
                            │   [4] 302 Redirect → accounts.google.com          │
                            │           │                                       │
                            └───────────┼───────────────────────────────────────┘
                                        ▼
                              ┌──────────────────────┐
                              │ Google OIDC IdP      │
                              │ (External)           │
                              │ User logs in + MFA   │
                              │ Issues auth_code     │
                              └────────┬─────────────┘
                                       │
                                       │ [5] 302 to /auth/callback?code=...
                                       ▼
                            ┌──────────────────────────────────────────────────┐
                            │                  GCP PROJECT                     │
                            │                                                  │
                            │  ┌───────────────────┐                           │
                            │  │  Cloud Run: API   │                           │
                            │  │  /auth/callback   │                           │
                            │  └────────┬──────────┘                           │
                            │           │                                      │
                            │   [6] Read state + verifier from Redis           │
                            │      ┌────▼──────┐                               │
                            │      │ Redis     │                               │
                            │      │ GET state │                               │
                            │      └────┬──────┘                               │
                            │           │                                      │
                            │   [7] Exchange code for tokens (POST → Google)   │
                            │      ┌────▼─────────┐                            │
                            │      │ Secret Mgr   │                            │
                            │      │ GET oauth    │                            │
                            │      │ client_secret│                            │
                            │      └────┬─────────┘                            │
                            │           │                                      │
                            │           │ POST → accounts.google.com/token     │
                            │           │ (returns id_token, access_token,     │
                            │           │  refresh_token)                      │
                            │           │                                      │
                            │   [8] Validate id_token JWT                      │
                            │       (signature via Google's JWKS,              │
                            │        iss, aud, exp checks)                     │
                            │           │                                      │
                            │   [9] Encrypt refresh_token                      │
                            │      ┌────▼─────────┐                            │
                            │      │ Secret Mgr   │                            │
                            │      │ GET enc_key  │                            │
                            │      └────┬─────────┘                            │
                            │           │                                      │
                            │   [10] Upsert user, store refresh_token,         │
                            │        create session                            │
                            │      ┌────▼──────────────────────────────┐       │
                            │      │ Cloud SQL (PostgreSQL)            │       │
                            │      │ ─────────────────────────         │       │
                            │      │ INSERT INTO users (...)           │       │
                            │      │  ON CONFLICT (google_sub)         │       │
                            │      │  DO UPDATE SET last_login=NOW()   │       │
                            │      │ INSERT INTO refresh_tokens (...)  │       │
                            │      │ INSERT INTO sessions (            │       │
                            │      │   user_id, session_token,         │       │
                            │      │   expires_at = NOW() + 24h        │       │
                            │      │ )                                 │       │
                            │      │ INSERT INTO audit_log (           │       │
                            │      │   event=LOGIN_SUCCESS             │       │
                            │      │ )                                 │       │
                            │      └───────────────────────────────────┘       │
                            │           │                                      │
                            │   [11] Cache session in Redis for fast lookup    │
                            │      ┌────▼──────┐                               │
                            │      │ Redis     │                               │
                            │      │ SET sess: │                               │
                            │      │ abc123    │                               │
                            │      │ TTL=24h   │                               │
                            │      └────┬──────┘                               │
                            │           │                                      │
                            │   [12] Set-Cookie: session=abc123; HttpOnly;     │
                            │        Secure; SameSite=Lax                      │
                            │           │                                      │
                            │       302 Redirect → UI /dashboard               │
                            │           │                                      │
                            └───────────┼──────────────────────────────────────┘
                                        ▼
                                   ┌────────┐
                                   │  USER  │
                                   │Browser │
                                   │(logged │
                                   │  in)   │
                                   └────────┘
```

### Flow 2: Deploy Click Workflow Inside GCP

```
   ┌────────┐
   │  USER  │  Clicks "Deploy"
   │Browser │──── POST /api/deploy ─────┐
   └────────┘  (Cookie: session=abc123) │
                                        │
        ┌───────────────────────────────┼───────────────────────────────────────┐
        │                               ▼               GCP PROJECT             │
        │                  ┌───────────────────────┐                            │
        │                  │  Cloud Run: API       │                            │
        │                  │  POST /deploy         │                            │
        │                  └──────────┬────────────┘                            │
        │                             │                                         │
        │     [1] Validate session                                              │
        │              ┌──────────────▼──────────────┐                          │
        │              │  Redis (cache hit)          │                          │
        │              │  GET sess:abc123            │                          │
        │              │  → user_id, role            │                          │
        │              └──────────────┬──────────────┘                          │
        │                             │                                         │
        │     [2] (Cache miss?) Fall back to Cloud SQL                          │
        │              ┌──────────────▼──────────────┐                          │
        │              │  Cloud SQL                  │                          │
        │              │  SELECT * FROM sessions     │                          │
        │              │  WHERE token = 'abc123'     │                          │
        │              │   AND expires_at > NOW()    │                          │
        │              │   AND revoked = FALSE       │                          │
        │              └──────────────┬──────────────┘                          │
        │                             │                                         │
        │     [3] RBAC check: user.role IN ('admin', 'deployer')                │
        │                             │                                         │
        │     [4] Generate job_id (UUID), JWT id (jti)                          │
        │                             │                                         │
        │     [5] Fetch private signing key                                     │
        │              ┌──────────────▼──────────────┐                          │
        │              │  Secret Manager             │                          │
        │              │  GET projects/.../secrets/  │                          │
        │              │      jwt-signing-key/       │                          │
        │              │      versions/latest        │                          │
        │              │  → RSA private key (PEM)    │                          │
        │              └──────────────┬──────────────┘                          │
        │                             │                                         │
        │     [6] Mint JWT:                                                     │
        │         {                                                             │
        │           "iss": "https://api-xxx.run.app",                           │
        │           "sub": "user_id",                                           │
        │           "aud": "//iam.googleapis.com/.../wif/onprem",               │
        │           "iat": 1735689600,                                          │
        │           "exp": 1735689900,    ← 5 minute TTL                        │
        │           "jti": "uuid-v4",                                           │
        │           "job_id": "job-uuid",                                       │
        │           "user_email": "manu@example.com",                           │
        │           "role": "deployer"                                          │
        │         }                                                             │
        │         Signed with kid=key-2024-12-01, algorithm RS256               │
        │                             │                                         │
        │     [7] Persist job record                                            │
        │              ┌──────────────▼──────────────┐                          │
        │              │  Cloud SQL                  │                          │
        │              │  INSERT INTO deploy_jobs (  │                          │
        │              │    id=job-uuid,             │                          │
        │              │    user_id, jwt_jti,        │                          │
        │              │    status='pending',        │                          │
        │              │    jwt_expires_at,          │                          │
        │              │    repo_url, branch         │                          │
        │              │  )                          │                          │
        │              └──────────────┬──────────────┘                          │
        │                             │                                         │
        │     [8] Cache live job status in Redis                                │
        │              ┌──────────────▼──────────────┐                          │
        │              │  Redis                      │                          │
        │              │  SET job:job-uuid status=   │                          │
        │              │      'pending' TTL=1h       │                          │
        │              │  PUBLISH job-updates        │                          │
        │              └──────────────┬──────────────┘                          │
        │                             │                                         │
        │     [9] Publish to Pub/Sub trigger topic                              │
        │              ┌──────────────▼──────────────┐                          │
        │              │  Cloud Pub/Sub              │                          │
        │              │  topic: deploy-triggers     │                          │
        │              │  message: {                 │                          │
        │              │    job_id, jwt, repo_url,   │                          │
        │              │    branch, user_email       │                          │
        │              │  }                          │                          │
        │              └──────────────┬──────────────┘                          │
        │                             │                                         │
        │     [10] Audit log                                                    │
        │              ┌──────────────▼──────────────┐                          │
        │              │  Cloud SQL                  │                          │
        │              │  INSERT INTO audit_log (    │                          │
        │              │    event='DEPLOY_TRIGGERED',│                          │
        │              │    user_id, event_data={    │                          │
        │              │      job_id, jti, repo      │                          │
        │              │    }                        │                          │
        │              │  )                          │                          │
        │              └──────────────┬──────────────┘                          │
        │                             │                                         │
        │     [11] Return 202 Accepted + job_id to UI                           │
        │                             │                                         │
        │     UI opens SSE stream: GET /api/jobs/{job_id}/events                │
        │     API streams events from Redis pub/sub channel                     │
        │                             │                                         │
        │              ┌──────────────▼──────────────┐                          │
        │              │  Redis                      │                          │
        │              │  SUBSCRIBE job-updates      │                          │
        │              │  → forward to UI via SSE    │                          │
        │              └─────────────────────────────┘                          │
        │                                                                       │
        └───────────────────────────────────────────────────────────────────────┘

   Meanwhile, on the on-prem side:

   On-Prem Agent (AWS VM)
        │
        │ [a] PULL from Pub/Sub subscription (outbound)
        │ [b] Receive {job_id, jwt, repo_url}
        │ [c] Validate JWT structure locally
        │ [d] Exchange JWT for GCP access_token via Workload Identity Federation
        │     POST https://sts.googleapis.com/v1/token
        │ [e] git clone https://source.developers.google.com/...
        │     Authorization: Bearer <gcp-access-token>
        │ [f] Run ansible-pull -U /tmp/repo playbook.yml
        │ [g] Stream logs to Cloud Logging
        │
        └─→ API polls Cloud Logging / receives webhook from job ID
            Updates Redis: SET job:job-uuid status='succeeded'
            Redis publishes to job-updates channel
            UI receives SSE event, shows "Done"
```

### Storage Component Responsibilities

| Component | Stores | Why this storage choice |
|-----------|--------|------------------------|
| **Cloud SQL (PostgreSQL)** | Users, sessions, refresh tokens (encrypted), deploy jobs, audit log, signing key metadata | Relational, transactional, durable, queryable for reports |
| **Memorystore (Redis)** | Active session cache, OAuth state/PKCE verifiers, live job status, SSE pub/sub | TTL-native, microsecond latency, pub/sub for real-time UI |
| **Secret Manager** | RSA private signing key, OAuth client secret, DB password, encryption keys | Hardware-backed, audited per access, automatic versioning |
| **Cloud Pub/Sub** | Deploy trigger messages (transient queue) | Outbound-pull subscriber model, durable retry, DLQ support |
| **Cloud Logging** | All structured logs from UI, API, agent, audit events | Centralized, queryable, retention policies |
| **GCP Source Repo** | Ansible playbooks (git over HTTPS) | Native IAM, OIDC-authenticated git, version controlled |

> **Note on Redis**: For the initial MVP, Redis is optional — sessions and job status can live in Cloud SQL with cleanup jobs. Add Memorystore in Phase 7 (observability/scale) when traffic grows. The architecture supports both modes.

---

## 🔐 User Authentication Flow (Sequence Diagram)

```
┌──────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────────┐
│   USER   │    │   BROWSER    │    │  UI+API on GCP  │    │  Google      │
│ (human)  │    │  (Desktop)   │    │  (Next+FastAPI) │    │  OIDC IdP    │
└────┬─────┘    └──────┬───────┘    └────────┬────────┘    └──────┬───────┘
     │                 │                     │                    │
     │ 1. Open app URL │                     │                    │
     │────────────────>│                     │                    │
     │                 │                     │                    │
     │                 │ 2. GET /            │                    │
     │                 │────────────────────>│                    │
     │                 │                     │                    │
     │                 │ 3. 302 Redirect to Google OAuth          │
     │                 │   (client_id, redirect_uri, scope,       │
     │                 │    state, PKCE challenge)                │
     │                 │<────────────────────│                    │
     │                 │                     │                    │
     │                 │ 4. GET /authorize   │                    │
     │                 │──────────────────────────────────────── >│
     │                 │                     │                    │
     │ 5. Google login │                     │                    │
     │    page shown   │                     │                    │
     │<──────────────────────────────────────────────────────────│
     │                 │                     │                    │
     │ 6. Email + pwd  │                     │                    │
     │    + MFA        │                     │                    │
     │──────────────────────────────────────────────────────────>│
     │                 │                     │                    │
     │                 │                     │                    │ 7. Validate
     │                 │                     │                    │    + issue
     │                 │                     │                    │    auth_code
     │                 │                     │                    │
     │                 │ 8. 302 /callback?code=AUTH_CODE          │
     │                 │<──────────────────────────────────────── │
     │                 │                     │                    │
     │                 │ 9. GET /callback?code=...                │
     │                 │────────────────────>│                    │
     │                 │                     │                    │
     │                 │                     │ 10. Exchange code  │
     │                 │                     │   POST /token      │
     │                 │                     │   + code_verifier  │
     │                 │                     │───────────────────>│
     │                 │                     │                    │
     │                 │                     │ 11. Returns:       │
     │                 │                     │   - id_token       │
     │                 │                     │   - access_token   │
     │                 │                     │   - refresh_token  │
     │                 │                     │<───────────────────│
     │                 │                     │                    │
     │                 │                     │ 12. Validate JWT   │
     │                 │                     │   Upsert user in   │
     │                 │                     │   Cloud SQL        │
     │                 │                     │   Encrypt+store    │
     │                 │                     │   refresh_token    │
     │                 │                     │   Create session   │
     │                 │                     │                    │
     │                 │ 13. 200 OK + Set-Cookie: session=...     │
     │                 │<────────────────────│                    │
     │                 │                     │                    │
     │ 14. Dashboard   │                     │                    │
     │     visible     │                     │                    │
     │<────────────────│                     │                    │
     │                 │                     │                    │
     │  ════════════════════════════════════════════════════════  │
     │   USER IS NOW LOGGED IN — can click "Deploy" to trigger    │
     │   downstream machine-auth flow (see Deploy Flow below)     │
     │  ════════════════════════════════════════════════════════  │
```

---

## 🚀 Deploy Flow (User-Triggered, Machine Identity)

```
USER ──[click Deploy]──> UI ──[POST /deploy + session cookie]──> API
                                                                   │
                                                       [validate session in DB]
                                                       [check RBAC role]
                                                       [fetch RSA key from Secret Mgr]
                                                       [mint job-scoped JWT (5min TTL)]
                                                       [persist job in Cloud SQL]
                                                                   │
                                                                   ▼
                                                          Cloud Pub/Sub topic
                                                       {job_id, jwt, repo_url}
                                                                   │
                                                                   │ outbound subscription
                                                                   ▼
                                                              Go Agent (on-prem)
                                                                   │
                                              ┌────────────────────┤
                                              │                    │
                                              ▼                    ▼
                                    Exchange JWT       (on success)
                                    via GCP STS         git clone with token
                                              │                    │
                                              ▼                    ▼
                                    GCP access_token       GCP Source Repo
                                                                   │
                                                                   ▼
                                                         ansible-pull execute
                                                                   │
                                                                   ▼
                                                           Cloud Logging
                                                                   │
                                                                   ▼
                                                          UI shows result via SSE
```

---

## 🧰 Tech Stack

| Layer | Technology | Why this choice |
|-------|-----------|-----------------|
| **Frontend (UI)** | Next.js 14 (App Router) on Cloud Run | SSR + API routes, modern React, auto-HTTPS, recruiter-recognized |
| **Backend API** | Python 3.12 + FastAPI on Cloud Run | Pydantic validation, Authlib OIDC, auto OpenAPI docs, security defaults |
| **Database** | Cloud SQL (PostgreSQL 15) | Managed, automatic backups, point-in-time recovery, transactional |
| **Cache / Sessions** | Memorystore (Redis) — optional Phase 7 | TTL-native, microsecond reads, pub/sub for SSE |
| **Secrets** | Google Secret Manager | Hardware-backed, audited access, automatic versioning |
| **User Auth** | Google OIDC (OAuth 2.0 + PKCE) | Industry standard, MFA built in, zero infra |
| **Machine Auth** | Self-hosted JWKS + GCP Workload Identity Federation | Custom claims, key rotation control, keyless cross-cloud trust |
| **Trigger Bus** | Google Cloud Pub/Sub | Outbound-only subscriber model, durable, exactly-once |
| **Source Repo** | GCP Source Repositories | Native IAM, OIDC-authenticated git over HTTPS |
| **On-Prem Agent** | Go 1.22+ | Single static binary, low memory, production daemon-grade |
| **Configuration Mgmt** | Ansible (pull mode) | Declarative, idempotent, the de facto Linux automation tool |
| **Logging** | Google Cloud Logging | Centralized, structured JSON, queryable, retention |
| **On-Prem Simulation** | AWS EC2 (Linux, single VM) | Cross-cloud trust boundary; treated as pure Linux host |
| **TLS** | Google-managed (Cloud Run) | Auto-provisioned, auto-renewed, zero configuration |

---

## 🔑 Key Rotation Strategy (Self-Hosted JWKS)

The API acts as its own OIDC issuer for machine identity, with automated key rotation:

```
At any time, you have 1-2 active keys:
  • "primary" key — used to SIGN new JWTs
  • "secondary" key — still trusted for VERIFICATION (recently rotated out)

Both keys' public parts are exposed in /.well-known/jwks.json
so GCP can verify JWTs signed with either.

Rotation flow (every 30 days, automated via Cloud Scheduler):
  T+0:    Generate new key K2 in Secret Manager
  T+0:    Add K2 public key to jwt_signing_keys table (status=active)
  T+0:    K1 status → 'rotating' (still in JWKS, but no longer signs)
  T+0:    API starts signing all new JWTs with K2
  T+5m:   GCP refreshes its JWKS cache, sees both keys
  T+1h:   All JWTs signed with K1 have expired (TTL = 5 min)
  T+1d:   K1 status → 'retired', removed from JWKS endpoint
  T+1d:   K1 deleted from Secret Manager

Each JWT header includes "kid" so verifiers know which key to use.
```

This is exactly how Google, AWS, GitHub, and Auth0 implement key rotation.

---

## 🗄️ Database Schema (Cloud SQL — PostgreSQL)

```sql
-- USERS: Master record of human users
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_sub      VARCHAR(255) UNIQUE NOT NULL,
    email           VARCHAR(255) UNIQUE NOT NULL,
    name            VARCHAR(255),
    picture_url     TEXT,
    role            VARCHAR(50) NOT NULL DEFAULT 'viewer'
                    CHECK (role IN ('admin', 'deployer', 'viewer')),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ
);

-- SESSIONS: Active browser sessions
CREATE TABLE sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token   VARCHAR(64) UNIQUE NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address      INET,
    user_agent      TEXT,
    revoked         BOOLEAN NOT NULL DEFAULT FALSE
);

-- REFRESH_TOKENS: Encrypted at rest
CREATE TABLE refresh_tokens (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_token     BYTEA NOT NULL,
    encryption_key_id   VARCHAR(64) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at        TIMESTAMPTZ
);

-- DEPLOY_JOBS: Audit trail of every deploy
CREATE TABLE deploy_jobs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    repo_url            TEXT NOT NULL,
    branch              VARCHAR(255) NOT NULL DEFAULT 'main',
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','dispatched','running',
                                          'succeeded','failed','timeout')),
    jwt_jti             VARCHAR(64) NOT NULL UNIQUE,
    jwt_issued_at       TIMESTAMPTZ NOT NULL,
    jwt_expires_at      TIMESTAMPTZ NOT NULL,
    dispatched_at       TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    finished_at         TIMESTAMPTZ,
    exit_code           INTEGER,
    error_message       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- AUDIT_LOG: Every security-relevant action
CREATE TABLE audit_log (
    id              BIGSERIAL PRIMARY KEY,
    user_id         UUID REFERENCES users(id),
    event_type      VARCHAR(50) NOT NULL,
    event_data      JSONB,
    ip_address      INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- JWT_SIGNING_KEYS: Public part for JWKS (private parts in Secret Manager)
CREATE TABLE jwt_signing_keys (
    kid             VARCHAR(64) PRIMARY KEY,
    public_key_pem  TEXT NOT NULL,
    algorithm       VARCHAR(20) NOT NULL DEFAULT 'RS256',
    status          VARCHAR(20) NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'rotating', 'retired')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    activated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    retired_at      TIMESTAMPTZ
);
```

Full schema with indexes lives in `docs/db-schema.md`.

---

## 📋 Prerequisites

Before you begin, ensure you have:

- **GCP account** with billing enabled and an active project
- **AWS account** with permissions to create VPC + EC2 + NAT
- **`gcloud` CLI** ([install](https://cloud.google.com/sdk/docs/install))
- **`aws` CLI** ([install](https://aws.amazon.com/cli/))
- **`terraform`** ≥ 1.5 (for IaC) ([install](https://www.terraform.io/downloads))
- **Python** ≥ 3.12 + `uv` or `pip`
- **Node.js** ≥ 20 + `npm`
- **Go** ≥ 1.22
- **Docker** (for local container builds)
- **Git** + **GitHub account**
- **`psql`** (PostgreSQL CLI client)

**Estimated cost**: ~$25–30/month total (GCP ~$10, AWS ~$20 with NAT instance instead of NAT Gateway).

---

## 📁 Repository Structure

```
zero-trust-oidc-hybrid-deploy/
├── README.md                           # This file
├── LICENSE                             # Apache 2.0
├── .gitignore
├── docs/
│   ├── architecture.md                 # Detailed architecture rationale
│   ├── auth-flow.md                    # Deep dive on OIDC + WIF
│   ├── threat-model.md                 # STRIDE analysis
│   ├── key-rotation.md                 # Rotation strategy + runbook
│   └── db-schema.md                    # Full Cloud SQL schema
├── ui/                                 # Next.js 14 (Cloud Run)
│   ├── app/
│   │   ├── login/
│   │   ├── dashboard/
│   │   └── deploy/
│   ├── components/
│   ├── lib/
│   │   └── api-client.ts
│   ├── Dockerfile
│   └── package.json
├── api/                                # Python 3.12 + FastAPI (Cloud Run)
│   ├── app/
│   │   ├── main.py                     # FastAPI app entry
│   │   ├── auth/                       # Google OIDC integration
│   │   │   ├── google_oidc.py
│   │   │   ├── session.py
│   │   │   └── rbac.py
│   │   ├── jwks/                       # Self-hosted machine IdP
│   │   │   ├── keys.py                 # RSA key gen, rotation
│   │   │   ├── jwks_endpoint.py        # /.well-known/jwks.json
│   │   │   ├── discovery.py            # /.well-known/openid-configuration
│   │   │   └── token_minter.py         # Mint deploy JWTs
│   │   ├── users/                      # User management CRUD
│   │   │   ├── models.py
│   │   │   ├── routes.py
│   │   │   └── service.py
│   │   ├── deploy/                     # Deploy orchestration
│   │   │   ├── routes.py
│   │   │   ├── publisher.py            # Pub/Sub publisher
│   │   │   └── status.py               # SSE job status stream
│   │   ├── db/
│   │   │   ├── models.py               # SQLAlchemy ORM
│   │   │   ├── session.py              # DB session factory
│   │   │   └── migrations/             # Alembic migrations
│   │   └── core/
│   │       ├── config.py               # Settings via env
│   │       ├── secrets.py              # Secret Manager wrapper
│   │       └── logging.py              # Structured logging
│   ├── tests/
│   ├── Dockerfile
│   ├── pyproject.toml
│   └── requirements.txt
├── agent/                              # Go 1.22 (on-prem)
│   ├── cmd/agent/main.go
│   ├── internal/
│   │   ├── pubsub/                     # Subscriber logic
│   │   ├── jwt/                        # JWT validation + STS exchange
│   │   ├── git/                        # Repo pull
│   │   └── ansible/                    # ansible-pull invocation
│   ├── go.mod
│   └── Makefile
├── ansible/                            # Sample playbooks
│   ├── playbook.yml
│   ├── roles/
│   └── inventory/
├── infra/                              # Infrastructure as Code
│   ├── gcp/                            # Terraform
│   │   ├── cloud_run.tf
│   │   ├── cloud_sql.tf
│   │   ├── secret_manager.tf
│   │   ├── pubsub.tf
│   │   ├── workload_identity.tf
│   │   ├── source_repo.tf
│   │   ├── memorystore.tf              # Optional
│   │   └── iam.tf
│   └── aws/
│       ├── vpc.tf
│       ├── nat.tf
│       └── ec2.tf
└── scripts/
    ├── bootstrap-gcp.sh                # One-shot GCP setup
    ├── bootstrap-aws.sh                # One-shot AWS setup
    ├── install-agent.sh                # Install agent on on-prem VM
    └── rotate-keys.sh                  # Manual key rotation trigger
```

---

## 🛠️ Setup Instructions

> **Note**: Setup is broken into phases that build on each other. Complete them in order.

### Phase 1 — Architecture & Documentation ✅
You're reading it. Review `docs/architecture.md` for detailed design rationale.

### Phase 2 — UI + API Skeleton on Cloud Run
*Coming soon* — Next.js dashboard, FastAPI backend, deployed to Cloud Run.

### Phase 3 — Cloud SQL + User Management + Google OIDC
*Coming soon* — Postgres schema, user CRUD, Google login working end-to-end.

### Phase 4 — Self-Hosted JWKS + Key Rotation + Deploy Endpoint
*Coming soon* — RSA key generation, JWKS discovery, JWT minting, Cloud Scheduler rotation.

### Phase 5 — AWS VM + NAT + Pub/Sub + Workload Identity Federation
*Coming soon* — Provision EC2 in private subnet, configure WIF pool, wire up Pub/Sub.

### Phase 6 — Go Agent + JWT Exchange + Ansible Execution
*Coming soon* — Build the on-prem daemon that closes the loop.

### Phase 7 — Logging, Monitoring, Observability
*Coming soon* — Structured logs, dashboards, alerts.

### Phase 8 — Documentation & Threat Model
*Coming soon* — STRIDE analysis, runbooks, ADRs.

---

## 🔒 Security Highlights

This project implements multiple layers of zero-trust principles:

| Threat | Mitigation |
|--------|-----------|
| **Long-lived credentials on on-prem host** | Eliminated via Workload Identity Federation + job-scoped JWTs (max 5min TTL) |
| **Inbound attack surface on on-prem** | Zero — security group denies all inbound; only outbound 443 allowed |
| **Lateral movement from compromised cloud** | Limited — cloud cannot push to on-prem; on-prem pulls only when triggered |
| **Token replay** | PKCE on user flow; nonce + `jti` on machine flow; short TTL; `jti` tracked in DB |
| **Audit gap** | Every action logged in `audit_log` table + Cloud Logging |
| **Identity spoofing** | JWT signature validation at every hop; offline JWKS verification |
| **Privilege escalation** | RBAC enforced at UI (role check) AND at GCP (IAM on federated identity) |
| **Insecure deserialization** | All inter-service messages are signed JWTs, not raw JSON |
| **Refresh token theft** | Refresh tokens encrypted at rest with key from Secret Manager |
| **Session fixation** | Session tokens are random 256-bit, regenerated on login, HttpOnly cookies |
| **Signing key compromise** | Automated 30-day rotation; multi-key JWKS for grace period |
| **Database credential leak** | DB password in Secret Manager, not env vars; rotated quarterly |
| **TLS downgrade** | Cloud Run enforces HTTPS; HSTS headers on UI |
| **CSRF** | SameSite=Lax cookies; state parameter on OAuth flow |

---

## 🗺️ Roadmap

- [x] Phase 1: Architecture & README
- [ ] Phase 2: Next.js UI + FastAPI skeleton on Cloud Run
- [ ] Phase 3: Cloud SQL schema + user management + Google OIDC
- [ ] Phase 4: Self-hosted JWKS + key rotation + deploy endpoint
- [ ] Phase 5: AWS VM + NAT + Pub/Sub + Workload Identity Federation
- [ ] Phase 6: Go agent + Ansible pull execution
- [ ] Phase 7: Memorystore (Redis) integration + observability
- [ ] Phase 8: Documentation polish + threat model + ADRs
- [ ] Phase 9 (Future): Keycloak as alternative IdP (vendor-agnostic)
- [ ] Phase 10 (Future): WebSocket-based real-time deploy progress
- [ ] Phase 11 (Future): Multi-tenant RBAC via OIDC group claims
- [ ] Phase 12 (Future): SPIFFE/SPIRE-based autonomous machine identity
- [ ] Phase 13 (Future): Full Terraform modules for IaC reproducibility

---

## 📚 References & Further Reading

- [OAuth 2.0 Authorization Code Flow with PKCE — RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)
- [OpenID Connect Discovery 1.0](https://openid.net/specs/openid-connect-discovery-1_0.html)
- [JSON Web Key (JWK) — RFC 7517](https://datatracker.ietf.org/doc/html/rfc7517)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GCP Workload Identity Federation with OIDC](https://cloud.google.com/iam/docs/workload-identity-federation-with-other-providers)
- [SPIFFE — Secure Production Identity Framework For Everyone](https://spiffe.io/)
- [Ansible Pull Mode Documentation](https://docs.ansible.com/ansible/latest/cli/ansible-pull.html)
- [Google BeyondCorp — Zero Trust Whitepaper](https://cloud.google.com/beyondcorp)
- [FastAPI Security Documentation](https://fastapi.tiangolo.com/tutorial/security/)
- [Authlib — OAuth & OIDC for Python](https://docs.authlib.org/)

---

## 🤝 Contributing

This is a portfolio / learning project. Issues, PRs, and discussions are welcome.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-improvement`)
3. Commit your changes (`git commit -m 'Add amazing improvement'`)
4. Push to the branch (`git push origin feature/amazing-improvement`)
5. Open a Pull Request

---

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.

---

## 👤 Author

**Manu Anand**
GitHub: [@manupanand](https://github.com/manupanand)

> If this project helped you understand zero-trust hybrid deployments, please ⭐ star the repository.

---

## ⚖️ Disclaimer

This is a reference implementation intended for learning, demonstration, and portfolio purposes. While it follows production-grade patterns, deploying it as-is to a live environment requires additional hardening: rate limiting, WAF, formal threat model review, penetration testing, secret rotation policies, monitoring/alerting, and disaster recovery planning. Use at your own risk.
