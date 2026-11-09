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

variable "datadog_api_key" {
  description = "Datadog API key (from the DD_API_KEY GitHub secret)"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog application key (from the DD_APP_KEY GitHub secret)"
  type        = string
  sensitive   = true
}

variable "datadog_api_url" {
  description = "Datadog API URL for your site. EU: https://api.datadoghq.eu/  US1: https://api.datadoghq.com/"
  type        = string
  default     = "https://api.datadoghq.eu/"
}

variable "tuned_alerts" {
  description = "false = deliberately noisy 5xx monitor (before). true = tuned monitor (after)."
  type        = bool
  default     = false
}
