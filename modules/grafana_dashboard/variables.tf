variable "datasource_uids" {
  type        = map(string)
  description = "Map of data source names to their respective UIDs."
}

variable "grafana_title" {
  type        = string
  description = "Title for the Grafana folder."
}

variable "local_directory" {
  type        = string
  description = "Local directory containing dashboard JSON files."
}
