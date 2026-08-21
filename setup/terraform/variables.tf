variable "k8s_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.33"
}

variable "enable_private" {
  type        = bool
  description = "Enable private EKS endpoint and private resources"
  default     = false
}

variable "public_az" {
  type        = string
  description = "Availability Zone suffix for the public subnet"
  default     = "a"
}

variable "private_az" {
  type        = string
  description = "Availability Zone suffix for the private subnet"
  default     = "b"
}