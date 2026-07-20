# Step ③ / Issue ④ — "Kill every `-az1-`" rewrite checklist (all systems)

**The RULE:** no hostname a service depends on may contain `az1`/`az2`. Replace each with:
- **Stable name** (cross-cluster/project) = drop the `-az1-` token →
  `…lb1-pruinhlth-prd-<projtoken>.pru.intranet.asia`, fronted by that system's internal L4 NLB failover VIP + wildcard DNS.
- **K8s service name** (same-cluster east-west) = `http://<service>` (already DR-safe).

Naming convention (per system, `<projtoken>` = chbb3e/vpkcai/rzg0c4/nhq8h1/f950ic/aa8b68/yoh0kt/…):
```
BEFORE : <svc>.lb1-pruinhlth-prd-az1-<projtoken>.pru.intranet.asia
AFTER  : <svc>.lb1-pruinhlth-prd-<projtoken>.pru.intranet.asia      (no az1/az2)
```

Legend:  ☐ = to do ·  ✅-safe = already AZ-agnostic (leave as-is)

---

## 1. Integration Layer / PPMC  (project chbb3e)  — `application-prod.yml`
| ☐ | Key | Current (`-az1-`) | Replace with (stable) |
|---|---|---|---|
| ☐ | `domainSuffix` | `lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | `lb1-pruinhlth-prd-chbb3e.pru.intranet.asia` |
| ☐ | `filenet.baseUrl` | `https://document-services-prod.lb1-pruinhlth-prd-az1-chbb3e…/document/` | `https://document-services-prod.lb1-pruinhlth-prd-chbb3e…/document/` |
| ☐ | `pas.api.baseUrl` | `https://pas-services-prod.lb1-pruinhlth-prd-az1-chbb3e…` | `https://pas-services-prod.lb1-pruinhlth-prd-chbb3e…` |
| ✅-safe | `payment.gateway.url` | `http://payment-service` (K8s svc) | keep |
| ✅-safe | `document.base-url` | `http://document-api` (K8s svc) | keep |
| ✅-safe | `medibuddy.apigeeBase`, `mer.apigeeUrl`, `ahcOpd.apigeeUrl` | `apigee-pruinhlth-prd.pru.intranet.asia/…` (gateway) | keep (zone-agnostic) |

> Because `domainSuffix` is az1-pinned and other URLs are built from it, fixing it de-pins several derived endpoints at once.

## 2. PAS / TCS BaNCS  (project vpkcai)  — `application-prod.yml`
| ☐ | Key | Current | Replace with |
|---|---|---|---|
| ☐ | `bancsHost` | `core-prod.lb1-pruinhlth-prd-az1-vpkcai.pru.intranet.asia` | `core-prod.lb1-pruinhlth-prd-vpkcai.pru.intranet.asia` |
| ☐ | `domainSuffix` | `lb1-pruinhlth-prd-az1-chbb3e…` | `lb1-pruinhlth-prd-chbb3e…` |

## 3. SimpleCRM  (project rzg0c4)  — `application-prod-dr.yml`
| ☐ | Key | Current | Replace with |
|---|---|---|---|
| ☐ | `crm.simple.baseUrl` | `https://crm-prod.lb1-pruinhlth-prd-az1-rzg0c4.pru.intranet.asia` | `https://crm-prod.lb1-pruinhlth-prd-rzg0c4.pru.intranet.asia` |

## 4. Claim Processing  (chbb3e)
| ✅-safe | Key | Value |
|---|---|---|
| ✅-safe | `GRAPHQL_CORE_BASE_URL` | `http://domain-graph` (K8s svc) — keep |
| ✅-safe | `TPA_PARTNER_URL` | `http://tpa-partner` (K8s svc) — keep |

## 5. Health App  (project rzg0c4)  — direct-az1 caller ①
| ☐ | Item | Current | Replace with |
|---|---|---|---|
| ☐ | own ingress host | `healthapp-…lb1-pruinhlth-…-az1-…pru.intranet.asia` | `healthapp-…lb1-pruinhlth-…-<projtoken>…` (stable) |
| ☐ | PHI Comms (OTP/SMS) | `comms-svc-…pru.intranet.asia` (direct) | stable comms endpoint (or via Apigee) |
| ☐ | Party Management | `party-management-…pru.intranet.asia` (direct) | stable / via Apigee |

