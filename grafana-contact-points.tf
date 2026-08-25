# Manages the "#infra-alerts" contact point that every Demeter alert rule group
# routes to (notification_settings.receiver). Grafana rejects rule groups whose
# receiver does not exist, so this must be provisioned before the alerts.
#
# The Slack incoming webhook URL is a secret and is read from the sops-encrypted
# config.yaml (grafana.cloud.slack_webhook_url), matching how the other Grafana
# credentials (auth, sm_access_token) are stored. Add it with:
#   sops config.yaml   # then under grafana.cloud add: slack_webhook_url: <url>
resource "grafana_contact_point" "infra_alerts" {
  name = "#infra-alerts"

  slack {
    url = try(local.env_vars.grafana.cloud.slack_webhook_url, "")
  }
}
