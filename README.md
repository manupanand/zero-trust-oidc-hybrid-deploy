# Hybrid On-Prem ↔ Cloud OIDC Connect with Workload Identity (Zero-Trust Deployment Model)

> A production-grade reference implementation demonstrating how to securely deploy code from a cloud control plane (GCP) to on-premise infrastructure with **zero inbound connectivity, zero standing credentials, and zero VPN** — using OIDC, Workload Identity Federation, and pull-based Ansible automation.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GCP](https://img.shields.io/badge/Cloud-GCP-4285F4?logo=google-cloud&logoColor=white)](https://cloud.google.com)
[![Ansible](https://img.shields.io/badge/Automation-Ansible-EE0000?logo=ansible&logoColor=white)](https://www.ansible.com)
[![Go](https://img.shields.io/badge/Agent-Go-00ADD8?logo=go&logoColor=white)](https://go.dev)
[![Next.js](https://img.shields.io/badge/UI-Next.js-000000?logo=next.js&logoColor=white)](https://nextjs.org)

---

## 📌 Project Overview

This project simulates a real-world enterprise hybrid deployment scenario where a centralized cloud platform must securely deploy configuration and code to on-premise servers that have **no public IP, no inbound ports open, and no VPN connection** to the cloud.

It implements a modern **zero-trust deployment pattern** using:

- **OpenID Connect (OIDC)** for human and machine authentication
- **GCP Workload Identity Federation** for keyless cloud access
- **Pull-based Ansible automation** triggered by user actions in a web UI
- **Outbound-only network model** (HTTPS 443 only)
- **Job-scoped, short-lived tokens** — no long-lived credentials anywhere

This pattern is used in production by Google Anthos, AWS Systems Manager, Azure Arc, and HashiCorp Boundary.

---

## 🎯 Why This Project Matters

Traditional infrastructure automation tools (Ansible push, SSH-based deployment) require **inbound network access** to managed nodes — a non-starter for:

- **Compliance-regulated environments** (PCI-DSS, HIPAA, ISO 27001, SOC 2)
- **Air-gapped or segmented networks** (banking, healthcare, OT/ICS)
- **Multi-cloud or edge deployments** behind corporate NAT
- **Zero-trust architectures** where identity is the perimeter

This project demonstrates the modern alternative: **the on-prem server pulls from the cloud, authenticated via short-lived OIDC tokens issued only when a human authorizes a deploy.**

---

## 🏗️ System Architecture

```
                             ┌─────────────────────────────────────────────────────┐
                             │              GCP (Cloud Control Plane)              │
                             │                                                     │
                             │   ┌────────────────┐      ┌──────────────────────┐  │
                             │   │  Next.js UI    │      │   Express API        │  │
                             │   │  (User Login)  │◄────►│  (Auth + Deploy)     │  │
                             │   └────────────────┘      └──────────┬───────────┘  │
                             │                                      │              │
                             │   ┌────────────────────┐              │              │
                             │   │  Google OIDC IdP   │◄─────────────┤              │
                             │   │ (User auth)        │              │              │
                             │   └────────────────────┘              │              │
                             │                                      │              │
                             │   ┌────────────────────┐    ┌────────▼───────────┐  │
                             │   │  Workload Identity │    │   Cloud Pub/Sub    │  │
                             │   │  Federation Pool   │    │   (Trigger bus)    │  │
                             │   │  (Machine auth)    │    └────────┬───────────┘  │
                             │   └────────────────────┘             │              │
                             │                                      │              │
                             │   ┌────────────────────┐             │              │
                             │   │  Source Repository │             │              │
                             │   │  (Ansible code)    │             │              │
                             │   └─────────▲──────────┘             │              │
                             │             │                        │              │
                             └─────────────┼────────────────────────┼──────────────┘
                                           │                        │
                                           │ HTTPS 443              │ HTTPS 443
                                           │ (outbound git pull)    │ (outbound subscribe)
                                           │                        │
                       ╔═══════════════════╪════════════════════════╪══════════════╗
                       ║                NAT GATEWAY (one-way valve)                ║
                       ║         OUTBOUND ONLY — zero inbound to on-prem           ║
                       ╚═══════════════════╪════════════════════════╪══════════════╝
                                           │                        │
                             ┌─────────────┼────────────────────────┼──────────────┐
                             │             │   On-Prem (AWS EC2)    │              │
                             │             │                        │              │
                             │   ┌─────────┴────────────────────────▼───────────┐  │
                             │   │            Go Agent (systemd service)         │  │
                             │   │                                               │  │
                             │   │  1. Subscribe to Pub/Sub                      │  │
                             │   │  2. Receive deploy trigger + job-scoped JWT   │  │
                             │   │  3. git clone <repo> with token               │  │
                             │   │  4. Invoke ansible-pull                       │  │
                             │   │  5. Stream logs back to Cloud Logging         │  │
                             │   └───────────────────────────────────────────────┘  │
                             │                                                      │
                             │   Security Group: outbound 443 only, NO inbound     │
                             └──────────────────────────────────────────────────────┘
```

---

## 🔐 User Authentication Flow

```
┌──────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────────┐
│   USER   │    │   BROWSER    │    │  UI+API on GCP  │    │  Google      │
│ (human)  │    │  (Desktop)   │    │  (Next.js+Expr) │    │  OIDC IdP    │
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
     │                 │                     │ 11. Returns JWTs:  │
     │                 │                     │   - id_token       │
     │                 │                     │   - access_token   │
     │                 │                     │   - refresh_token  │
     │                 │                     │<───────────────────│
     │                 │                     │                    │
     │                 │                     │ 12. Validate JWT   │
     │                 │                     │   (signature,      │
     │                 │                     │    iss, aud, exp)  │
     │                 │                     │   Extract claims   │
     │                 │                     │                    │
     │                 │                     │ 13. Create session │
     │                 │                     │    (signed cookie) │
     │                 │                     │                    │
     │                 │ 14. 200 OK + Set-Cookie: session=...     │
     │                 │<────────────────────│                    │
     │                 │                     │                    │
     │ 15. Dashboard   │                     │                    │
     │     visible     │                     │                    │
     │<────────────────│                     │                    │
     │                 │                     │                    │
     │  ════════════════════════════════════════════════════════  │
     │   USER IS NOW LOGGED IN — can click "Deploy" to trigger    │
     │   downstream machine-auth flow (see Deploy Flow below)     │
     │  ════════════════════════════════════════════════════════  │
```

---

## 🚀 Deploy Flow (User-Triggered)

```
USER ──[click Deploy]──> UI ──[POST /deploy + session cookie]──> API
                                                                   │
                                                       [validate session]
                                                       [check RBAC role]
                                                       [mint job-scoped JWT]
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
                                    git clone with JWT     ansible-pull
                                              │                    │
                                              ▼                    ▼
                                    GCP Source Repo        Local execution
                                                                   │
                                                                   ▼
                                                           Cloud Logging
                                                                   │
                                                                   ▼
                                                          UI shows result via SSE
```

---

## 🧰 Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Frontend (UI)** | Next.js 14 (App Router) | SSR + API routes, modern React, recruiter-recognized |
| **Backend API** | Express.js (Node 20) | Lightweight, OIDC ecosystem mature, fast iteration |
| **User Auth** | Google OIDC (OAuth 2.0 + PKCE) | Industry standard, zero infra to manage |
| **Machine Auth** | GCP Workload Identity Federation | Keyless, short-lived, federated trust |
| **Trigger Bus** | Google Cloud Pub/Sub | Outbound-only subscriber model, durable |
| **Source Repo** | GCP Source Repositories (or GitHub) | Git over HTTPS, OIDC-authenticated |
| **On-Prem Agent** | Go 1.22+ | Single binary, low footprint, production-grade |
| **Configuration Mgmt** | Ansible (pull mode) | Declarative, idempotent, agentless on managed nodes |
| **Logging** | Google Cloud Logging | Centralized, structured, queryable |
| **On-Prem Simulation** | AWS EC2 (Linux) | Cross-cloud trust boundary; pure Linux host |

---

## 📋 Prerequisites

Before you begin, ensure you have:

- **GCP account** with billing enabled and an active project
- **AWS account** with permissions to create VPC + EC2 + NAT Gateway
- **`gcloud` CLI** ([install](https://cloud.google.com/sdk/docs/install))
- **`aws` CLI** ([install](https://aws.amazon.com/cli/))
- **`terraform`** ≥ 1.5 (optional, for IaC) ([install](https://www.terraform.io/downloads))
- **Node.js** ≥ 20 and **npm**
- **Go** ≥ 1.22
- **Git** + a **GitHub account**
- A registered domain (optional, for production-grade callback URLs — `localhost` works for dev)

**Estimated cost**: ~$1–2 per day to run the full stack (NAT Gateway is the main cost). Fits in GCP free tier for the cloud side.

---

## 📁 Repository Structure

```
zero-trust-oidc-hybrid-deploy/
├── README.md                       # This file
├── LICENSE                         # Apache 2.0
├── docs/
│   ├── architecture.md             # Detailed architecture rationale
│   ├── auth-flow.md                # Deep dive on OIDC + WIF
│   └── threat-model.md             # STRIDE analysis
├── ui/                             # Next.js frontend
│   ├── app/
│   ├── components/
│   ├── package.json
│   └── ...
├── api/                            # Express backend
│   ├── src/
│   │   ├── routes/
│   │   ├── auth/                   # OIDC handlers
│   │   ├── deploy/                 # Deploy endpoint + JWT minting
│   │   └── server.js
│   └── package.json
├── agent/                          # Go on-prem agent
│   ├── cmd/agent/main.go
│   ├── internal/
│   │   ├── pubsub/                 # Subscriber logic
│   │   ├── token/                  # JWT validation
│   │   ├── git/                    # Repo pull
│   │   └── ansible/                # ansible-pull invocation
│   ├── go.mod
│   └── Makefile
├── ansible/                        # Sample playbooks (pulled by agent)
│   ├── playbook.yml
│   ├── roles/
│   └── inventory/
├── infra/                          # Infrastructure as Code
│   ├── gcp/                        # Terraform: VPC, WIF pool, Pub/Sub, IAM
│   └── aws/                        # Terraform: VPC, NAT, EC2
└── scripts/
    ├── bootstrap-gcp.sh            # One-shot GCP setup
    ├── bootstrap-aws.sh            # One-shot AWS setup
    └── install-agent.sh            # Install agent on on-prem VM
```

---

## 🛠️ Setup Instructions

> **Note**: Setup is broken into 5 phases that build on each other. Complete them in order.

### Phase 1 — Architecture & Documentation ✅
You're reading it. Review `docs/architecture.md` for design rationale.

### Phase 2 — Build UI + API
*Coming soon* — see `ui/README.md` and `api/README.md` for local dev.

### Phase 3 — OIDC Configuration
*Coming soon* — see `docs/oidc-setup.md`.

### Phase 4 — Provision Infrastructure + Deploy Trigger
*Coming soon* — see `infra/README.md`.

### Phase 5 — On-Prem Agent + Ansible Execution
*Coming soon* — see `agent/README.md`.

---

## 🔒 Security Highlights

This project deliberately implements multiple layers of zero-trust principles. Key callouts for security review:

| Threat | Mitigation |
|--------|-----------|
| **Long-lived credentials on on-prem host** | Eliminated via Workload Identity Federation + job-scoped JWTs (max 1hr TTL) |
| **Inbound attack surface on on-prem** | Zero — security group denies all inbound; only outbound 443 allowed |
| **Lateral movement from compromised cloud** | Limited — cloud cannot push to on-prem; on-prem pulls only when triggered |
| **Token replay** | PKCE on user flow; nonce + `jti` on machine flow; short TTL |
| **Audit gap** | Every action logged: user login (Google), deploy click (API), token mint (API), repo pull (GCP), playbook run (Ansible → Cloud Logging) |
| **Identity spoofing** | JWT signature validation at every hop; offline JWKS verification |
| **Privilege escalation** | RBAC enforced at UI (role check) AND at GCP (IAM on federated identity) |
| **Insecure deserialization** | All inter-service messages are signed JWTs, not raw JSON payloads |

---

## 🗺️ Roadmap

- [x] Phase 1: Architecture & README
- [ ] Phase 2: Next.js UI + Express API skeleton
- [ ] Phase 3: Google OIDC integration
- [ ] Phase 4: AWS VM + GCP Workload Identity Federation + Pub/Sub trigger
- [ ] Phase 5: Go agent + Ansible pull execution
- [ ] Phase 6 (Future): WebSocket-based real-time deploy progress
- [ ] Phase 7 (Future): Multi-tenant RBAC via OIDC group claims
- [ ] Phase 8 (Future): SPIFFE/SPIRE-based autonomous machine identity (Pattern B)
- [ ] Phase 9 (Future): Keycloak as alternative IdP (vendor-agnostic)
- [ ] Phase 10 (Future): Terraform modules for full IaC reproducibility

---

## 📚 References & Further Reading

- [OAuth 2.0 Authorization Code Flow with PKCE — RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [SPIFFE — Secure Production Identity Framework For Everyone](https://spiffe.io/)
- [Ansible Pull Mode Documentation](https://docs.ansible.com/ansible/latest/cli/ansible-pull.html)
- [Google BeyondCorp — Zero Trust Whitepaper](https://cloud.google.com/beyondcorp)

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

This is a reference implementation intended for learning, demonstration, and portfolio purposes. While it follows production-grade patterns, deploying it as-is to a live environment requires additional hardening: TLS termination, rate limiting, secret rotation policies, monitoring, alerting, and a formal threat model review. Use at your own risk.