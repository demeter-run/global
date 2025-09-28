output "uids" {
  value       = { for name, ds in grafana_data_source.this : name => ds.uid }
  description = "Map of data source names to their respective UIDs."
}
