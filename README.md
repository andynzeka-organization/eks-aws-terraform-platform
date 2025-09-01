# AWS VPC + EKS Terraform

This repo contains two Terraform modules (VPC and EKS) and a root configuration that wires them together for a multi-AZ Amazon EKS deployment with IRSA roles for the AWS Load Balancer Controller and EBS CSI driver. ArgoCD IRSA is optional.

## Structure

- `modules/vpc`: Core AWS-native networking (VPC, subnets, IGW, NAT, route tables, associations)
- `modules/eks`: EKS cluster, node group, IAM roles, OIDC provider, IRSA roles
- Root: Providers, backend, and module wiring

## Backend

The root `terraform` block declares an S3 backend. Provide settings via a backend config file:

1. Copy `backend.hcl.example` to `backend.hcl` and edit values.
2. Initialize Terraform with backend configuration:

   terraform init -backend-config=backend.hcl

## Usage

1. Review `variables.tf` defaults. Key inputs:
   - `project_name`: base name for resources
   - `aws_region`: region to deploy into
   - `vpc_cidr`: VPC CIDR
   - `az_count`: number of AZs (2–3 typical)
2. Plan and apply:

   terraform plan
   terraform apply

## Notes

- VPC module supports one NAT per AZ (`nat_gateway_per_az = true`) or a single NAT (`false`).
- EKS node group autoscaling: min=2, desired=2, max=4 by default.
- IRSA roles:
  - AWS Load Balancer Controller: role created; attach your policy via `lb_controller_policy_arn` or provide `lb_controller_policy_json` to create it inline.
  - EBS CSI driver: role created and attaches AWS-managed `AmazonEBSCSIDriverPolicy`.
  - ArgoCD: off by default; enable and attach policy ARN or JSON as needed.
- Subnets are derived from the VPC CIDR. Adjust the `cidrsubnet` math in `main.tf` if you require different sizing.

