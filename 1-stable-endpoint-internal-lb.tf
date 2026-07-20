# =============================================================================
# PIECE 1 — Stable AZ-agnostic endpoint (Option A: regional internal L4 NLB with
# failover backend). One VIP fronts AZ1 + AZ2 nginx-ingress; TLS passes through.
# Adapt names/NEGs to the pruinhlth-prod-prd-chbb3e Terraform repo.
# =============================================================================

variable "az1_ingress_neg" { description = "Zonal/Internal NEG or instance group of AZ1 nginx-ingress" }
variable "az2_ingress_neg" { description = "Zonal/Internal NEG or instance group of AZ2 nginx-ingress" }
variable "subnetwork"      { description = "Internal subnet for the ILB VIP" }
variable "network"         { description = "VPC self link" }

resource "google_compute_region_health_check" "ingress" {
  name               = "phi-ingress-hc"
  region             = "asia-south1"
  check_interval_sec = 5
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 2
  https_health_check {
    port         = 443
    request_path = "/healthz"   # nginx-ingress health endpoint
  }
}

resource "google_compute_region_backend_service" "ingress" {
  name                  = "phi-ingress-bes"
  region                = "asia-south1"
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.ingress.id]

  # PRIMARY = AZ1
  backend {
    group          = var.az1_ingress_neg
    balancing_mode = "CONNECTION"
  }
  # FAILOVER = AZ2
  backend {
    group          = var.az2_ingress_neg
    balancing_mode = "CONNECTION"
    failover       = true
  }

  failover_policy {
    drop_traffic_if_unhealthy            = false   # keep serving via failover backend
    disable_connection_drain_on_failover = false
    failover_ratio                       = 1.0     # flip all traffic when primary unhealthy
  }
}

resource "google_compute_forwarding_rule" "ingress_vip" {
  name                  = "phi-ingress-vip"
  region                = "asia-south1"
  load_balancing_scheme = "INTERNAL"
  ip_protocol           = "TCP"
  ports                 = ["443"]
  backend_service       = google_compute_region_backend_service.ingress.id
  network               = var.network
  subnetwork            = var.subnetwork
  allow_global_access   = false
}

# Then point the AZ-agnostic DNS name at google_compute_forwarding_rule.ingress_vip.ip_address:
#   *.lb1-pruinhlth-prd-chbb3e.pru.intranet.asia  ->  <VIP>
# Every caller (Apigee target servers + direct callers) uses this name. DR = zero routing changes.
