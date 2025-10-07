variable "local_directory" {
  type        = string
  description = "Local directory containing alert JSON files."
}

variable "folders" {
  type = list(object({
    title = string
    uid   = optional(string, "")
  }))
  description = "List of folders to create in Grafana."
}

variable "folder_title" {
  type        = string
  description = "The title of the Grafana folder to associate with alerts."
}

variable "folder_uid" {
  description = "The UID of the folder, defined in config.yaml"
  type        = string
}

variable "default_interval_seconds" {
  type        = number
  default     = 60
  description = "Default interval in seconds for evaluating alerts."
}

variable "datasource_uids" {
  type        = map(string)
  description = "Map of data source names to their respective UIDs."
}
