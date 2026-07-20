# PHI Auto-DR — Enterprise Solution Design
### Transparent, automatic, same-region (dual-AZ) DR on GCP with minimal configuration

**Version:** 1.0 · **Date:** 2026-07-19 · **Scope:** `asia-south1`, AZ1 (primary) ↔ AZ2 (standby)
**Companion:** `phi-auto-dr.drawio` (architecture + failover-sequence diagrams)

---

## 1. Executive summary

PHI's DR problem is **not** "how do we replicate data" — the stateful layer already auto-heals across zones (Cloud SQL `REGIONAL`, Redis `STANDARD_HA`, Pub/Sub global). The problem is **the request path**:

1. Services are published on **AZ-pinned hostnames** (`…-az1-…` vs `…-az2-…`), so every caller is *AZ-aware*.
2. **Not all callers come through Apigee** — other components call the **AZ1 URL directly**, so an Apigee-only failover does not rescue them.
3. **AZ2 pods are not running**, so failover today needs a **manual start** → long outage for whoever is calling.

**Recommended solution (minimal, fully automatic):**

> **(A) Put one stable, AZ-agnostic endpoint with health-based failover in front of both AZ ingresses**, so *every* caller (Apigee, other internal components, external partners) uses one URL that silently moves AZ1→AZ2; **and (B) keep AZ2 warm-minimal (1 replica of the critical services)** so the failover target is always alive.

Result: on AZ1 failure, **no URL change, no manual restart, no human** — traffic moves to already-warm AZ2 in **< 30 seconds**, while Cloud SQL/Redis/Pub/Sub have already failed over underneath. RPO ≈ 0.

---

## 2. What already survives (no action needed)

| Component | Mechanism | Behaviour on AZ1 loss |
|---|---|---|
| Cloud SQL `platform-domain-prod` | `REGIONAL` HA (sync standby) | Auto zone-failover, **RPO ≈ 0**, RTO 2–5 min |
| Redis `platform-domain-prod` | `STANDARD_HA` | Auto zone-failover, < 1 min (cache) |
| Pub/Sub (all `prod-*` topics) | Global / zone-agnostic | Unaffected |
| Apigee engine (`apigee-instance-as1`) | Single-region, zone-agnostic | Unaffected |
| IAM Workload Identity (DR namespace) | Pre-bound `platform-domain-prd-dr` | Ready |
| AZ2 firewall rules | Pre-provisioned | Ready |

**Therefore auto-DR only has to solve two things: (1) routing, (2) compute readiness.**

---

## 3. Root cause & the three pains it creates

The single root cause is the **AZ-pinned endpoint**:

```
service.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia   ← callers hardcode the AZ
service.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia   ← different name = manual switch
```

| Pain | Cause | Fix (this design) |
|---|---|---|
| Manual AZ2 start | AZ2 pods at 0 | **Warm-minimal AZ2** (§5) |
| Direct (non-Apigee) callers break | They hold the `az1` name; no failover in front | **Stable failover endpoint** (§4) |
| Apigee callers wait on manual restart | Fallback target (AZ2) is cold | Stable endpoint **+** warm AZ2 |

---

## 4. Piece 1 — Stable, AZ-agnostic endpoint with health-based failover

Insert one health-checked failover layer **in front of both AZ nginx-ingress controllers**, published on an **AZ-neutral name**:

```
service.lb1-pruinhlth-prd-chbb3e.pru.intranet.asia        ← NEW: no az1/az2
        │  (health-checked failover)
        ├── primary  → AZ1 nginx-ingress   (active)
        └── failover → AZ2 nginx-ingress   (warm standby)
```

Every caller — **Apigee target servers, other internal components, external partners** — points here once. **DR needs zero routing changes ever.**

### 4.1 Options (pick one)

| Option | What | Failover | When to choose |
|---|---|---|---|
| **A. Regional Internal Passthrough NLB (L4/TCP 443) with a failover backend** — *recommended* | One VIP; primary backend = AZ1 ingress, failover = AZ2; TLS passes through | Connection-level, instant, no DNS caching issue | Regulated / strict RTO |
| **B. Cloud DNS failover routing policy** | Stable A-record, health-checked: primary AZ1 IP, backup AZ2 IP | Auto on health fail (subject to TTL) | Absolute minimal infra |

