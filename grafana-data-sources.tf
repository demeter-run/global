module "grafana_data_sources" {
  source       = "./modules/grafana_data_sources"
  data_sources = local.env_vars.grafana.data_sources
}
