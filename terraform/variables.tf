variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "node_instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
  default     = ["t3.small"]  # ~$15/mo vs t3.medium ~$30/mo per node
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1  # Single node for cost savings
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 2  # Reduced from 4 to limit cost exposure
}