> **Why L4 passthrough (Option A):** your nginx-ingress already terminates TLS per AZ; an L4 internal LB just steers TCP:443 to the healthy ingress — no cert handling in the LB, native **failover backend** support, no DNS-cache lag.

### 4.2 Zero-coordination shortcut (you can't easily change other teams)

You own the `pru.intranet.asia` zone. So the fastest path that needs **nothing from external callers**:

> Convert the **existing `…-az1-…` records into health-checked failover records** (primary → AZ1 ingress IP, backup → AZ2 ingress IP), TTL 30–60s.

Then components with `…-az1-…` **hardcoded fail over automatically** — no code change on their side. It's a naming compromise ("az1" serves az2 during DR); long-term migrate everyone to the clean AZ-neutral name.

### 4.3 Illustrative config

**Option A — regional internal passthrough NLB with failover backend (Terraform sketch, adapt to `pruinhlth-prod-prd-chbb3e`):**
```hcl
resource "google_compute_region_health_check" "ingress" {
  name = "phi-ingress-hc"; region = "asia-south1"
  https_health_check { port = 443; request_path = "/healthz" }   # nginx-ingress healthz
  check_interval_sec = 5; timeout_sec = 5; healthy_threshold = 2; unhealthy_threshold = 2
}
resource "google_compute_region_backend_service" "ingress" {
  name = "phi-ingress-bes"; region = "asia-south1"
  protocol = "TCP"; load_balancing_scheme = "INTERNAL"
  health_checks = [google_compute_region_health_check.ingress.id]
  failover_policy { disable_connection_drain_on_failover = false; drop_traffic_if_unhealthy = false; failover_ratio = 1.0 }
  backend { group = var.az1_ingress_neg }                         # PRIMARY (AZ1)
  backend { group = var.az2_ingress_neg; failover = true }        # FAILOVER (AZ2)
}
# + internal forwarding rule (VIP) on 443 → Cloud DNS A record: *.lb1-pruinhlth-prd-chbb3e...
```

**Option B — Cloud DNS failover (illustrative):**
```bash
gcloud dns record-sets create "svc.lb1-pruinhlth-prd-chbb3e.pru.intranet.asia." \
  --zone=<internal-zone> --type=A --ttl=30 \
  --routing-policy-type=FAILOVER \
  --routing-policy-primary-data=<AZ1_ingress_ILB_forwarding_rule> \
  --enable-health-checking
# backup target = AZ2 ingress; health check tied to the AZ1 internal LB
```

---

## 5. Piece 2 — Warm-minimal AZ2 (so failover has somewhere alive to land)

A failover endpoint is useless if the backup is cold. Run AZ2 **warm-minimal**: 1 replica of the critical-path services; HPA scales up under real load.

**Critical set (warm, min=1):** `claim-processing`, `pas`, `ppmc`, `crm`, `policy-management`, `payment`.
**Everything else:** pilot-light (0) is fine if the endpoint fails over only to warm services — or warm at min=1 too (cost is small).

```yaml
# AZ2 (namespace platform-domain-prd-dr) — per critical Deployment
spec:
  replicas: 1                       # was effectively 0
  # HPA unchanged (1→N). Resource requests can be trimmed for standby.
```

> This is the single setting that removes **all** manual restart. AZ2 is always a healthy failover target; HPA absorbs real load after cutover.

**If warm cost is unacceptable → pilot-light + control loop (§8).**

---

## 6. Repoint Apigee at the stable name (so Apigee also "just works")

In `phi-7wd-apigee-proxies-main/environments/pruinhlth-prd/targetservers.json`, change the AZ1-pinned hosts to the **stable** host:

```diff
- "host": "ppmc-api.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia"
+ "host": "ppmc-api.lb1-pruinhlth-prd-chbb3e.pru.intranet.asia"     # AZ-agnostic
```

With the stable endpoint doing failover, you **no longer need per-AZ Apigee target servers or `IsFallback` XML, and no DR-time `target-server-deploy` run.** (The Apigee LB-fallback from the original doc becomes a redundant, secondary safety net — optional.)

---

## 7. Failover sequence (what happens automatically)

**Normal:** stable endpoint health-checks AZ1 = healthy → all callers (Apigee + direct) → AZ1 pods. AZ2 warm at 1 replica.

