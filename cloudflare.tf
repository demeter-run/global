provider "cloudflare" {}

variable "cloudflare_account_id" {
  default = "ac5ad90cf6f83abc85ee304a2bb2de73"
}
variable "cloudflare_zone_id" {
  default = "a4f238868ab16e77e1ba5210cb7f223d"
}
variable "cloudflare_zone_name" {
  default = "dmtr.host"
}

locals {
  cloudflare_zone_names = [
    var.cloudflare_zone_name,
  ]
}

locals {
  demeter_providers = [
    {
      name = "blinklabs-us"
      blockfrost_m1 = {
        enabled = true
        address = "demeter.blinklabs.cloud"
        port    = 3001
      }
      kupo_m1 = {
        enabled = true
        address = "demeter.blinklabs.cloud"
        port    = 4442
      }
      ogmios_m1 = {
        enabled = true
        address = "demeter.blinklabs.cloud"
        port    = 3032
      }
      tx_submit_api = {
        enabled = false
        address = "tx-submit-api.blinklabs.cloud"
      }
      utxorpc = {
        enabled           = false
        port              = 50051
        health_check_port = 9187
        networks = {
          cardano_mainnet = "mainnet.dolos.blinklabs.cloud"
          cardano_preprod = "preprod.dolos.blinklabs.cloud"
          cardano_preview = "preview.dolos.blinklabs.cloud"
        }
      }
    },
    {
      name = "txpipe-m2"
      blockfrost_m1 = {
        enabled = true
        address = "all.blockfrost-m1.demeter.run"
        port    = 443
      }
      kupo_m1 = {
        enabled = true
        address = "all.kupo-m1.demeter.run"
        port    = 443
      }
      ogmios_m1 = {
        enabled = true
        address = "all.ogmios-m1.demeter.run"
        port    = 443
      }
      tx_submit_api = {
        enabled = false
        address = "submitapi-m1.demeter.run"
      }
      utxorpc = {
        enabled           = false
        port              = 0
        health_check_port = 0
        networks = {
          cardano_mainnet = ""
          cardano_preprod = ""
          cardano_preview = ""
        }
      }
    },
  ]
}


# We use for_each on this to expose the domain names in the resource names
resource "cloudflare_zone" "this" {
  for_each = toset(local.cloudflare_zone_names)
  account = {
    id = var.cloudflare_account_id
  }
  name = each.key
}

resource "cloudflare_certificate_pack" "this" {
  zone_id               = cloudflare_zone.this[var.cloudflare_zone_name].id
  certificate_authority = "google"

  // At most 50.
  hosts = [
    "*.dmtr.host",

    // Ogmios
    "*.ogmios-m1.dmtr.host",
    "*.cardano-mainnet-v6.ogmios-m1.dmtr.host",
    "*.cardano-preprod-v6.ogmios-m1.dmtr.host",
    "*.cardano-preview-v6.ogmios-m1.dmtr.host",
    "*.vector-mainnet-v6.ogmios-m1.dmtr.host",
    "*.vector-testnet-v6.ogmios-m1.dmtr.host",
    "*.prime-testnet-v6.ogmios-m1.dmtr.host",

    // Kupo
    "*.kupo-m1.dmtr.host",
    "*.cardano-mainnet-v2.kupo-m1.dmtr.host",
    "*.cardano-preprod-v2.kupo-m1.dmtr.host",
    "*.cardano-preview-v2.kupo-m1.dmtr.host",

    // Blockfrost
    "*.blockfrost-m1.dmtr.host",
    "blockfrost-m1.dmtr.host",
    "*.cardano-mainnet.blockfrost-m1.dmtr.host",
    "*.cardano-preprod.blockfrost-m1.dmtr.host",
    "*.cardano-preview.blockfrost-m1.dmtr.host",
    "*.vector-mainnet.blockfrost-m1.dmtr.host",
    "*.vector-testnet.blockfrost-m1.dmtr.host",

    // DBSync
    "*.dbsync-v3.dmtr.host",

    // U5C
    "*.utxorpc-m1.dmtr.host",

    // Balius

    // TRP
    "*.trp-m1.dmtr.host",

    // Mumak
    "*.mumak-m0.dmtr.host",
  ]
  type              = "advanced"
  validation_method = "txt"
  validity_days     = 90
}

# Kupo
resource "cloudflare_load_balancer_monitor" "kupo_m1_monitor" {
  account_id  = var.cloudflare_account_id
  type        = "https"
  description = "Health Check for Kupo"
  path        = "/dmtr_health"
  # port omitted so each origin is health-checked on its own port (blinklabs-us: 4442, txpipe-m2: 443)
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
}

resource "cloudflare_load_balancer_pool" "kupo_m1" {
  name       = "Kupo"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.kupo_m1_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.kupo_m1.address != "" ? p.kupo_m1.address : "${p.name}.${var.cloudflare_zone_name}"
      port    = p.kupo_m1.port != 0 ? p.kupo_m1.port : null
    } if p.kupo_m1.enabled
  ]
}

resource "cloudflare_load_balancer" "kupo_m1_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.kupo-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.kupo_m1.id]
  fallback_pool   = cloudflare_load_balancer_pool.kupo_m1.id
  proxied         = true
  steering_policy = "off"
}

# Ogmios M1 (top-level splat)
resource "cloudflare_load_balancer_monitor" "ogmios_m1_monitor" {
  account_id  = var.cloudflare_account_id
  type        = "https"
  description = "Health check for OgmiosM1"
  path        = "/healthz"
  # port omitted so each origin is health-checked on its own port
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "ogmios_m1" {
  name       = "Ogmios"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.ogmios_m1_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.ogmios_m1.address != "" ? p.ogmios_m1.address : "${p.name}.${var.cloudflare_zone_name}"
      port    = p.ogmios_m1.port != 0 ? p.ogmios_m1.port : null
    } if p.ogmios_m1.enabled
  ]
}

