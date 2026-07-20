# PHI DR (Disaster Recovery) Architecture — Comprehensive Technical Reference

**Document Version:** 1.0  
**Last Updated:** 2026-07-19  
**Platform:** GCP (asia-south1)  
**DR Model:** Active-Passive (same region, dual availability zones)

---

## Executive Summary

The Prudential Health India (PHI) platform runs on GCP in `asia-south1` with an **active-passive DR spanning two availability zones** (AZ1 primary, AZ2 standby). All infrastructure is provisioned, but AZ2 microservice pods are not pre-running for cost optimisation. DR activation requires Apigee target server updates + GKE pod deployment — currently manual but automatable.

---

## Section 1: Repositories & Platform Overview

### Repositories
| Repo | Purpose |
|---|---|
| `apigee-config-main` | Terraform for Apigee X infrastructure (prusgrass tenant) |
| `phi-7wd-apigee-proxies-main` | Apigee proxy bundles + target server configs |
| `pruinhlth-prod-prd-chbb3e` | Terraform: GKE, Cloud SQL, Redis, PubSub, IAM, Firewall |
| `phi-7wd-ppmc-service-main` | PPMC Java/Spring Boot |
| `phi-7wd-crm-service` | CRM Java/Spring Boot |
| `phi-7wd-pas-service-main` | PAS Java/Spring Boot + gRPC:9090 |
| `phi-7wd-claim-processing-main` | Claim Processing NestJS/TypeScript |

### GCP Projects
| Environment | Project ID |
|---|---|
| Production | `pruinhlth-prod-prd-chbb3e-5648` |
| Non-Prod / UAT | `pruinhlth-nprd-uat-f8hev4-3c6b` |
| PAS Data | `pruinhlth-prod-prd-vpkcai-f2f0` |

---

## Section 2: Apigee X Infrastructure (apigee-config-main)

### Instance for PHI
```
Instance Name : apigee-instance-as1
Region        : asia-south1
IP Range      : 10.41.92.0/22
Org (prod)    : prusgrass-prod-infra-shared
Org (nprd)    : prusgrass-nprd-infra-shared
Environments  : pruinhlth-prd, phil-public-prod, phil-coreint-prod, phil-pruservices-prod
```

### Environment Group: pruinhlth-prd
| Hostname | Load Balancer | Access |
|---|---|---|
| `api.pruinhlthprod.apigee.pru.intranet.asia` | ILB (Internal) | Intranet only |
| `api.pruinhlthprod.apigee.prudentialhealth.in` | XLB (External) | Internet / 3rd party |

### ILB (Internal Load Balancer)
```
Frontend IP        : 10.41.110.130
Ingress Subnet     : apigee-nb-ingress-pruinhlth (10.41.110.128/26)
Proxy Subnet       : ap-proxy-as1 (10.41.110.192/26)
L7 ILB Prefix      : apigee-ilb-as1
Internal Domains   : *.pruinhlthprod.apigee.pru.intranet.asia
```

### XLB (External Load Balancer)
```
NEG Subnet  : apigee-neg-xlb-as1 (10.41.111.0/26)
Region      : asia-south1
LBU Mapping : pruinhlth → [asia-south1]
```

### Proxy Routing — Reverse Proxy Chain
```
External (3rd-party) → XLB (api.pruinhlthprod.apigee.prudentialhealth.in)
                     → Apigee Engine (pruinhlth-prd env)
                     → Target Server (lb1-pruinhlth-prd-az1 host)
                     → nginx-ingress (AZ1)
                     → GKE Pod (platform-domain-prod namespace)

Internal (GKE pods)  → ILB (api.pruinhlthprod.apigee.pru.intranet.asia / 10.41.110.130)
                     → Apigee Engine
                     → Target Server → External Partner (Medibuddy, Mediassist etc.)
```

### Service Account: pruinhlth-prd-bundle-deployer
```
Roles     : apigee.environmentAdmin, apigee.apiAdminV2, iam.serviceAccountUser,
            apigee.developerAdmin, logging.logWriter
Key       : Private key, rotation every 30 days
Vault Path: kv2/data/pruinhlth/prod/chbb3e/pruinhlth-prd-bundle-deployer
```

---

## Section 3: Apigee Proxy Configuration (phi-7wd-apigee-proxies-main)

### Target Servers: environments/pruinhlth-prd/targetservers.json

> ⚠️ **CRITICAL: ALL point to AZ1 only. No AZ2 entries exist. No failover configured.**

