variable "eks_cluster_domain" {
  type        = string
  description = "Route53 domain for the cluster."
  default     = "lonelyplanet-digital.sandbox.redventures.io"
}

variable "acm_certificate_domain" {
  type        = string
  description = "Route53 certificate domain"
  default     = "*.lonelyplanet-digital.sandbox.redventures.io"
}
