resource "grafana_folder" "this" {
  title = var.grafana_title
}

resource "grafana_dashboard" "this" {
  for_each = {
    for file in fileset("${path.root}/${var.local_directory}", "*.json") :
    file => jsondecode(templatefile("${path.root}/${var.local_directory}/${file}", var.datasource_uids))
  }

  config_json = jsonencode(each.value)
  folder      = grafana_folder.this.id
}
