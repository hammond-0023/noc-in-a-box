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

variable "worker_desired_count" {
  description = "Set to 0 to simulate a dead worker (stuck-queue drill)"
  type        = number
  default     = 1
}

variable "alert_email" {
  description = "Email for alarm notifications. Leave empty to skip the subscription."
  type        = string
  default     = ""
}
