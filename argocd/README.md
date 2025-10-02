ArgoCD Terraform Module

Overview
- Deploys ArgoCD into an existing EKS cluster and exposes it via AWS Load Balancer Controller (ALB) Ingress.
- Self-contained: does not create VPC/EKS; only relies on cluster info and public subnets.

Inputs
- eks_cluster_name (string, required): EKS cluster name.
- aws_region (string, required): AWS region of the cluster.
- public_subnet_ids (list(string), required): Public subnet IDs for the ALB.
- namespace (string, default: "argocd"): Namespace for ArgoCD.
- alb_group_name (string, default: "argocd"): ALB ingress group name.
- wait_for_alb_controller (bool, default: true): Wait for ALB controller readiness before creating Ingress.
- tags (map(string), optional): Tags for supported resources.

Outputs
- argocd_ingress_hostname: ALB DNS hostname.
- argocd_url: Convenience URL for ArgoCD (http://<hostname>/argocd).

Order of Operation
1) Configure providers from the EKS cluster identity (aws, kubernetes, helm).
2) Create namespace.
3) Install ArgoCD Helm chart (server at /argocd).
4) Wait for argocd-server deployment to be Available.
5) Optionally wait for ALB controller to be Available (kube-system).
6) Create ALB Ingress pointing to the ArgoCD server Service.
7) Wait for Ingress hostname to be assigned.
8) On destroy, strip ingress finalizers to avoid hangs.

Example Usage
module "argocd" {
  source            = "./argocd"
  eks_cluster_name  = "demo-eks-cluster"
  aws_region        = "us-east-1"
  public_subnet_ids = ["subnet-abc", "subnet-def"]
  namespace         = "argocd"
  alb_group_name    = "argocd"
}

Notes
- Requires AWS Load Balancer Controller to be installed in the cluster.
- Health checks accept 200–399 on /argocd/ to tolerate redirects.
- Admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

