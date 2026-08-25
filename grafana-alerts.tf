module "grafana_alerts" {
  for_each = {
    for alert in local.env_vars.grafana.alerts :
    alert.grafana_title => alert
  }
  source          = "./modules/grafana_alerts"
  local_directory = each.value.local_directory
  folder_title    = each.value.grafana_title
  folder_uid      = each.value.folder_uid
  datasource_uids = module.grafana_data_sources.uids

  # Rule groups reference the "#infra-alerts" receiver, which must exist first.
  depends_on = [grafana_contact_point.infra_alerts]
}