**AZ1 fails:**
1. Cloud SQL/Redis auto-fail-over to the surviving zone (RPO ≈ 0) — seconds.
2. Stable endpoint health check marks AZ1 unhealthy (2 fails × 5s ≈ 10s).
3. Endpoint steers **all** traffic → **AZ2 ingress** → warm AZ2 pods (no restart).
4. HPA scales AZ2 up to real load. Pub/Sub subscriptions continue (shared `prod-*`).
5. **Apigee callers, direct callers, external partners: unchanged URL, ≈ 20–30s blip.**

**AZ1 recovers:** health check passes for the stable window → endpoint reverts to AZ1 primary; AZ2 returns to warm (or 0). Cooldown prevents flapping.

---

## 7a. Coverage across ALL systems (grounded in the 14 LLDs)

> Companion diagram: **`phi-system-connectivity.drawio`** — page 1 connectivity (colour = transport), page 2 DR posture, page 3 issues & fixes.

The front-door failover covers everything reaching IL **through Apigee** plus the inbound HTTP surface. A review of the source LLDs corrected several earlier assumptions:

| Correction | What the LLD actually says |
|---|---|
| **Buy-Online calls IL via Apigee, not a direct az1 link** | DCPHIL-131: *"NestJS BFF → Integration Layer (IL APIs via Apigee)."* Already zone-agnostic. |
| **The real direct-az1 caller is the Health App** | DCPHIL-137 hard-codes `healthapp-…-az1-…pru.intranet.asia` and calls `comms-svc-…` / `party-management-…` directly. Strongest case for the stable endpoint. |
| **FileNet (`nhq8h1`) and SimpleCRM (`rzg0c4`) DO have az1+az2** | Paired firewall rules per zone. Not all cross-project systems lack AZ2. |
| **PAS (`vpkcai`) and Samvaad (`f950ic`) are az1-only** | PAS shows only az1; Samvaad egress is `vpc-connector-prd-az1` only. The genuine single-AZ gaps. |
| **PAS owns its own DR** | DCPHIL-8: cross-region asia-south2, **RTO 1h / RPO 2h** — the ceiling for BaNCS-dependent flows. |
| **Every LLD documents cross-region (asia-south2) DR; none documents same-region dual-AZ** | This dual-AZ auto-DR is a deliberate departure — reconcile it in the DR narrative/BCM sign-off. |
| **Non-GKE single points of failure** | FileNet depends on **DB2 on a VM** + **on-prem AD (DSG001/002)** — outside GKE AZ failover; needs its own HA/DR. |

**Zone vs region — clarify everywhere:** `az2` is a **zone inside asia-south1 (Mumbai)**; **asia-south2 is the Delhi region**. Several docs conflate them (e.g. an ops note calling `az2` "Delhi"). This solution is **zone** DR; region DR is Phase 2 (§13).

**Traffic-type coverage:** callers via **Apigee** (D2C/47, Corp/144, Buy-Online/131, PruServices/125, WhatsApp→Samvaad) are DR-safe on the IL hop — just repoint Apigee targets. **Direct-az1** paths (Health App ingress + `comms-svc`/`party-management`; **Fyntune**) need the stable endpoint. **Pub/Sub** consumers (CHUB documented; CRM/PPMC in infra) → active-passive (gate consumer off on warm AZ2; scale on failover).

---

## 7b. DR as a UNIVERSAL pattern (every system, not just IL)

**Key fact:** *every* PHI system runs the same active-passive dual-AZ DR as IL — az1 active, az2 provisioned-but-cold, stateful layer auto-failing-over (confirmed uniform, including PAS `vpkcai` and Samvaad `f950ic`; Samvaad still needs an az2 VPC connector added). The platform is therefore a **mesh of identical dual-AZ systems that call each other by az1-pinned hostnames** — so DR only works if **all systems adopt the pattern together** (partial rollout breaks the east-west mesh — issue ⑩).

> Companion diagram: **`phi-dr-solution.drawio`** — page 1 universal pattern, page 2 platform mesh, page 3 per-system solution table.

