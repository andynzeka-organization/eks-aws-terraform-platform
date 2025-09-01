variable "namespace" {
  description = "Namespace to install Grafana"
  type        = string
  default     = "grafana"
}

variable "create_namespace" {
  description = "Create the namespace if it does not exist"
  type        = bool
  default     = true
}

variable "admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "service_type" {
  description = "Service type for Grafana"
  type        = string
  default     = "ClusterIP"
}

variable "service_annotations" {
  description = "Service annotations (for LB configuration when type is LoadBalancer)"
  type        = map(string)
  default     = {}
}