#### Internal Services (AZ1)
| Name | Host | Port |
|---|---|---|
| `claim-processing-service` | `claim-processing-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `ppmc-partner-service` | `ppmc-api.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `crm-partner-service` | `crm-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `pas-partner-service` | `pas-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `pis-channel-service` | `pis-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `policy-management` | `policy-management-api-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `document-management` | `document-management-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `party-management` | `party-management.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `payment-partner-service` | `payment-service.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `domain-master` | `domain-master-caching-api-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `product-management` | `product-management-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `chronic-care` | `chronic-care-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `ccm-service` | `ccm-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `filenet-service` | `filenet-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `tpa-partner-service` | `tpa-partner.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | 443 |
| `samvaad-adk` | `samvaad-service-prod.lb1-pruinhlth-prd-az1-f950ic.pru.intranet.asia` | 443 |

#### External Partners
| Name | Host | Partner |
|---|---|---|
| `mediassist` | `apiintegration.mediassist.in` | Mediassist (TPA claims) |
| `medibuddy` | `fuser.medibuddy.in` | Medibuddy (PPMC insurer API) |
| `ahcopd` | `bifrost-prod.medibuddy.in` | Medibuddy AHC/OPD |
| `insurance` | `partners.docsapp.in` | Docsapp (MER) |
| `chronic-care-service` | `services.prod.zyla.in` | Zyla |
| `katrix` | `rcmapi.instaalerts.zone` | Instaalerts |
| `sms` | `japi.instaalerts.zone` | Instaalerts SMS |
| `email` | `ejson.instaalerts.zone` | Instaalerts Email |

### Current Proxy Target XML — Single Server, No Failover
```xml
<!-- prod-ppmc-partner-service/apiproxy/targets/default.xml -->
<TargetEndpoint name="default">
  <HTTPTargetConnection>
    <LoadBalancer>
      <Server name="ppmc-partner-service"/>
    </LoadBalancer>
    <Path>/ppmc</Path>
  </HTTPTargetConnection>
</TargetEndpoint>
<!-- Same pattern: claim-processing→/claim-processing, crm→/crm, pas→/pas -->
```

### GitHub Workflows
```
target-server-deploy.yml
  Trigger  : workflow_dispatch OR push main (path: targetservers.json)
  Input    : environment (pruinhlth-dev|sit|uat|prd)
  Runner   : pru-phi-all-nprd-linux-runner-01
  Secrets  : GCP_SERVICE_ACCOUNT_KEY_ENCODED (nprd)
             GCP_SERVICE_ACCOUNT_KEY_ENCODED_PROD (prd)

proxy-deploy.yml         — deploy proxy bundles
shared-flow-deploy.yml   — deploy shared policy flows
```

### Production Proxy List (apigeeproxies-prd/)
```
prod-buy-online, prod-ccm-service, prod-chronic-care-service,
prod-claim-processing-service, prod-console-desktop, prod-console-web,
prod-digio, prod-document-management, prod-domain-master,
prod-filenet-service, prod-health-android, prod-health-app,
prod-health-desktop, prod-health-web, prod-katrix, prod-mediassist,
prod-medibuddy, prod-microsoft, prod-oAuth2, prod-party-management,
prod-pas-partner-service, prod-payment-partner-service,
prod-pis-channel-service, prod-policy-management,
prod-ppmc-partner-service, prod-samvaad-adk, prod-tpa-partner-service
```

---

## Section 4: GCP Infrastructure (pruinhlth-prod-prd-chbb3e)

### GKE Clusters

#### AZ1 — PRIMARY
```
Cluster     : gke-pruinhlth-prod-prd-chbb3e-az1
Region      : asia-south1 (regional, spans 3 zones)
K8s Version : 1.33.5-gke.1162000
Max Pods    : 32/node
Maintenance : Saturday-Sunday 16:00-22:00 UTC (weekly)

np1 : c2-standard-16, pd-ssd,      100 GB, min=0, max=10, label=gkeaz1np1
np2 : c2-standard-16, pd-balanced, 100 GB, min=0, max=5

Monitoring: Managed Prometheus enabled (SYSTEM_COMPONENTS, STORAGE)
```

#### AZ2 — DR STANDBY (same region as AZ1)
```
Cluster     : gke-pruinhlth-prod-prd-chbb3e-az2
Region      : asia-south1  ← SAME REGION — not cross-region DR
K8s Version : 1.33.5-gke.1162000

np1 : c2-standard-16, pd-ssd,      100 GB, min=0, max=10
np2 : c2-standard-16, pd-balanced, 100 GB, min=0, max=5

Status: Infrastructure provisioned, NO pods pre-running (cost optimisation)
```

### Cloud SQL PostgreSQL 14
```
Instance           : platform-domain-prod
Tier               : db-perf-optimized-N-4 (ENTERPRISE_PLUS)
Availability Type  : REGIONAL  ← automatic zone failover within asia-south1
Disk               : PD_SSD, 10 GB initial (auto-resize → 1 TB max)
Deletion Protection: true
Encryption         : enabled

Databases (13):
  quote, product, proposal, claims, health, party, payment, policy,
  servicing, communication, documents, rule_engine, domain_masters

Backup:
  PITR           : enabled
  Start Time     : 23:00 UTC
  Retention      : 14 days (14 backups retained)
  Log Retention  : 7 days
  Backup Location: asia-south1

Database Flags:
  cloudsql.iam_authentication = on
  max_connections             = 600
  cloudsql.logical_decoding   = on
  max_replication_slots       = 20
  max_wal_senders             = 20

Users:
  pguser (BUILT_IN)
  GINRHO-SAHI-GCP-DEVELOPERS@prugcp.com (CLOUD_IAM_USER)

⚠️  Cross-Region Replica (asia-south2): COMMENTED OUT — NOT provisioned
    Full asia-south1 outage = complete data unavailability
```

### Redis
```
Instance      : platform-domain-prod
Tier          : STANDARD_HA  ← automatic zone failover
Memory        : 4 GB
Read Replicas : DISABLED
Host          : 10.141.179.4
Port          : 6378
Auth/TLS      : enabled
```

### GCS Buckets
```
platform-domain:
  Class   : STANDARD, asia-south1
  Viewers : GINRHO-SAHI-GCP-DEVELOPERS@prugcp.com

