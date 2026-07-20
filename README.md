# PHI Auto-DR — Solution Package (index)

Enterprise auto-DR for Prudential Health India on GCP: **same-region dual-AZ** (`asia-south1`
az1 active / az2 warm). This folder is the complete analysis + solution + diagrams + config.

> **Start here → read in this order:** 1) this README 2) `phi-dr-architecture.drawio` (the architecture,
> self-contained) 3) `PHI-Auto-DR-Solution.md` (the write-up) 4) `dr-config/` (the actual changes).

---

## The solution in 6 lines
1. Put a **stable AZ-agnostic endpoint** (Internal L4 passthrough NLB, failover backend, health-checked) in
   front of every system's az1+az2 ingress — one name, no `az1`.
2. Keep **az2 warm** (HTTP min=1); **Pub/Sub consumers active-passive** (gated off until failover).
3. **Kill every `-az1-`** in config → stable name (cross-cluster) or K8s service name (same cluster).
4. **Repoint Apigee** target servers to the stable name.
5. Fix **az2 secrets/bugs**; add missing plumbing (Samvaad az2 VPC connector).
6. The stateful layer (Cloud SQL REGIONAL, Redis HA, Pub/Sub) **already auto-fails-over** → RTO **< 30s**,
   RPO **≈ 0**. Full-region loss = **Phase 2** (cross-region asia-south2).

**Every PHI system runs this same pattern** — roll it out to all systems together (IL → direct-az1 callers
Health App & Fyntune → downstream → Apigee channels), or the east-west mesh breaks.

---

## Files

### Diagrams (open in draw.io / diagrams.net)
| File | Pages | Use |
|---|---|---|
| **`phi-dr-architecture.drawio`** ⭐ | 1 Reference architecture · 2 Platform connectivity · 3 Reference info · 4 East-west before→after | The **architecture** view with real GCP/K8s icons. Self-contained — no doc needed. |
| `phi-system-connectivity.drawio` | 1 Connectivity (+issues&fixes) · 2 DR posture · 3 Issues & Fixes | The **problem** view: who calls whom, what breaks. |
| `phi-solution-connectivity.drawio` | 1 Target connectivity · 2 Per-system solution detail | The **solved** connectivity, per system. |
| `phi-auto-dr.drawio` | 1 Target architecture · 2 Failover sequence | The **failover mechanism** / timeline. |

### Documents
| File | Use |
|---|---|
| `PHI-Auto-DR-Solution.md` | Full solution write-up: the pattern, §7a all-systems coverage, §7b universal pattern + per-system table, RTO/RPO, guardrails, rollout. |
| `at.md` | **Source** — the DR technical reference (infra, configs, Pub/Sub topics, bugs) this analysis is built on. |

### Config (`dr-config/`) — the actual changes
| File | What |
|---|---|
| `1-stable-endpoint-internal-lb.tf` | Terraform: Internal L4 NLB + health check + failover backend + firewall + DNS (step ①). |
| `2-cloud-dns-failover.sh` | Alternative/shortcut: Cloud DNS failover routing (incl. zero-caller-change on legacy az1 names). |
| `3-warm-az2-and-apigee.md` | Warm az2 (step ②), Apigee repoint (④), Bug #1/#2 fixes (⑤). |
| `4-pilot-light-control-loop.yaml` | Optional: event-driven auto-scale if az2 must stay at 0 (Monitoring→Pub/Sub→Cloud Run). |
| `6-config-az-agnostic-rewrite.md` | The **east-west checklist** (step ③ / issue ④): every `-az1-` key → stable replacement, per system, + done-when test. |
| `7-change-map.md` | **Where to make the stable-link changes** — repo · file · layer (Terraform + service `.yml` + K8s manifests + Apigee), and why Terraform-only isn't enough. |

*(There is no file 5 — step ⑤ fixes live in `3-warm-az2-and-apigee.md`.)*

---

## The 10 issues → fixes (badges on the diagrams)
| # | Issue | Fix |
|---|---|---|
| ① | Direct `-az1-` callers bypassing Apigee (Health App, Fyntune) | call IL's **stable name** (or az1-failover-DNS shortcut) |
| ② | PAS az1-pinned + own cross-region DR (RTO 1h) | dual-AZ via pattern; 1h RTO = **region loss only** |
| ③ | Samvaad egress `vpc-connector-prd-az1` | **add az2 VPC connector** + stable |
| ④ | East-west `-az1-` config (`domainSuffix`, `filenet.baseUrl`, `pas.api.baseUrl`, `bancsHost`, `crm.simple.baseUrl`) | **THE RULE** — #1 fix (page 4 + `dr-config/6`) |
| ⑤ | Warming az2 = competing Pub/Sub consumer | **active-passive** (gate off; scale on failover) |
| ⑥ | FileNet DB2-on-VM + on-prem AD (DSG001/002) SPOF | own HA/DR (out of GKE-AZ scope) |
| ⑦ | Apigee target servers all `-az1-` | repoint all 17 to stable |
| ⑧ | Bug#1 PPMC `application-dr.yml`→UAT · Bug#2 missing mTLS cert | fix **before** warming az2 |
| ⑨ | Zone-vs-region confusion | `az2` = zone in asia-south1 (Mumbai); `asia-south2` = Delhi region |
| ⑩ | Coordination | roll the pattern out to **all systems together** |

---

## Per-system status (grounded in the 14 LLDs)
| System | Project | az1+az2 | Reaches IL via | Fix steps |
|---|---|---|---|---|
| Integration Layer | chbb3e | ✅ | hub | ①②③④⑤ |
| PAS / TCS BaNCS | vpkcai | ✅ | direct | ①②③ (RTO 1h region-only) |
| FileNet/BAW/ODM | nhq8h1 | ✅ | direct | ①③ (+ own HA for DB2/AD) |
| SimpleCRM | rzg0c4 | ✅ | Apigee | ①②③④ |
| Samvaad | f950ic | ✅ | Apigee + egress | ①③⑤ (add az2 connector) |
| CHUB / Comms | — | ✅ | Pub/Sub + REST | ①②③ |
| PIXEL / DocDigit | dp1d50 | ✅ | via IL | ①③ |
| PruServices | aa8b68 | ✅ | Apigee | ④ |
| Buy-Online / D2C / Corp | yoh0kt | ✅ | Apigee | ④ |
| Health App | rzg0c4 | ✅ | Apigee + **direct az1** | ①③ |
| **Fyntune** (distributed) | own | ✅ | **direct az1 (bypasses Apigee)** | ①③ + ②④⑤ |

**RTO/RPO:** zone loss → **< 30s / ≈ 0** (automatic). Region loss → Phase 2 (cross-region asia-south2).
