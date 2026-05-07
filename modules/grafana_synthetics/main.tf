data "grafana_synthetic_monitoring_probes" "main" {}

resource "grafana_synthetic_monitoring_check" "checks" {
  for_each = { for check in var.synthetics_checks : check.target => check }

  job     = each.value.job_name
  target  = each.value.target
  enabled = true
  probes  = [data.grafana_synthetic_monitoring_probes.main.probes.Ohio]

  settings {
    scripted {
      script = sensitive(templatefile(each.value.script_path, {
        url     = each.value.url
        api_key = each.value.api_key
      }))
    }
  }

  frequency = each.value.frequency
  timeout   = each.value.timeout
}
