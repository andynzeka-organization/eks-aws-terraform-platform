resource "kubernetes_namespace" "argocd_namespace" {
  count = var.create_namespace ? 1 : 0
  metadata { name = var.namespace }
}

locals {
  argocd_crds = [
    "applications.argoproj.io",
    "appprojects.argoproj.io",
    "argocdexports.argoproj.io",
    "applicationsets.argoproj.io"
  ]
}

resource "null_resource" "reset_argocd_crd_annotations" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      for crd in ${join(" ", local.argocd_crds)}; do
        kubectl annotate crd "$crd" meta.helm.sh/release-name- --overwrite >/dev/null 2>&1 || true
        kubectl annotate crd "$crd" meta.helm.sh/release-namespace- --overwrite >/dev/null 2>&1 || true
      done
    EOT
  }

  triggers = {
    cleanup = timestamp()
  }
}

resource "helm_release" "argocd" {
  name              = "argocd"
  repository        = "https://argoproj.github.io/argo-helm"
  chart             = "argo-cd"
  version           = "5.51.6" # match with your values
  namespace         = var.namespace
  wait              = true
  timeout           = 300
  dependency_update = true
  atomic            = true
  cleanup_on_fail   = true

  values = [yamlencode({
    nameOverride     = "argocd"
    fullnameOverride = "argocd"
    configs = {
      params = {
        "server.insecure" = true
        "server.basehref" = "/argocd"
        "server.rootpath" = "/argocd"
      }
    }
    crds = {
      install = true
    }
    server = {
      service = {
        type        = var.service_type
        annotations = var.service_annotations
      }
      ingress = {
        enabled = false
      }
    }
  })]

  depends_on = [
    kubernetes_namespace.argocd_namespace,
    null_resource.reset_argocd_crd_annotations,
  ]
}

data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = var.namespace
  }
  depends_on = [helm_release.argocd]
}

data "kubernetes_secret" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = var.namespace
  }
  depends_on = [helm_release.argocd]
}
