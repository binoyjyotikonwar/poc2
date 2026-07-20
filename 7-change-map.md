# Change Map — where to make the stable-link changes (repo · file · layer)

**Question answered:** the stable-link fix is **NOT Terraform-only.** It spans **4 layers**. Terraform only
*creates* the endpoint; the service `.yml` + K8s manifests make services *use* it and *be reachable by* it;
Apigee repoints external callers. (Grounded in the repo names from `at.md`.)

## Summary

| Layer | Repo | File(s) | Makes the stable link… | Step |
|---|---|---|---|---|
| **1. Terraform** | `pruinhlth-prod-prd-chbb3e` | `*.tf` (LB/DNS/firewall) | …**EXIST & fail over** | ① |
| **2. Service config** | each `phi-7wd-*-service` | `application-*.yml`, `application-*-dr.yml` | …**USABLE** (rewrite `-az1-` deps) | ③ (+Bug#1) |
| **2. K8s manifests** | each `phi-7wd-*-service` | Helm / Deployment / Service / Ingress yaml | …**REACHABLE** (NEG + stable Host + warm az2) | ②③⑤ (+Bug#2) |
| **3. Apigee proxies** | `phi-7wd-apigee-proxies-main` | `environments/pruinhlth-prd/targetservers.json` | …**used by external/channel callers** | ④ |
| **4. Pilot-light (optional)** | infra repo | Monitoring + Workflows | …auto-scale az2 (only if az2 stays at 0) | — |

> ⚠️ **If you do ONLY Terraform:** the stable name resolves and fails over, **but** (a) services still call
> each other on `-az1-` → **east-west breaks**, and (b) nginx-ingress returns its default 404 because it was
> never told to answer the new Host. You need layers 2 and 3 too.

---

## 1. Terraform — repo `pruinhlth-prod-prd-chbb3e`  (creates the stable endpoint)
Add (see `dr-config/1-stable-endpoint-internal-lb.tf`):
- `google_compute_region_health_check` — HTTPS :443 `/actuator/health/readiness`, 5s, unhealthy=2
- `google_compute_region_backend_service` — `INTERNAL`/TCP, **failover_policy**, az1 backend (primary) + az2 backend (`failover=true`)
- `google_compute_forwarding_rule` — internal VIP :443
- `google_compute_firewall` — allow health-check ranges `35.191.0.0/16`, `130.211.0.0/22` on 443
- `google_dns_record_set` — `*.lb1-pruinhlth-prd-chbb3e.pru.intranet.asia` → VIP
**Result:** the stable name exists, is health-checked, and fails az1→az2 automatically.

## 2. Service repos — `phi-7wd-ppmc-service-main` · `phi-7wd-crm-service` · `phi-7wd-pas-service-main` · `phi-7wd-claim-processing-main`

### 2a. Service config — YES, the `.yml` files change  (step ③, issue ④)
In `application-prod.yml` (and fix/remove `application-*-dr.yml`), rewrite every `-az1-` dependency hostname
→ stable name (cross-cluster) or K8s service name (same cluster). Full list in `dr-config/6-config-az-agnostic-rewrite.md`:
```yaml
# BEFORE → AFTER
domainSuffix     : lb1-pruinhlth-prd-az1-chbb3e…   →  lb1-pruinhlth-prd-chbb3e…
filenet.baseUrl  : …-az1-chbb3e…                    →  …-chbb3e…
pas.api.baseUrl  : …-az1-chbb3e…                    →  …-chbb3e…
bancsHost        : core-prod.…-az1-vpkcai…          →  core-prod.…-vpkcai…
crm.simple.baseUrl: crm-prod.…-az1-rzg0c4…          →  crm-prod.…-rzg0c4…
# KEEP (already AZ-safe, same cluster):
payment.gateway.url : http://payment-service
document.base-url   : http://document-api
```
**Bug #1 (do here):** `application-dr.yml` points at UAT (`pruinhlth-nprd-uat-f8hev4-3c6b`, `topicPrefix: dr`).
Fix: **delete the `dr` profile** and run az2 on `prod` (CRM already does this), else warm az2 writes prod
Pub/Sub messages to UAT.

### 2b. K8s / Helm manifests (same repos)  (steps ② ③ ⑤)
- **NEG annotation** on the nginx-ingress **Service** (so the Terraform NLB can target it):
  `cloud.google.com/neg: '{"exposed_ports": {"443": {"name": "<svc>-ingress-neg"}}}'`
- **Stable Host** on the **Ingress** — add to BOTH `spec.rules[].host` **and** `spec.tls[].hosts` (SNI), in az1 and az2
- **az2 Deployment** `replicas: 1` (warm)  ·  Pub/Sub consumer gated off until failover
- **Bug #2 (do here):** uncomment `ORGANIZATION_CERT_BASE64` in the claim-processing DR deployment yaml
  (`secretKeyRef: sahi-certificates / ssl-cert`), else mTLS to TPA fails in DR
**Result:** services call peers by stable/K8s name (survives az1 loss), nginx answers the stable Host, and
az2 is a live failover target.

## 3. Apigee proxies — repo `phi-7wd-apigee-proxies-main`  (step ④)
`environments/pruinhlth-prd/targetservers.json` — repoint all **17** internal target hosts from `-az1-` →
stable (drop the `-az1-` token). Deploy via the existing `target-server-deploy.yml`. External-partner
targets (mediassist, medibuddy, …) are unchanged.
**Result:** channel apps and 3rd-party callbacks reach services via the stable name (through Apigee).

## 4. Optional — pilot-light control loop (only if az2 stays at 0)
Cloud Monitoring uptime check → Pub/Sub → Cloud Workflows to scale az2 on failure. See
`dr-config/4-pilot-light-control-loop.yaml`. Skip if using warm az2 (recommended).

---

## Do-this-order (per system, hub first)
1. Terraform (layer 1) → stand up the stable endpoint.
2. K8s manifests (2b) → NEG + stable Host + warm az2 (nginx now answers the stable name).
3. Service config (2a) → rewrite `-az1-` deps + Bug#1/#2 (services now use stable names).
4. Apigee (layer 3) → repoint targets.
5. Validate: `grep -r 'az1' <service-config>` returns only comments / cluster names; test failover.

**See also:** `dr-config/6-config-az-agnostic-rewrite.md` (full key list) · `phi-dr-architecture.drawio`
page 4 (before→after mechanism) · `dr-config/1-3` (the actual snippets).
