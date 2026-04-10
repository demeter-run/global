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
      blockfrost = {
        enabled = true
        networks = {
          cardano_preview = "preview.dolos.blinklabs.cloud"
          cardano_preprod = "preprod.dolos.blinklabs.cloud"
          cardano_mainnet = "mainnet.dolos.blinklabs.cloud"
        }
      }
      kupo = {
        enabled = true
        networks = {
          cardano_preview = "preview.kupo.blinklabs.cloud"
          cardano_preprod = "preprod.kupo.blinklabs.cloud"
          cardano_mainnet = "kupo.blinklabs.cloud"
        }
      }
      ogmios = {
        enabled = true
        networks = {
          cardano_preview = "preview.ogmios.blinklabs.cloud"
          cardano_preprod = "preprod.ogmios.blinklabs.cloud"
          cardano_mainnet = "ogmios.blinklabs.cloud"
        }
      }
      tx_submit_api = {
        enabled = true
        address = "tx-submit-api.blinklabs.cloud"
      }
      utxorpc = {
        enabled = true
        networks = {
          cardano_preview = "preview.dolos.blinklabs.cloud"
          cardano_preprod = "preprod.dolos.blinklabs.cloud"
          cardano_mainnet = "mainnet.dolos.blinklabs.cloud"
        }
      }
    },
    {
      name = "txpipe-m2"
      blockfrost = {
        enabled = false
        networks = {
          cardano_preview = ""
          cardano_preprod = ""
          cardano_mainnet = ""
        }
      }
      kupo = {
        enabled = true
        networks = {
          cardano_preview = "preview-v2.kupo-m1.demeter.run"
          cardano_preprod = "preprod-v2.kupo-m1.demeter.run"
          cardano_mainnet = "mainnet-v2.kupo-m1.demeter.run"
        }
      }
      ogmios = {
        enabled = true
        networks = {
          cardano_preview = "preview-v6.ogmios-m1.demeter.run"
          cardano_preprod = "preprod-v6.ogmios-m1.demeter.run"
          cardano_mainnet = "mainnet-v6.ogmios-m1.demeter.run"
        }
      }
      tx_submit_api = {
        enabled = false
        address = "submitapi-m1.demeter.run"
      }
      utxorpc = {
        enabled = false
        networks = {
          cardano_preview = ""
          cardano_preprod = ""
          cardano_mainnet = ""
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
resource "cloudflare_load_balancer_pool" "kupo_preview" {
  name = "KupoPreview"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.kupo_preview_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.kupo.networks.cardano_preview != "" ? p.kupo.networks.cardano_preview : "${p.name}.${var.cloudflare_zone_name}"
    } if p.kupo.enabled
  ]
}

resource "cloudflare_load_balancer" "kupo_preview" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preview-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.kupo_preview.id]
  fallback_pool   = cloudflare_load_balancer_pool.kupo_preview.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "kupo_preview_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preview-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.kupo_preview.id]
  fallback_pool   = cloudflare_load_balancer_pool.kupo_preview.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "kupo_preview_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for KupoPreview"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "kupo_preprod" {
  name = "KupoPreprod"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.kupo_preprod_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.kupo.networks.cardano_preprod != "" ? p.kupo.networks.cardano_preprod : "${p.name}.${var.cloudflare_zone_name}"
    } if p.kupo.enabled
  ]
}

resource "cloudflare_load_balancer" "kupo_preprod" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preprod-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.kupo_preprod.id]
  fallback_pool   = cloudflare_load_balancer_pool.kupo_preprod.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "kupo_preprod_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preprod-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.kupo_preprod.id]
  fallback_pool   = cloudflare_load_balancer_pool.kupo_preprod.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "kupo_preprod_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for KupoPreprod"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "kupo_mainnet" {
  name = "KupoMainnet"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.kupo_mainnet_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.kupo.networks.cardano_mainnet != "" ? p.kupo.networks.cardano_mainnet : "${p.name}.${var.cloudflare_zone_name}"
    } if p.kupo.enabled
  ]
}