document-bucket:
  Class            : STANDARD, asia-south1
  Object Retention : enabled
  Admin            : nitinbhasin@prudentialhealth.in
  Admin (SA)       : sa-14191-pruinhlth-prod@pruinhlth-prod-prd-chbb3e-5648.iam.gserviceaccount.com
```

### Firewall Rules

#### AZ1 Egress
```
allow-out-gke-az1-intranet-tcp-any (priority 65500)
  Targets : gke-pruinhlth-prod-prd-chbb3e-az1
  Ranges  : 10.141.161.192/26, 10.141.164.0/23, 10.223.2.0/25, 10.141.160.160/27,
            10.141.164.0/24, 10.141.161.0/26, 10.141.162.64/26, 10.141.160.108/32,
            10.141.161.160/27, 10.141.162.128/28, 10.143.161.160/27, 10.143.162.80/28,
            10.141.162.16/28, 10.141.161.64/26, 10.141.160.224/28
  Ports   : 443, 5432, 3306-3307, 6378, 6376

allow-out-gke-az1-internet (priority 1000)
  Targets : gke-pruinhlth-prod-prd-chbb3e-az1
  Ranges  : 0.0.0.0/0
  Ports   : 443
```

#### AZ2 Egress
```
allow-out-gke-az2-intranet-tcp-any (priority 65500)
  Targets : gke-pruinhlth-prod-prd-chbb3e-az2
  Ranges  : 10.143.161.192/26, 10.141.164.0/23, 10.223.2.0/25
  Ports   : 443, 5432, 3306-3307, 6378, 6376

allow-out-gke-az2-internet (priority 1000)
  Targets : gke-pruinhlth-prod-prd-chbb3e-az2
  Ranges  : 0.0.0.0/0
  Ports   : 443
```

#### AZ1 Ingress
```
allow-in-gke-az1-intranet-tcp-any (priority 65500)
  Ranges : same 15 ranges as AZ1 egress
  Ports  : 443, 5432, 3306-3307, 6378, 6376
```

#### AZ2 Ingress
```
allow-in-gke-az2-intranet-tcp-any (priority 65500)
  Ranges : 10.143.161.192/26, 10.141.164.0/23, 10.223.2.0/25
  Ports  : 443, 5432, 3306-3307, 6378, 6376
```

#### Forward Proxy Allowlist
```
Rule "001": api.razorpay.com, ejson.instaalerts.zone
```

### Service Accounts (GCP)
```
platform_domain:
  SA    : sa-14191-pruinhlth-prod@pruinhlth-prod-prd-chbb3e-5648.iam.gserviceaccount.com
  Roles : pubsub.publisher, pubsub.subscriber, cloudsql.client, logging.logWriter,
          storage.objectUser, storage.bucketViewer, cloudtrace.agent, bigquery.jobUser,
          bigquery.metadataViewer, logging.configWriter, storage.objectViewer, cloudsql.admin
  Key Rotation : 365 days
  Vault Path   : kv2/data/pruinhlth/prod/chbb3e/platform_domain_prod

cloudadmin (ClaimZippy AI):
  Roles : aiplatform.user, storage.objectViewer, storage.objectUser, storage.bucketViewer,
          cloudtrace.agent, pubsub.publisher, pubsub.subscriber
  Key Rotation : 365 days
  Vault Path   : kv2/data/pruinhlth/prod/chbb3e/cloudadmin_prod
```

### IAM Workload Identity
```hcl
GCP SA : sa-14191-pruinhlth-prod@pruinhlth-prod-prd-chbb3e-5648.iam.gserviceaccount.com
Role   : roles/iam.workloadIdentityUser

Members (K8s → GCP):
  Production pods (AZ1):
    pruinhlth-prod-prd-chbb3e-5648.svc.id.goog[platform-domain-prod/platform-domain-microservice-prod]

  DR pods (AZ2) — PRE-CONFIGURED ✓:
    pruinhlth-prod-prd-chbb3e-5648.svc.id.goog[platform-domain-prd-dr/platform-domain-microservice-prod-dr]
```

---

## Section 5: Pub/Sub Topics (Complete List)

All use `prod-` prefix. Each has a corresponding `-dl-topic` dead letter queue.

```
DAS     : prod-das-agent-created-topic
Claims  : prod-claim-data-updated-topic, prod-tpa-claim-updated-topic,
          prod-pas-claim-updated-topic, prod-claim-communication-updated-topic
CRM     : prod-crm-call-update-request-topic, prod-partner-call-request-update-topic,
          prod-channel-lead-update-topic, prod-crm-process-endorsement-topic,
          prod-crm-process-service-request-topic, prod-crm-document-update-topic,
          prod-crm-quotes-updated-topic, prod-crm-proposals-updated-topic,
          prod-crm-ppmc-tickets-updated-topic, prod-crm-policies-updated-topic,
          prod-crm-payments-updated-topic, prod-crm-notes-updated-topic,
          prod-crm-mer-tickets-updated-topic, prod-crm-feedback-updated-topic,
          prod-crm-documents-updated-topic, prod-crm-communications-updated-topic,
          prod-crm-claim-tickets-updated-topic, prod-crm-call-claims-updated-topic,
          prod-crm-agents-updated-topic, prod-crm-generic-ticket-topic,
          prod-crm-opd-tickets-topic, prod-crm-ahc-tickets-topic
