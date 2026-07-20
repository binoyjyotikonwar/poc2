# Piece 2 (warm AZ2) + Apigee repoint + bug fixes

## 3a. Warm-minimal AZ2 — the setting that removes ALL manual restart
For each critical service in the DR namespace `platform-domain-prd-dr`, set the standby to 1 replica.

```yaml
# deployments/<svc>-dr.yml  (AZ2)  — claim-processing, pas, ppmc, crm, policy, payment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ppmc-api
  namespace: platform-domain-prd-dr
spec:
  replicas: 1                     # WAS 0 → now always-warm standby
  # HPA unchanged (1→5). Standby resource requests may be trimmed.
```
```yaml
# hpa stays as-is; it scales AZ2 up on real load after cutover
minReplicas: 1
maxReplicas: 5
```
> AZ2 is now always a healthy failover target. The stable endpoint (files 1/2) lands traffic here in <30s with no restart.

## 3b. Repoint Apigee target servers to the stable name
`phi-7wd-apigee-proxies-main/environments/pruinhlth-prd/targetservers.json`
```diff
- "host": "ppmc-api.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia"
+ "host": "ppmc-api.lb1-pruinhlth-prd-chbb3e.pru.intranet.asia"
```
Apply to all 16 internal target servers. With the stable endpoint doing failover you no longer need
per-AZ `IsFallback` XML or a DR-time `target-server-deploy` run.

## 3c. Bug fixes (do first — DR silently fails otherwise)

**Bug #1 (HIGH) — application-dr.yml points to UAT.** Best fix: delete the `dr` Spring profile
entirely and run AZ2 on `prod` (CRM already does this). If kept:
```diff
- gcp.projectId : pruinhlth-nprd-uat-f8hev4-3c6b
- domainSuffix  : lb1-pruinhlth-uat-az2-f8hev4.pru.intranet.asia
- topicPrefix   : dr
+ gcp.projectId : pruinhlth-prod-prd-chbb3e-5648
+ domainSuffix  : lb1-pruinhlth-prd-chbb3e.pru.intranet.asia   # AZ-agnostic
+ topicPrefix   : prod
```

**Bug #2 (MED) — claim-processing DR yaml missing mTLS cert.**
```diff
- # - name: ORGANIZATION_CERT_BASE64        # commented out in DR yaml
- #   valueFrom: { secretKeyRef: { name: sahi-certificates, key: ssl-cert } }
+ - name: ORGANIZATION_CERT_BASE64
+   valueFrom: { secretKeyRef: { name: sahi-certificates, key: ssl-cert } }
```

## 3d. Structural rule (kills DR drift forever)
Replace every hardcoded `...-az1-...` in service config with either a K8s service name
(intra-platform) or the stable endpoint / Apigee (cross-boundary). Then AZ2 runs the identical
prod manifest and Bug #1's class can never recur. Known offenders to fix:
`PPMC domainSuffix`, `filenet.baseUrl`, `PAS bancsHost`, `pas.api.baseUrl`, `mer/ahcOpd apigee URLs`.