resource "cloudflare_load_balancer" "kupo_mainnet" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-mainnet-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.kupo_mainnet.id]
  fallback_pool   = cloudflare_load_balancer_pool.kupo_mainnet.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "kupo_mainnet_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-mainnet-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.kupo_mainnet.id]
  fallback_pool   = cloudflare_load_balancer_pool.kupo_mainnet.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "kupo_mainnet_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for KupoMainnet"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

# Ogmios
resource "cloudflare_load_balancer_pool" "ogmios_preview" {
  name       = "OgmiosPreview"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.ogmios_preview_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.ogmios.networks.cardano_preview
    } if p.ogmios.enabled
  ]
}

resource "cloudflare_load_balancer" "ogmios_preview" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preview-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.ogmios_preview.id]
  fallback_pool   = cloudflare_load_balancer_pool.ogmios_preview.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "ogmios_preview_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preview-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.ogmios_preview.id]
  fallback_pool   = cloudflare_load_balancer_pool.ogmios_preview.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "ogmios_preview_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for OgmiosPreview"
  path           = "/healthz"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true

  header = {
    "Host" = ["health.preview-v6.ogmios-m1.dmtr.host"]
  }
}

resource "cloudflare_load_balancer_pool" "ogmios_preprod" {
  name       = "OgmiosPreprod"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.ogmios_preprod_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.ogmios.networks.cardano_preprod
    } if p.ogmios.enabled
  ]
}

resource "cloudflare_load_balancer" "ogmios_preprod" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preprod-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.ogmios_preprod.id]
  fallback_pool   = cloudflare_load_balancer_pool.ogmios_preprod.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "ogmios_preprod_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preprod-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.ogmios_preprod.id]
  fallback_pool   = cloudflare_load_balancer_pool.ogmios_preprod.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "ogmios_preprod_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for OgmiosPreprod"
  path           = "/healthz"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true

  header = {
    "Host" = ["health.preprod-v6.ogmios-m1.dmtr.host"]
  }
}

resource "cloudflare_load_balancer_pool" "ogmios_mainnet" {
  name       = "OgmiosMainnet"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.ogmios_mainnet_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.ogmios.networks.cardano_mainnet
    } if p.ogmios.enabled
  ]
}

resource "cloudflare_load_balancer" "ogmios_mainnet" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-mainnet-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.ogmios_mainnet.id]
  fallback_pool   = cloudflare_load_balancer_pool.ogmios_mainnet.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "ogmios_mainnet_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-mainnet-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.ogmios_mainnet.id]
  fallback_pool   = cloudflare_load_balancer_pool.ogmios_mainnet.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "ogmios_mainnet_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for OgmiosMainnet"
  path           = "/healthz"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true

  header = {
    "Host" = ["health.mainnet-v6.ogmios-m1.dmtr.host"]
  }
}

# Tx-Submit-API
resource "cloudflare_load_balancer_pool" "tx_submit_api_m1" {
  name = "TxSubmitApiM1"

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
  zone_id         = var.cloudflare_zone_id
  name            = "*.submitapi-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.tx_submit_api_m1.id]
  fallback_pool   = cloudflare_load_balancer_pool.tx_submit_api_m1.id
  proxied         = true
  steering_policy = "off"
}

# Blockfrost
resource "cloudflare_load_balancer_pool" "blockfrost_preview" {
  name = "BlockfrostPreview"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.blockfrost_preview_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.blockfrost.networks.cardano_preview != "" ? p.blockfrost.networks.cardano_preview : "${p.name}.${var.cloudflare_zone_name}"
    } if p.blockfrost.enabled
  ]
}

resource "cloudflare_load_balancer" "blockfrost_preview" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preview.blockfrost-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.blockfrost_preview.id]
  fallback_pool   = cloudflare_load_balancer_pool.blockfrost_preview.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "blockfrost_preview_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preview.blockfrost-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.blockfrost_preview.id]
  fallback_pool   = cloudflare_load_balancer_pool.blockfrost_preview.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "blockfrost_preview_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for BlockfrostPreview"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "blockfrost_preprod" {
  name = "BlockfrostPreprod"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.blockfrost_preprod_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.blockfrost.networks.cardano_preprod != "" ? p.blockfrost.networks.cardano_preprod : "${p.name}.${var.cloudflare_zone_name}"
    } if p.blockfrost.enabled
  ]
}

