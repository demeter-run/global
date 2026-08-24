module "grafana_alerts" {
  for_each = {
    for alert in local.env_vars.grafana.alerts :
    alert.grafana_title => alert
  }
  source          = "./modules/grafana_alerts"
  local_directory = each.value.local_directory
  folder_title    = each.value.grafana_title
  folder_uid      = each.value.folder_uid
  folders = [
    {
      title = each.value.grafana_title
      uid   = each.value.folder_uid
    }
  ]
  datasource_uids = module.grafana_data_sources.uids
}
