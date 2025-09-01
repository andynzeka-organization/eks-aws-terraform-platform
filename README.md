# AWS EKS Platform with Terraform

Provision a production‑ready VPC and Amazon EKS cluster, plus optional add‑ons (ALB Controller, EBS CSI, cert‑manager, metrics‑server) and application charts (Argo CD, Grafana, Prometheus).

**Highlights**
- VPC with public/private subnets, IGW, NAT (per‑AZ or shared), and route tables.
- EKS with managed node group, IAM roles, OIDC provider, and IRSA roles.
- Single ALB Ingress for both Grafana and Prometheus using path routing (`/grafana`, `/prometheus`). No domain required — use the ALB DNS name.
- Optional Helm‑based apps under `apps/` with a ready‑to‑use providers setup.
- Worker EC2 instances are tagged with a `Name` (default: `demo-worker-node`).

## Repository Layout

- `main.tf`: wires VPC and EKS modules together
- `providers.tf`, `versions.tf`, `backend.tf`: provider and backend setup
- `variables.tf`, `outputs.tf`: root inputs/outputs
- `modules/vpc`: VPC (VPC, Subnets, IGW, NAT, Routes)
- `modules/eks`: EKS (cluster, node group, IAM, IRSA, kubeconfig helpers)
- `modules/system/*`: Optional system add‑ons (ALB Controller, EBS CSI, etc.)
- `modules/prometheus`, `modules/grafana`, `modules/argocd`: Helm modules
- `apps/*`: Example stacks using the Helm modules with working providers

## Prerequisites

- Terraform 1.3+
- AWS account + credentials configured (e.g., `aws configure`)
- AWS CLI v2, `kubectl`, and `helm` installed (for post‑apply operations)

## Backend Configuration

- The root config uses an S3 backend. Prepare a backend config file:
  - Copy `backend.hcl.example` to `backend.hcl` and set your bucket/key/region/table
  - Initialize with: `terraform init -backend-config=backend.hcl`

## Quick Start

1) Adjust variables in `variables.tf` as needed (see Variables).

2) Initialize, plan, and apply:
- `terraform init -backend-config=backend.hcl`
- `terraform plan`
- `terraform apply`

3) Configure local kubeconfig (done automatically by the EKS module; requires AWS CLI):
- The module runs `aws eks update-kubeconfig --name <cluster> --region <region>` and waits for API health.
- If you prefer manual, run:
  - `aws eks update-kubeconfig --name <your_cluster_name> --region <your_region>`

4) Deploy platform apps (Argo CD, Grafana, Prometheus) with shared ALB Ingress:
- `cd apps/platform`
- `terraform init`
- `terraform apply`
- Outputs to use:
  - `monitoring_ingress_hostname` → ALB DNS
  - `grafana_ingress_url`, `prometheus_ingress_url`
  - `post_install_summary` → handy cheatsheet of URLs and credentials

## Variables (Root)

- `project_name`: name prefix for resources (default: `demo`)
- `vpc_cidr`: VPC CIDR (default: `10.0.0.0/16`)
- `azs`: availability zones to use; if empty, two AZs are auto‑selected
- `public_subnet_cidrs`, `private_subnet_cidrs`: override subnet CIDRs; if empty, they’re derived from `vpc_cidr`
- `enable_nat_per_az`: one NAT per AZ if true; single shared NAT if false
- `aws_region`: AWS region for providers (default: `us-east-1`)
- `eks_cluster_name`: EKS cluster name (default: `demo-eks-cluster`)
- `cluster_version`: Kubernetes version (default: `1.33`)
- `tags`: common tags map for all resources

## Variables (EKS Module)

- `eks_cluster_name`: cluster name (required)
- `kubernetes_version`: e.g., `1.33`
- `subnet_ids`: typically private subnets from VPC module
- `desired_size`, `min_size`, `max_size`: node group scaling (default: 2/1/4)
- `instance_types`: default `["t3.medium"]`
- `capacity_type`: `ON_DEMAND` or `SPOT` (default: `ON_DEMAND`)
- `node_name_tag`: EC2 `Name` tag for worker instances (default: `demo-worker-node`)
- `region`: AWS region (used for kubeconfig update)
- IRSA toggles and policies for ALB Controller, EBS CSI, and optional Argo CD

