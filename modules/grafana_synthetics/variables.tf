variable "synthetics_checks" {
  description = "List of synthetic monitoring checks"
  type = list(object({
    job_name    = string
    target      = string
    frequency   = number
    timeout     = number
    url         = string
    api_key     = string
    script_path = string
  }))
}
