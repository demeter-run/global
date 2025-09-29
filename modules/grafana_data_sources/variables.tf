variable "data_sources" {
  type = map(object({
    type = string
    name = string
    url  = string
    # Optional field for Private Data Source Connect
    pdc = optional(string)
  }))
  description = "Map of data sources with type, name, URL, and optional PDC configuration."
}