## Outputs

- `vpc_id`, `public_subnet_ids`, `private_subnet_ids`
- `eks_cluster_name`, `eks_cluster_endpoint`
- `node_group_name`, `node_role_arn`

## Optional Add‑Ons and Apps

- System add‑ons are in `modules/system/*` (ALB Controller, EBS CSI, cert‑manager, metrics‑server). You can consume them from your own stack or extend the root config.
- Example application stacks live under `apps/` and include working Kubernetes/Helm providers:
  - `apps/platform`: Argocd, Grafana, Prometheus in one stack
  - `apps/argocd`, `apps/grafana`, `apps/prometheus`: separate stacks

To deploy an app stack individually, change into the directory and run Terraform there after the cluster is ready (kubeconfig configured). For example:
- `cd apps/argocd | apps/grafana | apps/prometheus`
- `terraform init`
- `terraform apply`

Notes:
- Grafana and Prometheus are installed as `ClusterIP` Services. They are exposed through one external ALB Ingress at `/grafana` and `/prometheus`.
- Argo CD is installed as `LoadBalancer` by default (NLB). You can switch it to Ingress as well if you prefer a single ALB for everything.

## How It Works

- The VPC module creates a VPC and per‑AZ public/private subnets, tags subnets for ELB/ILB usage and (optionally) cluster discovery, sets up IGW/NAT, and associates routes.
- The EKS module creates IAM roles, the EKS control plane, OIDC provider, and a managed node group. Worker instances inherit the `Name` tag via a launch template.
- A helper in the EKS module updates your kubeconfig and waits for API readiness so subsequent Helm deployments can succeed.
- The platform stack creates a Kubernetes Ingress (class `alb`) that routes a single external ALB to two Services using paths:
  - `/grafana` → `Service grafana:80` (Grafana configured with `grafana.ini` to serve from sub‑path)
  - `/prometheus` → `Service prometheus-server:80` (Prometheus configured with `server.prefixURL`)

ALB Controller
- Ensure the AWS Load Balancer Controller is installed in the cluster so Ingress resources provision an ALB.
- This repo includes `modules/system/alb-controller` you can consume from your own stack. It requires:
  - Cluster name, region, VPC ID
  - IRSA role for the controller service account

## Storage & Alertmanager

- For training/lab use, Alertmanager persistence is disabled and Alertmanager itself is turned off by default to avoid PVC scheduling issues on clusters without storage.
- To enable Alertmanager with storage:
  1. Install the EBS CSI driver (either EKS addon or the Helm module under `modules/system/ebs-csi`).
  2. Create a default `gp3` StorageClass (provisioner: `ebs.csi.aws.com`).
  3. Re‑enable Alertmanager in the Prometheus module and (optionally) enable persistence.

## Destroy

- Run `terraform destroy` from the root. The node group is deleted before the cluster. If AWS reports the cluster has nodegroups attached, destroy the node group first:
- `terraform destroy -target=module.eks.aws_eks_node_group.worker-node`
- Then `terraform destroy` again for the rest.

## Troubleshooting

- Helm release timeouts: ensure the cluster API is reachable and your kubeconfig is updated. For Prometheus, persistence is disabled and Alertmanager is off by default to avoid PVC Pending on clusters without a default StorageClass.
- Subnet math: subnets are derived as `/20` by default; adjust the `cidrsubnet` logic in the root `main.tf` if you need different sizes.
- Resource address changes: if you rename resources inside modules, use `terraform state mv` to keep state aligned and avoid deletion ordering issues.

## Recent Changes (How‑To recap)
- Shared ALB Ingress added for Grafana and Prometheus. Use `terraform output monitoring_ingress_hostname` and open `http://<ALB-DNS>/grafana` or `/prometheus`.
- Grafana and Prometheus use `ClusterIP`; Argo CD remains `LoadBalancer` by default.
- Prometheus: `server.prefixURL` set, Alertmanager disabled; persistence forced off. Enable storage to re‑enable Alertmanager safely.
- Worker node Name tags applied via launch template; override with EKS module var `node_name_tag`.
# Renamed project