PAS     : prod-pas-party-data-updated-topic, prod-pas-product-updated-topic,
          prod-pas-proposal-updated-topic, prod-pas-quote-updated-topic,
          prod-pas-policy-processed-topic, prod-pas-service-request-updated-topic,
          prod-pas-provider-data-updated-topic, prod-pas-provider-updated-topic,
          prod-pas-provider-received-topic
Payment : prod-payment-data-updated-topic, prod-payment-request-updated-topic
PPMC    : prod-ppmc-medical-test-updated-topic, prod-ppmc-mer-updated-topic,
          prod-ppmc-ahc-opd-updated-topic, prod-ppmc-communication-updated-topic,
          prod-ppmc-call-updated-topic
Channel : prod-channel-quote-created-topic, prod-channel-user-activity-reported-topic
NPS     : prod-nps-survey-updated-topic
Chronic : prod-chronic-care-activity-topic, prod-chronic-care-appointment-activity-topic
Policy  : prod-policy-management-sr-updated-topic,
          prod-policy-management-policy-processed-topic
SR      : prod-endorsement-sr-updated-topic, prod-endorsement-processed-sr-topic,
          prod-src-document-update-topic, prod-sr-processed-topic
DMS     : prod-dms-party-document-upload-topic,
          prod-dms-underwriting-document-upload-topic,
          prod-proposal-link-document-topic
Partner : prod-partner-endorsement-request-topic
TPA     : prod-tpa-hospital-created-topic
AML     : prod-aml-request-created, prod-aml-request-updated
CCM     : prod-ccm-communication-trigger-topic, prod-communication-otp-generated-topic
OZ      : prod-oz-digitization-result-topic
```

Subscription settings: `max_delivery_attempts=5, max_backoff=600s, min_backoff=300s, message_ordering=true`

---

## Section 6: GKE NGINX Ingress Layer

### AZ1 nginx-ingress (Production)
```
Namespace     : platform-domain-prod
IngressClass  : nginx-ingress
Domain Pattern: <service>.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
TLS           : required, port 443
```

### AZ2 nginx-ingress (DR Standby)
```
Namespace     : platform-domain-prd-dr
IngressClass  : nginx-ingress
Domain Pattern: <service>.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia
TLS           : required, port 443
Status        : Active only when DR pods are deployed
```

---

## Section 7: Microservice Specifications

### Kubernetes Namespaces
| Environment | Namespace | K8s Service Account |
|---|---|---|
| Production (AZ1) | `platform-domain-prod` | `platform-domain-microservice-prod` |
| DR (AZ2) | `platform-domain-prd-dr` | `platform-domain-microservice-prod-dr` |

---

### 7.1 PPMC Service (phi-7wd-ppmc-service-main)

**Purpose:** Pre & Post Medical Clearance — medical tests, AHC/OPD subscriptions, Medibuddy callbacks

| Property | Production (AZ1) | DR (AZ2) |
|---|---|---|
| Ingress host | `ppmc-api.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | `ppmc-api.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia` |
| Path | `/` | `/` |
| Ports | 8080 (HTTP), 9090 (gRPC) | same |
| Replicas | 1 | 1 |
| HPA | 1–5 (CPU/Mem 70%) | 1–5 |
| Resources req | 1 CPU, 2 Gi | same |
| Resources lim | 1 CPU, 4 Gi | same |
| Spring Profile | `prod` | `prod` |
| Liveness | `/actuator/health/liveness` delay=60s, period=15s, fail=3 | same |
| Readiness | `/actuator/health/readiness` delay=30s, period=10s, fail=5 | same |
| preStop | sleep 15s | same |
| Vault path | — | `kv2/data/pruinhlth/prod/dr/chbb3e/ppmc/client-credentials` |

#### Environment Variables (PPMC)
```bash
SPRING_PROFILES_ACTIVE=prod
ORGANIZATION_CERT_BASE64=<from K8s secret: sahi-certificates, key: ssl-cert>
PPMC_CLIENT_ID=__PPMC_CLIENT_ID__
PPMC_SOURCE_ID=__PPMC_SOURCE_ID__
PPMC_USERNAME=__PPMC_USERNAME__
PPMC_PASSWORD=__PPMC_PASSWORD__
MER_API_KEY=__MER_API_KEY__
MER_CLIENT_ID=__MER_CLIENT_ID__
MER_CLIENT_SECRET=__MER_CLIENT_SECRET__
AHC_PARTNER_SECRET_KEY=__AHC_SECRET_KEY_NEW__
OPD_PARTNER_SECRET_KEY=__OPD_SECRET_KEY_NEW__
HASURA_SECRET_PROD=__HASURA_SECRET_PROD__
ADTC_JWT_KEY=__ADTC_JWT_KEY__
ADTC_SECRET_KEY=__ADTC_SECRET_KEY__
AHC_JWT_KEY=__AHC_JWT_KEY__
OPD_JWT_KEY=__OPD_JWT_KEY__
```

