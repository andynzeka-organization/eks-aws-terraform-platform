variable "namespace" {
  description = "Namespace to install Prometheus"
  type        = string
  default     = "monitoring"
}

variable "create_namespace" {
  description = "Create the namespace if it does not exist"
  type        = bool
  default     = true
}

variable "server_service_type" {
  description = "Kubernetes Service type for Prometheus server (ClusterIP or LoadBalancer)"
  type        = string
  default     = "ClusterIP"
}

variable "server_service_annotations" {
  description = "Additional annotations for the Prometheus server Service"
  type        = map(string)
  default     = {}
}