## 6. Fyntune  (own project)  — direct-az1 caller ① (bypasses Apigee)
| ☐ | Item | Current | Replace with |
|---|---|---|---|
| ☐ | **IL link it calls** | IL `…-az1-chbb3e…` direct | **IL stable name** `…lb1-pruinhlth-prd-chbb3e…` (or az1-failover-DNS shortcut → no Fyntune change) |
| ☐ | its own ingress + `-az1-` deps | `…-az1-<fyntune-proj>…` | stable `…-<fyntune-proj>…` + its own L4 NLB failover VIP |

## 7. Samvaad  (project f950ic)
| ☐ | Item | Current | Replace with |
|---|---|---|---|
| ☐ | **VPC connector** | `vpc-connector-prd-az1` (only) | **add `vpc-connector-prd-az2`** (egress must survive az1 loss) |
| ☐ | egress targets | Hasura/SimpleCRM/PAS-PIS/FileNet `*.pru.intranet.asia` (az1) | each system's stable name |

## 8. PIXEL / Doc Digitisation  (project dp1d50 / f950ic)
| ☐ | Item | Current | Replace with |
|---|---|---|---|
| ☐ | ingress hosts | `digitisation-*.lb1-pruinhlth-…-az1-dp1d50…` | stable `…-dp1d50…` |
| ☐ | VPC connector | `vpc-connector-*-az1` | add `-az2` |

## 9. FileNet / BAW / ODM  (project nhq8h1)
| ☐ | Item | Current | Replace with |
|---|---|---|---|
| ☐ | ingress hosts | `cp4ba-*.lb1-pruinhlth-…-az1-nhq8h1…` | stable `…-nhq8h1…` |
| ⚠ | DB2-on-VM + on-prem AD (DSG001/DSG002) | non-GKE | **out of GKE-AZ scope — own HA/DR** |

## 10. Apigee target servers  (`phi-7wd-apigee-proxies-main/environments/pruinhlth-prd/targetservers.json`)  — Step ④
Repoint **all 17** from `-az1-` to the stable host (drop `-az1-`):
```
☐ claim-processing-service   ☐ ppmc-partner-service      ☐ crm-partner-service
☐ pas-partner-service        ☐ pis-channel-service       ☐ policy-management
☐ document-management        ☐ party-management          ☐ payment-partner-service
☐ domain-master              ☐ product-management        ☐ chronic-care
☐ ccm-service                ☐ filenet-service           ☐ tpa-partner-service
☐ samvaad-adk  (…-az1-f950ic → …-f950ic)
```
External-partner targets (mediassist, medibuddy, ahcopd, insurance/docsapp, zyla, instaalerts) = partner hosts, **no change**.

## 11. DR-config bugs (Step ⑤ — do BEFORE warming az2)
| ☐ | Bug | Fix |
|---|---|---|
| ☐ | **#1** PPMC `application-dr.yml` → UAT (`f8hev4`, `topicPrefix: dr`) | Delete the `dr` profile; run az2 on `prod` (stable chbb3e). |
| ☐ | **#2** claim-processing DR yaml missing `ORGANIZATION_CERT_BASE64` | Uncomment (`secretKeyRef: sahi-certificates/ssl-cert`). |

---

## Rollout order (Issue ⑩ — one coordinated program)
1. **Hub first — IL (chbb3e):** stable endpoint + §1 rewrites + §10 Apigee repoint + §11 bug fixes.
2. **Direct-az1 callers — Health App, Fyntune:** point them at IL's stable name (or az1-failover-DNS shortcut), then give each its own dual-AZ template.
3. **Downstream systems — PAS, FileNet, CRM, Samvaad (+az2 connector), PIXEL, CHUB:** §2–§9.
4. **Apigee-fronted channels — PruServices, Buy-Online, D2C, Corp:** only §10 repoint (already zone-safe on the IL hop).

**Done when:** `grep -r 'az1' <config>` across every system returns only comments / cluster-object names — no dependency **hostname** contains `az1`.