#### application-prod.yml (Key Config)
```yaml
projectId     : pruinhlth-prod-prd-chbb3e-5648
domainSuffix  : lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
topicPrefix   : prod
bucketName    : pruinhlth-prd-chbb3e-asia-south1-medibuddy
redis.host    : 10.141.179.4
redis.port    : 6378

# Outbound URLs
medibuddy.baseUrl     : https://fuser.medibuddy.in/api/v1/insurer
medibuddy.apigeeBase  : https://apigee-pruinhlth-prd.pru.intranet.asia/prod/medibuddy/v1/insurer/
mer.apigeeUrl         : https://apigee-pruinhlth-prd.pru.intranet.asia/prod/medibuddy/
mer.rescheduleUrl     : https://video.docsapp.in
mer.createCaseUrl     : https://partners.docsapp.in
ahcOpd.baseUrl        : https://bifrost-prod.medibuddy.in/sdk/policy/subscription
ahcOpd.apigeeUrl      : https://apigee-pruinhlth-prd.pru.intranet.asia/prod/medibuddy/sdk/policy/subscription
filenet.baseUrl       : https://document-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia/document/
pas.api.baseUrl       : https://pas-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
payment.gateway.url   : http://payment-service
document.base-url     : http://document-api

# Pub/Sub published
prod-ppmc-mer-updated-topic
prod-ppmc-medical-test-updated-topic
prod-ppmc-ahc-opd-updated-topic
prod-ppmc-communication-updated-topic
prod-ppmc-call-updated-topic

# Subscriptions consumed
prod-pas-proposal-updated-ppmc-sub
prod-pas-policy-processed-ppmc-sub
prod-pas-service-request-updated-ppmc-sub
```

#### mTLS Configuration
```
Outgoing (PPMC → Medibuddy):
  Client Cert : phi-egress-client (Prudential PKI)
  Trusted CA  : medibuddy-ca.crt
  Validation  : strict

Incoming (Medibuddy → PPMC callbacks):
  Require Client Cert : true
  Trusted CA          : apigee-ca / medibuddy-ca
  Webhook Endpoint    : /ppmc/medibuddy/webhook/mTLS

Inbound Callback Endpoints (via Apigee proxy prod-ppmc-partner-service):
  POST /ppmc/callback/case              ← Medibuddy MER case updates
  POST /ppmc/callback/ppmc-case         ← Medibuddy medical test updates
  POST /ppmc/callback/ahc-opd           ← Medibuddy AHC/OPD updates
  POST /ppmc/callback/communication     ← Medibuddy communication status
  GET  /ppmc/mtls/health/status         ← Medibuddy health check
```

#### ⚠️ application-dr.yml — MISCONFIGURED (DO NOT USE)
```yaml
# This file is NOT loaded — SPRING_PROFILES_ACTIVE=prod in DR pods
# If profile=dr were set accidentally, pods would connect to UAT:
gcp.projectId   : pruinhlth-nprd-uat-f8hev4-3c6b  ← WRONG (UAT project)
domainSuffix    : lb1-pruinhlth-uat-az2-f8hev4.pru.intranet.asia  ← WRONG
topicPrefix     : dr  ← WRONG (dr-ppmc-* topics don't exist in prod)
```

---

### 7.2 CRM Service (phi-7wd-crm-service)

**Purpose:** Customer relationships, tickets, communications, SimpleCRM integration

| Property | Production (AZ1) | DR (AZ2) |
|---|---|---|
| Ingress host | `crm-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | `crm-services-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia` |
| Paths | `/crm, /swagger-ui/, /v3/, /actuator/` | same |
| Port | 8080 | 8080 |
| Replicas | 1 | 1 |
| HPA | 1–5 | 1–5 |
| Resources | req=1CPU/2Gi, lim=2CPU/4Gi | same |
| Spring Profile | `prod` | `prod` (uses application-prod-dr.yml) |

#### Environment Variables (CRM)
```bash
SPRING_PROFILES_ACTIVE=prod
SIMPLECRM_DEFAULTCREDENTIALS_CLIENTID=__SIMPLECRM_DEFAULTCREDENTIALS_CLIENTID__
SIMPLECRM_DEFAULTCREDENTIALS_CLIENTSECRET=__SIMPLECRM_DEFAULTCREDENTIALS_CLIENTSECRET__
SIMPLECRM_DEFAULTCREDENTIALS_GRANTTYPE=__SIMPLECRM_DEFAULTCREDENTIALS_GRANTTYPE__
HASURA_ADMIN_SECRET=__HASURA_ADMIN_SECRET__
SIMPLECRM_CA_CERT=__SIMPLECRM_CA_CERT__
```

#### application-prod-dr.yml
```yaml
crm.simple.baseUrl : https://crm-prod.lb1-pruinhlth-prd-az1-rzg0c4.pru.intranet.asia
gcp.projectId      : pruinhlth-prod-prd-chbb3e-5648  ✓ correct prod project
pubsub.topicPrefix : prod  ✓ correct (shared topics with AZ1)
```

#### Key PubSub Subscriptions (40+)
```
prod-tpa-claim-updated-crm-sub
prod-pas-proposal-updated-crm-sub
prod-ppmc-mer-updated-crm-sub
prod-ppmc-medical-test-updated-crm-sub
prod-pas-policy-processed-crm-sub
prod-pas-service-request-updated-crm-sub
prod-payment-data-updated-crm-sub
prod-channel-quote-created-crm-sub
prod-das-agent-created-crm-sub
prod-ccm-communication-trigger-crm-sub
prod-dms-underwriting-document-upload-crm-sub
prod-claim-communication-updated-crm-sub
prod-ppmc-ahc-opd-updated-crm-sub
prod-ppmc-communication-updated-crm-sub
prod-endorsement-sr-updated-crm-sub
prod-endorsement-processed-service-request-crm-sub
(+ corresponding -dl-crm-sub dead-letter variants)
```

#### CI/CD
```
deploy-crm.yml:
  Triggers : push develop | workflow_dispatch (dev|sit|uat|prod|dr) | schedule 16:00 UTC daily
  Guard    : PROD/DR only deployable from main branch
