provider "grafana" {
  url  = local.env_vars.grafana.cloud.url
  auth = local.env_vars.grafana.cloud.auth
}
