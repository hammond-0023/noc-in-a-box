variable "name" {
  description = "Name prefix for network resources"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.20.0.0/16"
}
