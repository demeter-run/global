module "grafana_dashboard" {
  for_each = {
    for folder in local.env_vars.grafana.folders :
    folder.local_directory => folder
  }
  source          = "./modules/grafana_dashboard"
  local_directory = each.value.local_directory
  grafana_title   = each.value.grafana_title
  datasource_uids = {
    # This is a template variable used in Demeter dashboards
    datasource_uid = module.grafana_data_sources.uids[each.value.datasource_uids.datasource_uid]
  }
}