resource "cloudflare_load_balancer" "blockfrost_preprod" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preprod.blockfrost-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.blockfrost_preprod.id]
  fallback_pool   = cloudflare_load_balancer_pool.blockfrost_preprod.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "blockfrost_preprod_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preprod.blockfrost-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.blockfrost_preprod.id]
  fallback_pool   = cloudflare_load_balancer_pool.blockfrost_preprod.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "blockfrost_preprod_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for BlockfrostPreprod"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "blockfrost_mainnet" {
  name = "BlockfrostMainnet"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.blockfrost_mainnet_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.blockfrost.networks.cardano_mainnet != "" ? p.blockfrost.networks.cardano_mainnet : "${p.name}.${var.cloudflare_zone_name}"
    } if p.blockfrost.enabled
  ]
}

resource "cloudflare_load_balancer" "blockfrost_mainnet" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-mainnet.blockfrost-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.blockfrost_mainnet.id]
  fallback_pool   = cloudflare_load_balancer_pool.blockfrost_mainnet.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "blockfrost_mainnet_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-mainnet.blockfrost-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.blockfrost_mainnet.id]
  fallback_pool   = cloudflare_load_balancer_pool.blockfrost_mainnet.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "blockfrost_mainnet_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for BlockfrostMainnet"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

# UTxORPC
resource "cloudflare_load_balancer_pool" "utxorpc_preview" {
  name = "UtxorpcPreview"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.utxorpc_preview_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.utxorpc.networks.cardano_preview != "" ? p.utxorpc.networks.cardano_preview : "${p.name}.${var.cloudflare_zone_name}"
    } if p.utxorpc.enabled
  ]
}

resource "cloudflare_load_balancer" "utxorpc_preview" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preview-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_preview.id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_preview.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "utxorpc_preview_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preview-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_preview.id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_preview.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "utxorpc_preview_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for UtxorpcPreview"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "utxorpc_preprod" {
  name = "UtxorpcPreprod"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.utxorpc_preprod_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.utxorpc.networks.cardano_preprod != "" ? p.utxorpc.networks.cardano_preprod : "${p.name}.${var.cloudflare_zone_name}"
    } if p.utxorpc.enabled
  ]
}

resource "cloudflare_load_balancer" "utxorpc_preprod" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-preprod-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_preprod.id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_preprod.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "utxorpc_preprod_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-preprod-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_preprod.id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_preprod.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "utxorpc_preprod_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for UtxorpcPreprod"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}

resource "cloudflare_load_balancer_pool" "utxorpc_mainnet" {
  name = "UtxorpcMainnet"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.utxorpc_mainnet_monitor.id

  origins = [
    for p in local.demeter_providers : {
      name    = p.name
      address = p.utxorpc.networks.cardano_mainnet != "" ? p.utxorpc.networks.cardano_mainnet : "${p.name}.${var.cloudflare_zone_name}"
    } if p.utxorpc.enabled
  ]
}

resource "cloudflare_load_balancer" "utxorpc_mainnet" {
  zone_id         = var.cloudflare_zone_id
  name            = "cardano-mainnet-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_mainnet.id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_mainnet.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer" "utxorpc_mainnet_splat" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.cardano-mainnet-v1.utxorpc-m1.${var.cloudflare_zone_name}"
  default_pools   = [cloudflare_load_balancer_pool.utxorpc_mainnet.id]
  fallback_pool   = cloudflare_load_balancer_pool.utxorpc_mainnet.id
  proxied         = true
  steering_policy = "off"
}

resource "cloudflare_load_balancer_monitor" "utxorpc_mainnet_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for UtxorpcMainnet"
  path           = "/dmtr_health"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true
}
