provider "grafana" {
  url             = local.env_vars.grafana.cloud.url
  auth            = local.env_vars.grafana.cloud.auth
  sm_url          = local.env_vars.grafana.cloud.sm_url
  sm_access_token = local.env_vars.grafana.cloud.sm_access_token
}
