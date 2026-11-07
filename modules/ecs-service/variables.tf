variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "image" {
  description = "Full container image URI including tag"
  type        = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "environment" {
  type    = map(string)
  default = {}
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB. Restrict to your IP if you like."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