**The 5-step template (apply identically to each system):**
1. **Stable AZ-agnostic endpoint** (regional internal L4 passthrough NLB, failover backend) over the system's az1+az2 ingress; health-check a real readiness path.
2. **Warm az2** for HTTP (min=1); **Pub/Sub consumers active-passive** (gate off on warm az2; scale on failover).
3. **Rewrite every `-az1-`** in config → stable name (cross-system) or K8s service name (same cluster). **THE RULE.** Two cases: **same GKE cluster** → K8s service name `http://<svc>` (in-cluster DNS, AZ-agnostic — already true for `payment-service`, `domain-graph`, `tpa-partner`); **cross-cluster / cross-project** → the target system's **stable NLB endpoint** (`…lb1-pruinhlth-prd-<proj>…`, no az1). See `phi-dr-architecture.drawio` page 4 (before → after) and `dr-config/6-config-az-agnostic-rewrite.md`.
4. **Repoint Apigee target servers** to the stable name.
5. **Fix az2 secrets/bugs**; add missing az2 plumbing (e.g. Samvaad az2 VPC connector).

**Per-system solution:**

| System | Project | az1+az2 | Reached via | `-az1-` deps to rewrite | Pub/Sub | Steps | Special note |
|---|---|---|---|---|---|---|---|
| Integration Layer | chbb3e | ✅ | hub (Apigee + direct) | `domainSuffix`, `filenet.baseUrl`, `pas.api.baseUrl` | pub+consume | ①②③④⑤ | the hub — do first |
| PAS / TCS BaNCS | vpkcai | ✅ | IL → direct | `bancsHost` | no | ①②③ | zone-DR via pattern; **cross-region RTO 1h = region-loss only** |
| FileNet/BAW/ODM | nhq8h1 | ✅ | IL → direct | `cp4ba`/`filenet` host | no | ①③ | **DB2-on-VM + on-prem AD SPOF → own HA/DR** |
| SimpleCRM | rzg0c4 | ✅ | Apigee; IL → CRM | `crm.simple.baseUrl` (`-az1-rzg0c4`) | consumer | ①②③④ | Pub/Sub consumer → active-passive |
| Samvaad | f950ic | ✅ | Apigee in; egress out | egress `*.pru.intranet.asia` | no | ①③⑤ | **add az2 VPC connector** (only az1 today) |
| CHUB / Comms | — | ✅ | Pub/Sub + REST | REST host | consumer | ①②③ | active-passive consumer |
| PIXEL / DocDigit | dp1d50 | ✅ | via IL | egress via VPC connector | no | ①③ | fix az2=zone label; check az2 connector |
| PruServices | aa8b68 | ✅ | Apigee | (minimal) | pub | ④ | repoint Apigee targets → stable |
| Buy-Online | yoh0kt | ✅ | Apigee (IL APIs) | none (via Apigee) | no | ④ | already zone-safe on IL hop |
| D2C + Corp sites | yoh0kt | ✅ | Apigee | none (via Apigee) | no | ④ | already zone-safe on IL hop |
| Health App | rzg0c4 | ✅ | Apigee + **DIRECT az1** | own ingress + `comms-svc` + `party-management` | no | ①③ | **direct-az1 caller → must use stable name** |
| **Fyntune** (distributed) | own proj | ✅ | **DIRECT az1 → IL (NOT Apigee)** | IL az1 link it calls + its own `-az1-` deps | ? | ①③ + full ②④⑤ | **2nd direct-az1 caller**: point at IL's stable name; + its own dual-AZ template |

**Issue ⑩ — coordinated rollout:** because the whole mesh talks via az1 hostnames, treat this as **one platform program** — a single stable-endpoint naming convention and template applied to every system, sequenced hub-first (IL), then the direct-az1 callers (Health App, Fyntune), then the rest.

---

## 8. Optional — pilot-light control loop (only if AZ2 must stay at 0)

All GCP-native, all tools already in use:
```
Cloud Monitoring uptime checks (AZ1 /actuator/health) + alert (dampened)
  → Pub/Sub topic  prod-dr-control
  → Cloud Workflows / Cloud Run job:
       1. confirm AZ1 down (2 independent signals)
       2. scale AZ2 deployments up (GKE API via pre-bound DR Workload Identity)
       3. wait for AZ2 readiness
       4. endpoint already routes there → done
       5. audit log + notify
  → auto-failback when AZ1 healthy (with cooldown)
```
Trade-off: RTO 3–5 min (pod cold-start) vs near-zero idle cost. **Warm-minimal (§5) is simpler and safer; prefer it for the money/claims path.**