```

---

### 7.3 PAS Service (phi-7wd-pas-service-main)

**Purpose:** Products, proposals, policies, BaNCS core banking integration

| Property | Production (AZ1) | DR (AZ2) |
|---|---|---|
| Ingress hosts | `pas-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | `pas-services-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia` |
| | `pas-partner-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | `pas-partner-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia` |
| Ports | 8080 (HTTP), 9090 (gRPC) | same |
| HPA | 1–20 (highest scaling) | 1–20 |
| Spring Profile | `prod` | `prod` |

#### application-prod.yml (Key Config)
```yaml
bancsHost     : core-prod.lb1-pruinhlth-prd-az1-vpkcai.pru.intranet.asia
domainSuffix  : lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
pasTopicPrefix: prod
ilTopicPrefix : prod
projectId     : pruinhlth-prod-prd-chbb3e-5648
pasProjectId  : pruinhlth-prod-prd-vpkcai-f2f0

BaNCS Endpoints (all via bancsHost):
  Product     : /BaNCSServicesHL/api/ProductServices/Product/13.0
  Proposal    : /BaNCSServicesHL/api/HealthProposalService/Policy/14.0
  Underwriting: /BaNCSServicesHL/api/UnderwritingServices/HealthMember/13.0
  Party       : /BaNCSServicesHL/api/PartyServices/HealthParty/13.0
  Quote       : /BaNCSQuote/quoteEngine
  Endorsement : /BaNCSServicesHL/api/EndorsementServices/Endorsement/13.0
  CancelPolicy: /BaNCSServicesHL/api/EndorsementServices/CancelPolicy/13.0
  Claim       : /BaNCSServicesHL/api/ClaimServices/HealthClaim/13.0
  Document    : /BaNCSServicesHL/api/DocumentServices/Document/13.0
  Collection  : /BaNCSAccounts/AccountsService
```

---

### 7.4 Claim Processing Service (phi-7wd-claim-processing-main)

**Purpose:** Claims lifecycle — submission, validation, Mediassist TPA integration

| Property | Production (AZ1) | DR (AZ2) |
|---|---|---|
| Ingress host | `claim-processing-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia` | `claim-processing-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia` |
| Path | `/claim-processing` | `/claim-processing` |
| Port | 3000 | 3000 |
| HPA | 1–10 | 1–10 |
| Resources | req=1CPU/2048Mi, lim=2CPU/4096Mi | same |
| Health URL | `/claim-processing/v1/app` | same |

#### Environment Variables (Claim Processing)
```bash
NODE_ENV=prod
PORT=3000
GCP_PROJECT_ID=pruinhlth-prod-prd-chbb3e-5648
GOOGLE_APPLICATION_CREDENTIALS=/var/secrets/google/key.json
CLAIM_DATA_UPDATED_TOPIC=prod-claim-data-updated-topic
GRAPHQL_CORE_BASE_URL=http://domain-graph
TPA_PARTNER_URL=http://tpa-partner
HASURA_ADMIN_SECRET=__HASURA_ADMIN_SECRET__
ENABLE_SENSITIVE_DATA_REDACTION=false
OTEL_LOG_LEVEL=warn
OTEL_LOGS_EXPORTER=none
# ⚠️ DR yaml: ORGANIZATION_CERT_BASE64 is COMMENTED OUT (Bug #2)
```

#### Internal Integrations
```
TPA Partner (Mediassist):
  Claim submission : http://tpa-partner/tpa-partner/v1/ma/claim-submission-callback-api
  Doc upload       : http://tpa-partner/tpa-partner/v1/ma/callback/document-upload

Domain Graph (Hasura): http://domain-graph
Pub/Sub topic        : prod-claim-data-updated-topic
```

#### CI/CD
```
deploy-claim-processing.yml:
  Triggers : push main | workflow_dispatch (dev|sit|uat|prod|dr)
  Guard    : PROD/DR only from main branch
  DR health check URL:
    https://claim-processing-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia/claim-processing/v1/app
```

---

## Section 8: DR Gaps & Critical Bugs

### What Survives Automatically (No Action Needed)

| Component | Mechanism | RTO |
|---|---|---|
| Cloud SQL | REGIONAL HA — automatic zone failover | 2–5 min |
| Redis | STANDARD_HA — automatic zone failover | < 1 min |
| Pub/Sub | Global service — zone agnostic | Instant |
| IAM Workload Identity | DR namespace pre-bound in iam.tf | Ready ✓ |
| Firewall Rules AZ2 | Pre-configured | Ready ✓ |
| Apigee Engine | Single-region instance (zone-agnostic) | Ready ✓ |

### What Requires Manual Action

| Step | Action | Time | Impact if Skipped |
|---|---|---|---|
| 1 | `kubectl apply` 4 DR YAMLs to AZ2 | 3–5 min | AZ2 pods don't start |
| 2 | Update Apigee targetservers + run workflow | 2–3 min | 3rd-party callbacks fail |
| **Total RTO** | | **~10 min** | |

---

### ⚠️ Bug #1 — application-dr.yml Points to UAT (Severity: HIGH)
```
File   : phi-7wd-ppmc-service-main/src/main/resources/application-dr.yml

