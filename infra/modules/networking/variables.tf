# =============================================================================
# Networking Module — Variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet" {
  description = "Whether the subnet should auto-assign public IPs on launch"
  type        = bool
  default     = true
}

variable "enable_internet_gateway" {
  description = "Create an Internet Gateway and a default route. Set to false for air-gapped builds that rely on VPC endpoints."
  type        = bool
  default     = true
}

variable "enable_packer_endpoints" {
  description = "Create VPC endpoints for EC2 and STS (required when enable_internet_gateway = false so Packer can reach AWS APIs)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
