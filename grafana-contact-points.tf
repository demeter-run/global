# Manages the "#infra-alerts" contact point that every Demeter alert rule group
# routes to (notification_settings.receiver). Grafana rejects rule groups whose
# receiver does not exist, so this must be provisioned before the alerts.
#
# The infrastructure-alerts channel uses a Discord incoming webhook (matching the
# sibling infrastructure repo, which notifies the same channel via the
# DISCORD_INFRA_ALERTS_WEBHOOK_URL secret). The webhook URL is a secret and is read
# from the sops-encrypted config.yaml (grafana.cloud.discord_webhook_url), matching
# how the other Grafana credentials (auth, sm_access_token) are stored. Add it with:
#   sops config.yaml   # then under grafana.cloud add: discord_webhook_url: <url>
resource "grafana_contact_point" "infra_alerts" {
  name = "#infra-alerts"

  discord {
    url = try(local.env_vars.grafana.cloud.discord_webhook_url, "")
  }
}
