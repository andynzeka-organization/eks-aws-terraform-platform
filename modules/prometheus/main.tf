resource "kubernetes_namespace" "ns" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

/*
  Prometheus helm_release removed per request. Namespace resource retained
  for compatibility if module is referenced in the future.
*/
