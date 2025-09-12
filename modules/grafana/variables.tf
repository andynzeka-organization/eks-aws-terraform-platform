variable "namespace" {
  description = "Namespace to install Grafana"
  type        = string
  default     = "monitoring"
}

variable "create_namespace" {
  description = "Create the namespace if it does not exist"
  type        = bool
  default     = true
}

variable "service_type" {
  description = "Kubernetes Service type for Grafana (ClusterIP or LoadBalancer)"
  type        = string
  default     = "ClusterIP"
}

variable "service_annotations" {
  description = "Additional annotations for the Grafana Service"
  type        = map(string)
  default     = {}
}

variable "admin_password" {
  description = "Grafana admin password; if null, one is generated"
  type        = string
  default     = null
  sensitive   = true
}

