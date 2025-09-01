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
  description = "Service type for Prometheus server"
  type        = string
  default     = "ClusterIP"
}

variable "server_service_annotations" {
  description = "Annotations for Prometheus server Service (when type LoadBalancer)"
  type        = map(string)
  default     = {}
}

variable "alertmanager_service_type" {
  description = "Service type for Alertmanager"
  type        = string
  default     = "ClusterIP"
}

variable "pushgateway_service_type" {
  description = "Service type for Pushgateway"
  type        = string
  default     = "ClusterIP"
}

variable "server_persistence_enabled" {
  description = "Enable PVC for Prometheus server"
  type        = bool
  default     = false
}

variable "alertmanager_persistence_enabled" {
  description = "Enable PVC for Alertmanager"
  type        = bool
  default     = false
}