Current misconfig:
  gcp.projectId  = pruinhlth-nprd-uat-f8hev4-3c6b  ← WRONG (UAT project)
  domainSuffix   = lb1-pruinhlth-uat-az2-f8hev4.pru.intranet.asia  ← WRONG
  topicPrefix    = dr  ← WRONG (dr-ppmc-* topics don't exist in prod)

Status : NOT loaded currently (DR pods use SPRING_PROFILES_ACTIVE=prod)
Risk   : If profile=dr is ever used, pods connect to UAT infrastructure

Fix:
  gcp.projectId  → pruinhlth-prod-prd-chbb3e-5648
  domainSuffix   → lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia
  topicPrefix    → prod
```

### ⚠️ Bug #2 — claim-processing-dr.yml Missing SSL Cert (Severity: MEDIUM)
```
File   : phi-7wd-claim-processing-main DR deployment YAML

Issue  : ORGANIZATION_CERT_BASE64 env var is COMMENTED OUT in DR YAML
         Production YAML has it enabled (from K8s secret: sahi-certificates)

Impact : mTLS outbound calls from Claim Processing to TPA may fail in DR

Fix    : Uncomment ORGANIZATION_CERT_BASE64 in DR deployment YAML
         Source: secretKeyRef: name=sahi-certificates, key=ssl-cert
```

### ⚠️ Bug #3 — No AZ2 Target Servers in Apigee (Severity: CRITICAL)
```
File   : phi-7wd-apigee-proxies-main/environments/pruinhlth-prd/targetservers.json

Issue  : All 17 target servers → AZ1 only. No AZ2 entries, no failover logic in proxy XMLs.

Impact : During DR — all 3rd-party callbacks (Medibuddy mTLS via XLB Apigee) continue
         routing to dead AZ1 pods → FAIL.
         External platform traffic completely broken until Apigee is manually updated.

Fix    : Add 4 AZ2 target server entries + IsFallback XML in proxy targets
         (see Section 9 Option A)
```

### ⚠️ Bug #4 — Cross-Region DR Replica Disabled (Severity: HIGH, Long-term)
```
File   : pruinhlth-prod-prd-chbb3e/terraform.tfvars (Cloud SQL config)

Issue  : Cross-region replica to asia-south2 is commented out:
         # zone = asia-south2-a
         # tier = db-perf-optimized-N-4

Impact : Full asia-south1 regional outage = complete data unavailability
         (Current DR only protects against single-zone failure, not full region)

Fix    : Uncomment + provision read replica in asia-south2-a
```

---

## Section 9: Automation Options for DR

### Option A: Apigee LoadBalancer Auto-Failover (Zero-Click — Recommended)

Add AZ2 as fallback servers in Apigee + pre-warm AZ2 pods. Automatic failover with no manual action needed.

**5 files to change:**

#### Step 1 — Add to targetservers.json (4 new entries)
```json
{ "name": "ppmc-partner-service-dr",
  "host": "ppmc-api.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia",
  "isEnabled": true, "port": 443, "sSLInfo": {"enabled": true}, "protocol": "HTTP" },
{ "name": "claim-processing-service-dr",
  "host": "claim-processing-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia",
  "isEnabled": true, "port": 443, "sSLInfo": {"enabled": true}, "protocol": "HTTP" },
{ "name": "crm-partner-service-dr",
  "host": "crm-services-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia",
  "isEnabled": true, "port": 443, "sSLInfo": {"enabled": true}, "protocol": "HTTP" },
{ "name": "pas-partner-service-dr",
  "host": "pas-services-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia",
  "isEnabled": true, "port": 443, "sSLInfo": {"enabled": true}, "protocol": "HTTP" }
```

#### Step 2 — Update each of 4 proxy target XMLs (same pattern for all)
```xml
<!-- prod-ppmc-partner-service/apiproxy/targets/default.xml -->
<TargetEndpoint name="default">
  <HTTPTargetConnection>
    <LoadBalancer>
      <Algorithm>RoundRobin</Algorithm>
      <Server name="ppmc-partner-service">
        <Weight>5</Weight>
      </Server>
      <Server name="ppmc-partner-service-dr">
        <IsFallback>true</IsFallback>
      </Server>
      <MaxFailures>2</MaxFailures>
      <RetryEnabled>true</RetryEnabled>
      <ServerUnhealthyResponse>
        <ResponseCode>500</ResponseCode>
        <ResponseCode>503</ResponseCode>
      </ServerUnhealthyResponse>
    </LoadBalancer>
    <Path>/ppmc</Path>
  </HTTPTargetConnection>
</TargetEndpoint>
<!-- Apply same pattern to: claim-processing, crm, pas proxy XMLs -->
```

#### Step 3 — Pre-warm AZ2 (one-time kubectl apply)
```bash
kubectl apply -f deployments/claim-processing-dr.yml
kubectl apply -f deployments/crm-api-dr.yml
kubectl apply -f deployments/ppmc-api-dr.yml
kubectl apply -f deployments/pas-api-dr.yml
```

**Result:** AZ1 fails → Apigee detects 2 consecutive failures → auto-routes to AZ2 in < 30 sec.

---

### Option B: GitHub Actions Single-Click DR Workflow

**1 new file:** `phi-7wd-apigee-proxies-main/.github/workflows/dr-failover.yml`

```yaml
name: DR Failover Switch
on:
  workflow_dispatch:
    inputs:
      direction:
        description: 'Failover direction'
        required: true
        type: choice
        options: ['az1-to-az2', 'az2-to-az1']  # az2-to-az1 = failback

jobs:
  dr-switch:
    runs-on: pru-phi-all-nprd-linux-runner-01
    steps:
      - uses: actions/checkout@v4

      - name: Patch Apigee target servers
        run: |
          if [ "${{ inputs.direction }}" == "az1-to-az2" ]; then
            sed -i 's/lb1-pruinhlth-prd-az1-chbb3e/lb1-pruinhlth-prd-az2-chbb3e/g' \
              src/main/apigee/environments/pruinhlth-prd/targetservers.json
          else
            sed -i 's/lb1-pruinhlth-prd-az2-chbb3e/lb1-pruinhlth-prd-az1-chbb3e/g' \
              src/main/apigee/environments/pruinhlth-prd/targetservers.json
          fi

      - name: Deploy Apigee target servers
        # calls existing target-server-deploy.yml for pruinhlth-prd

      - name: Deploy DR microservices
        run: |
          gh workflow run deploy-crm.yml \
            -R <org>/phi-7wd-crm-service --field environment=dr
          gh workflow run deploy-claim-processing.yml \
            -R <org>/phi-7wd-claim-processing-main --field environment=dr
          # Repeat for ppmc and pas
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Comparison

| | Option A (Apigee LB) | Option B (GH Actions) |
|---|---|---|
| Trigger | Automatic (zero-click) | One click |
| Failover speed | < 30 sec | 10–15 min |
| Pre-requisite | AZ2 pods pre-warmed | Nothing |
| Files changed | 5 (targetservers + 4 XMLs) | 1 new workflow |
| Failback | Automatic on AZ1 recovery | Re-run with az2-to-az1 |
| 3rd-party continuity | ✅ Seamless | ✅ After workflow completes |
| Complexity | Medium | Low |

---

## Section 10: Quick Reference

### URLs

#### Production (AZ1)
```
Apigee External  : api.pruinhlthprod.apigee.prudentialhealth.in
Apigee Internal  : api.pruinhlthprod.apigee.pru.intranet.asia
PPMC             : ppmc-api.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
CRM              : crm-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
PAS              : pas-services-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
PAS Partner      : pas-partner-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
Claim Processing : claim-processing-prod.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
TPA Partner      : tpa-partner.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia
```

#### DR (AZ2)
```
PPMC             : ppmc-api.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia
CRM              : crm-services-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia
PAS              : pas-services-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia
PAS Partner      : pas-partner-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia
Claim Processing : claim-processing-prod.lb1-pruinhlth-prd-az2-chbb3e.pru.intranet.asia
```

### Key IPs
| Resource | IP | Port |
|---|---|---|
| Redis | 10.141.179.4 | 6378 |
| Apigee ILB Frontend | 10.41.110.130 | 443 |

### DR Activation Checklist
- [ ] Deploy 4 DR YAMLs to AZ2 (`kubectl apply`)
- [ ] Verify pods ready (`kubectl get pods -n platform-domain-prd-dr`)
- [ ] Update `targetservers.json` (4 service hosts: az1 → az2)
- [ ] Trigger `target-server-deploy.yml` (environment: pruinhlth-prd)
- [ ] Validate health endpoints on AZ2 hosts
- [ ] Test Medibuddy callback via Apigee XLB — confirm reaches AZ2 pods
- [ ] Monitor pod logs for mTLS / DB / PubSub errors

---

## Appendix: Glossary

| Term | Definition |
|---|---|
| AZ1 | Availability Zone 1 — Primary production (`gke-pruinhlth-prod-prd-chbb3e-az1`) |
| AZ2 | Availability Zone 2 — DR standby (`gke-pruinhlth-prod-prd-chbb3e-az2`) |
| ILB | Internal Load Balancer — Apigee intranet frontend (10.41.110.130:443) |
| XLB | External Load Balancer — Apigee internet-facing frontend |
| lb1 | NGINX Ingress Controller LB prefix in cluster hostnames |
| PPMC | Pre & Post Medical Clearance service |
| PAS | Product & Administration Services (also integrates BaNCS) |
| TPA | Third-Party Administrator (Mediassist handles claims) |
| mTLS | Mutual TLS — bidirectional certificate authentication |
| REGIONAL HA | Cloud SQL zone failover within same GCP region |
| PSC | Private Service Connect — Apigee VPC connectivity mechanism |
| NEG | Network Endpoint Group — Apigee XLB backend |
| BaNCS | Core banking system integrated via PAS service |

---

**Document End** | Version 1.0 | 2026-07-19