resource "cloudflare_load_balancer" "ogmios_m1_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.ogmios-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.ogmios_m1.id]
  fallback_pool   = cloudflare_load_balancer_pool.ogmios_m1.id
  proxied         = true
  steering_policy = "off"
}

# Tx-Submit-API
resource "cloudflare_load_balancer_pool" "tx_submit_api_m1" {
  count = anytrue([for p in local.demeter_providers : p.tx_submit_api.enabled]) ? 1 : 0
  name  = "TxSubmitApiM1"

  account_id = var.cloudflare_account_id
  # TODO: add monitor when tx-submit-api supports reliable health checks
  # monitor    = cloudflare_load_balancer_monitor.tx_submit_api_m1_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.tx_submit_api.address != "" ? p.tx_submit_api.address : "${p.name}.${var.cloudflare_zone_name}"
    } if p.tx_submit_api.enabled
  ]
}

resource "cloudflare_load_balancer" "tx_submit_api_m1" {
  count           = anytrue([for p in local.demeter_providers : p.tx_submit_api.enabled]) ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = "*.submitapi-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.tx_submit_api_m1[0].id]
  fallback_pool   = cloudflare_load_balancer_pool.tx_submit_api_m1[0].id
  proxied         = true
  steering_policy = "off"
}

# Blockfrost
resource "cloudflare_load_balancer_monitor" "blockfrost_m1_monitor" {
  account_id  = var.cloudflare_account_id
  type        = "https"
  description = "Health check for BlockfrostM1"
  path        = "/dmtr_health"
  # port omitted so each origin is health-checked on its own port (blinklabs-us: 3001, txpipe-m2: 443)
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
}

resource "cloudflare_load_balancer_pool" "blockfrost_m1" {
  name       = "Blockfrost"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.blockfrost_m1_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.blockfrost_m1.address != "" ? p.blockfrost_m1.address : "${p.name}.${var.cloudflare_zone_name}"
      port    = p.blockfrost_m1.port != 0 ? p.blockfrost_m1.port : null
    } if p.blockfrost_m1.enabled
  ]
}

resource "cloudflare_load_balancer" "blockfrost_m1_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.blockfrost-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.blockfrost_m1.id]
  fallback_pool   = cloudflare_load_balancer_pool.blockfrost_m1.id
  proxied         = true
  steering_policy = "off"
}

# UTxORPC
resource "cloudflare_load_balancer_monitor" "utxorpc_preview_monitor" {
  count          = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for UtxorpcPreview"
  path           = "/dmtr_health"
  port           = try(([for p in local.demeter_providers : p.utxorpc.health_check_port if p.utxorpc.enabled && p.utxorpc.health_check_port != 0])[0], null)
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "utxorpc_preview" {
  count      = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  name       = "UtxorpcPreview"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.utxorpc_preview_monitor[0].id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.utxorpc.networks.cardano_preview != "" ? p.utxorpc.networks.cardano_preview : "${p.name}.${var.cloudflare_zone_name}"
      port    = p.utxorpc.port != 0 ? p.utxorpc.port : null
    } if p.utxorpc.enabled
  ]
}

resource "cloudflare_load_balancer" "utxorpc_preview" {
  count           = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preview-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_preview[0].id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_preview[0].id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "utxorpc_preview_splat" {
  count           = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preview-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_preview[0].id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_preview[0].id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "utxorpc_preprod_monitor" {
  count          = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for UtxorpcPreprod"
  path           = "/dmtr_health"
  port           = try(([for p in local.demeter_providers : p.utxorpc.health_check_port if p.utxorpc.enabled && p.utxorpc.health_check_port != 0])[0], null)
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "utxorpc_preprod" {
  count      = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  name       = "UtxorpcPreprod"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.utxorpc_preprod_monitor[0].id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.utxorpc.networks.cardano_preprod != "" ? p.utxorpc.networks.cardano_preprod : "${p.name}.${var.cloudflare_zone_name}"
      port    = p.utxorpc.port != 0 ? p.utxorpc.port : null
    } if p.utxorpc.enabled
  ]
}

resource "cloudflare_load_balancer" "utxorpc_preprod" {
  count           = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preprod-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_preprod[0].id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_preprod[0].id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "utxorpc_preprod_splat" {
  count           = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preprod-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_preprod[0].id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_preprod[0].id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "utxorpc_mainnet_monitor" {
  count          = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for UtxorpcMainnet"
  path           = "/dmtr_health"
  port           = try(([for p in local.demeter_providers : p.utxorpc.health_check_port if p.utxorpc.enabled && p.utxorpc.health_check_port != 0])[0], null)
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "utxorpc_mainnet" {
  count      = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  name       = "UtxorpcMainnet"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.utxorpc_mainnet_monitor[0].id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.utxorpc.networks.cardano_mainnet != "" ? p.utxorpc.networks.cardano_mainnet : "${p.name}.${var.cloudflare_zone_name}"
      port    = p.utxorpc.port != 0 ? p.utxorpc.port : null
    } if p.utxorpc.enabled
  ]
}

resource "cloudflare_load_balancer" "utxorpc_mainnet" {
  count           = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-mainnet-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_mainnet[0].id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_mainnet[0].id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "utxorpc_mainnet_splat" {
  count           = anytrue([for p in local.demeter_providers : p.utxorpc.enabled]) ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-mainnet-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_mainnet[0].id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_mainnet[0].id
  proxied         = true
  steering_policy = "off"
}
