module "grafana_synthetics" {
  source = "./modules/grafana_synthetics"

  synthetics_checks = [
    for check in local.env_vars.grafana.synthetics_checks : {
      job_name    = check.job_name
      target      = check.target
      frequency   = check.frequency
      timeout     = check.timeout
      url         = check.url
      api_key     = check.api_key
      script_path = "${path.root}/${check.script_path}"
    }
  ]
}
