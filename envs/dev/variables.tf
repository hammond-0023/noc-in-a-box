variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "image_tag" {
  description = "Image tag to deploy (git SHA in CI)"
  type        = string
  default     = "bootstrap"
}

variable "desired_count" {
  type    = number
  default = 1
}
