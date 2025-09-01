variable "name" {
  description = "Name prefix for VPC resources"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "List of availability zones to use"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDRs, one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDRs, one per AZ"
  type        = list(string)
}

variable "enable_nat_per_az" {
  description = "Create one NAT Gateway per AZ (true) or a single NAT (false)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags to apply"
  type        = map(string)
  default     = {}
}

variable "cluster_name_for_tag" {
  description = "Optional: if set, tag subnets with kubernetes.io/cluster/<name>=shared for ALB/NLB discovery"
  type        = string
  default     = null
}
