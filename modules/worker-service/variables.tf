variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "cluster_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "image" {
  type = string
}

variable "command" {
  type = list(string)
}

variable "environment" {
  type    = map(string)
  default = {}
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

variable "log_retention_days" {
  type    = number
  default = 7
}
