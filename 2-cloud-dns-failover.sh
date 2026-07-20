#!/usr/bin/env bash
# =============================================================================
# PIECE 1 — Alternative (Option B): Cloud DNS health-checked FAILOVER routing.
# Most minimal (no new LB). Caveat: DNS TTL means failover isn't connection-instant.
#
# Two ways to use it:
#   (a) Clean AZ-agnostic name  -> migrate callers to it (best long-term).
#   (b) ZERO-COORDINATION shortcut: turn the EXISTING ...-az1-... names into
#       failover records so hardcoded direct callers fail over with no code change.
# =============================================================================

ZONE="pruinhlth-internal"                                  # your Cloud DNS zone
AZ1_ILB="<AZ1_ingress_internal_LB_forwarding_rule>"        # primary (health-checked)
AZ2_IP="<AZ2_ingress_internal_IP>"                         # backup target

# --- (a) clean stable name ---------------------------------------------------
gcloud dns record-sets create "ppmc-api.lb1-pruinhlth-prd-chbb3e.pru.intranet.asia." \
  --zone="$ZONE" --type=A --ttl=30 \
  --routing-policy-type=FAILOVER \
  --routing-policy-primary-data="$AZ1_ILB" \
  --enable-health-checking \
  --routing-policy-backup-data-type=IP \
  --routing-policy-backup-data="$AZ2_IP"

# --- (b) zero-coordination: make the existing az1 name itself fail over -------
# (repeat per service host that external teams have hardcoded)
gcloud dns record-sets update "ppmc-api.lb1-pruinhlth-prd-az1-chbb3e.pru.intranet.asia." \
  --zone="$ZONE" --type=A --ttl=30 \
  --routing-policy-type=FAILOVER \
  --routing-policy-primary-data="$AZ1_ILB" \
  --enable-health-checking \
  --routing-policy-backup-data-type=IP \
  --routing-policy-backup-data="$AZ2_IP"

# Keep TTL low (30-60s). Pair with warm AZ2 (file 3) so the backup is always alive.