---

## 9. Fix these bugs first (DR silently fails otherwise)

| # | Sev | Fix |
|---|---|---|
| **1** | HIGH | `application-dr.yml` → UAT. **Delete the `dr` profile entirely**; run AZ2 on `prod` (as CRM already does). Removes an entire class of DR drift. |
| **2** | MED | claim-processing DR yaml has `ORGANIZATION_CERT_BASE64` commented out → **uncomment** (`secretKeyRef: sahi-certificates/ssl-cert`) or mTLS to TPA fails in DR. |
| **3** | — | With the stable endpoint (§4) you no longer need AZ2 Apigee target servers; if you keep Apigee-level fallback instead of §4, then this (add AZ2 targets + `IsFallback`) is mandatory. |

---

## 10. Structural rule that prevents DR drift forever

**Make AZ2 config identical to prod via AZ-agnostic addressing.** Wherever a service hardcodes `…-az1-…` (`PPMC domainSuffix`, `filenet.baseUrl`, `PAS bancsHost`), that's a DR landmine. Standardize:
- intra-platform calls → **K8s service names** (already done for `http://payment-service`, `http://domain-graph`, `http://tpa-partner`);
- cross-boundary calls → the **stable endpoint / Apigee gateway**.

Then AZ2 pods run the **same prod manifest** — Bug #1 can never recur.

---

## 11. RTO / RPO

| Scenario | RTO | RPO | Automatic |
|---|---|---|---|
| Zone (AZ1) loss — stable endpoint + warm AZ2 | **< 30 s** | **≈ 0** | ✅ zero-touch |
| Zone loss — pilot-light + control loop | 3–5 min | ≈ 0 | ✅ |
| **Full `asia-south1` region loss** | *not covered* | — | ❌ → §13 |

---

## 12. Enterprise guardrails (regulated / IRDAI)

- **Dampening + multi-signal** health detection (no failover on a blip).
- **Cooldown / circuit-breaker** before failback (no flapping / split-brain).
- **Manual kill-switch / override** — ops can force or abort.
- **Immutable audit trail** (Cloud Logging) of every failover/failback.
- **DR drills as code** — scheduled game-day that fails over in a controlled window and validates health/mTLS/Pub/Sub → your BCP evidence.

---

## 13. Phase 2 — the real gap: cross-region

Same-region dual-AZ does **not** survive a full `asia-south1` outage (data unavailable). For a regulated health insurer this is a genuine BCP exposure. Enabler is already stubbed in Terraform:

> **Uncomment the Cloud SQL cross-region read replica to `asia-south2-a`**, extend the stable-endpoint concept to a second region, and pre-provision AZ pools there. Separate, funded phase.

---

## 14. Rollout plan

| Phase | Work | Outcome |
|---|---|---|
| 0 | Fix Bug #1 (drop `dr` profile), Bug #2 (mTLS cert); standardize AZ-agnostic config (§10) | Clean, prod-identical AZ2 |
| 1 | Stand up the **stable failover endpoint** (§4, Option A) on a couple of services; validate | Transparent routing proven |
| 2 | Set critical AZ2 deployments **min=1** (§5); repoint Apigee + a pilot direct-caller to stable name | Zero-touch failover for pilot |
| 3 | Roll stable name across all services; migrate remaining direct callers (or use the §4.2 shortcut) | Full auto-DR, no manual action |
| 4 | Add guardrails + **DR-drill-as-code** (§12); optional control loop (§8) if any service stays at 0 | Audited, tested, regulator-ready |
| 5 | **Cross-region** (§13) | Region-level BCP |

---

## Assumptions
- Direct callers resolve you via **intranet DNS you control** (`*.pru.intranet.asia`) — enables §4.2.
- **Warm-minimal AZ2** (≈6 small always-on pods) is acceptable; if not, use §8.
- nginx-ingress exposes a health path (e.g. `/healthz`) for the LB/DNS health check.
- Terraform/gcloud snippets are **illustrative** — adapt to the `pruinhlth-prod-prd-chbb3e` repo conventions.

**Document End · v1.0 · 2026-07-19**
