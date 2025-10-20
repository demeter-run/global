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
      node = {
        enabled = true
        networks = {
          cardano_preview = "blinklabs-us-cardano-node.blinklabs.io"
          cardano_preprod = "blinklabs-us-cardano-node.blinklabs.io"
          cardano_mainnet = "blinklabs-us-cardano-node.blinklabs.io"
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
    },
    {
      name = "txpipe-m2"
      node = {
        enabled = true
        networks = {
          cardano_preview = "txpipe.cardano-preview.cnode-m1.demeter.run"
          cardano_preprod = "txpipe.cardano-preprod.cnode-m1.demeter.run"
          cardano_mainnet = "txpipe.cardano-mainnet.cnode-m1.demeter.run"
          vector_testnet  = "txpipe.vector-testnet.cnode-m1.demeter.run"
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
          vector_testnet  = "vector-testnet-v6.ogmios-m1.demeter.run"
        }
      }
      tx_submit_api = {
        enabled = false
        address = "submitapi-m1.demeter.run"
      }
    },
  ]
}


# We use for_each on this to expose the domain names in the resource names
resource "cloudflare_zone" "this" {
  for_each   = toset(local.cloudflare_zone_names)
  account_id = var.cloudflare_account_id
  zone       = each.key
  plan       = "pro"
  jump_start = false
}

# Zone settings
# The commented items don't seem to be supported on free plans
resource "cloudflare_zone_settings_override" "this" {
  for_each = toset(local.cloudflare_zone_names)

  zone_id = cloudflare_zone.this[each.key].id

  settings {
    always_use_https         = "on"
    automatic_https_rewrites = "on"
    brotli                   = "on"
    browser_cache_ttl        = 300
    cache_level              = "basic"
    early_hints              = "on"
    h2_prioritization        = "on"
    http2                    = "on"
    http3                    = "on"
    min_tls_version          = "1.2"
    #mirage                   = "on"
    opportunistic_encryption = "on"
    #polish                   = "lossless"
    rocket_loader = "on"
    ssl           = "full"
    tls_1_3       = "on"
    webp          = "on"
    websockets    = "on"
    security_header {
      enabled            = true
      preload            = true
      max_age            = 31536000
      include_subdomains = true
    }
  }
}

resource "cloudflare_certificate_pack" "this" {
  zone_id               = cloudflare_zone.this[var.cloudflare_zone_name].id
  certificate_authority = "google"

  // At most 50.
  hosts = [
    "*.dmtr.host",

    // Cardano node
    "*.cnode-m1.dmtr.host",
    "*.cardano-mainnet.cnode-m1.dmtr.host",
    "*.cardano-preprod.cnode-m1.dmtr.host",
    "*.cardano-preview.cnode-m1.dmtr.host",
    "*.vector-mainnet.cnode-m1.dmtr.host",
    "*.vector-testnet.cnode-m1.dmtr.host",
    "*.prime-testnet.cnode-m1.dmtr.host",

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

# Node
resource "cloudflare_load_balancer_pool" "node_cardano_mainnet" {
  name = "NodeCardanoMainnet"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.node_cardano_mainnet.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.node.enabled && p.node.networks.cardano_mainnet != null }
    content {
      name    = origins.value.name
      address = origins.value.node.networks.cardano_mainnet
    }
  }
}

resource "cloudflare_load_balancer" "node_cardano_mainnet" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-mainnet.cnode-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.node_cardano_mainnet.id]
  fallback_pool_id = cloudflare_load_balancer_pool.node_cardano_mainnet.id
  proxied          = false
  steering_policy  = "off"
}

resource "cloudflare_load_balancer_monitor" "node_cardano_mainnet" {
  account_id     = var.cloudflare_account_id
  type           = "http"
  description    = "Health check for Cardano Mainnet node."
  path           = "/healthcheck"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true

  header {
    header = "Host"
    values = ["cardano-mainnet.cnode-m1.dmtr.host"]
  }
}

resource "cloudflare_load_balancer_pool" "node_cardano_preprod" {
  name = "NodeCardanoPreprod"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.node_cardano_preprod.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.node.enabled && p.node.networks.cardano_preprod != null }
    content {
      name    = origins.value.name
      address = origins.value.node.networks.cardano_preprod
    }
  }
}

resource "cloudflare_load_balancer" "node_cardano_preprod" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-preprod.cnode-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.node_cardano_preprod.id]
  fallback_pool_id = cloudflare_load_balancer_pool.node_cardano_preprod.id
  proxied          = false
  steering_policy  = "off"
}

resource "cloudflare_load_balancer_monitor" "node_cardano_preprod" {
  account_id     = var.cloudflare_account_id
  type           = "http"
  description    = "Health check for Cardano preprod node."
  path           = "/healthcheck"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true

  header {
    header = "Host"
    values = ["cardano-preprod.cnode-m1.dmtr.host"]
  }
}

resource "cloudflare_load_balancer_pool" "node_cardano_preview" {
  name = "NodeCardanoPreview"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.node_cardano_preview.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.node.enabled && p.node.networks.cardano_preview != null }
    content {
      name    = origins.value.name
      address = origins.value.node.networks.cardano_preview
    }
  }
}

resource "cloudflare_load_balancer" "node_cardano_preview" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-preview.cnode-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.node_cardano_preview.id]
  fallback_pool_id = cloudflare_load_balancer_pool.node_cardano_preview.id
  proxied          = false
  steering_policy  = "off"
}

resource "cloudflare_load_balancer_monitor" "node_cardano_preview" {
  account_id     = var.cloudflare_account_id
  type           = "http"
  description    = "Health check for Cardano preview node."
  path           = "/healthcheck"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true

  header {
    header = "Host"
    values = ["cardano-preview.cnode-m1.dmtr.host"]
  }
}

resource "cloudflare_load_balancer_pool" "node_vector_testnet" {
  name = "NodeVectorTestnet"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.node_vector_testnet.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.node.enabled && p.node.networks.vector_testnet != null }
    content {
      name    = origins.value.name
      address = origins.value.node.networks.vector_testnet
    }
  }
}

resource "cloudflare_load_balancer" "node_vector_testnet" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.vector_testnet.cnode-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.node_cardano_preview.id]
  fallback_pool_id = cloudflare_load_balancer_pool.node_cardano_preview.id
  proxied          = false
  steering_policy  = "off"
}

resource "cloudflare_load_balancer_monitor" "node_vector_testnet" {
  account_id     = var.cloudflare_account_id
  type           = "http"
  description    = "Health check for vector testnet node."
  path           = "/healthcheck"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true

  header {
    header = "Host"
    values = ["vector-testnet.cnode-m1.dmtr.host"]
  }
}

# Kupo
resource "cloudflare_load_balancer_pool" "kupo_preview" {
  name = "KupoPreview"

  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.kupo_preview_monitor.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.kupo.enabled }
    content {
      name    = origins.value.name
      address = origins.value.kupo.networks.cardano_preview != "" ? origins.value.kupo.networks.cardano_preview : "${origins.value.name}.${var.cloudflare_zone_name}"
    }
  }
}

resource "cloudflare_load_balancer" "kupo_preview" {
  zone_id          = var.cloudflare_zone_id
  name             = "cardano-preview-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.kupo_preview.id]
  fallback_pool_id = cloudflare_load_balancer_pool.kupo_preview.id
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_load_balancer" "kupo_preview_splat" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-preview-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.kupo_preview.id]
  fallback_pool_id = cloudflare_load_balancer_pool.kupo_preview.id
  proxied          = true
  steering_policy  = "off"
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

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.kupo.enabled }
    content {
      name    = origins.value.name
      address = origins.value.kupo.networks.cardano_preprod != "" ? origins.value.kupo.networks.cardano_preprod : "${origins.value.name}.${var.cloudflare_zone_name}"
    }
  }
}

resource "cloudflare_load_balancer" "kupo_preprod" {
  zone_id          = var.cloudflare_zone_id
  name             = "cardano-preprod-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.kupo_preprod.id]
  fallback_pool_id = cloudflare_load_balancer_pool.kupo_preprod.id
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_load_balancer" "kupo_preprod_splat" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-preprod-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.kupo_preprod.id]
  fallback_pool_id = cloudflare_load_balancer_pool.kupo_preprod.id
  proxied          = true
  steering_policy  = "off"
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

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.kupo.enabled }
    content {
      name    = origins.value.name
      address = origins.value.kupo.networks.cardano_mainnet != "" ? origins.value.kupo.networks.cardano_mainnet : "${origins.value.name}.${var.cloudflare_zone_name}"
    }
  }
}

resource "cloudflare_load_balancer" "kupo_mainnet" {
  zone_id          = var.cloudflare_zone_id
  name             = "cardano-mainnet-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.kupo_mainnet.id]
  fallback_pool_id = cloudflare_load_balancer_pool.kupo_mainnet.id
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_load_balancer" "kupo_mainnet_splat" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-mainnet-v2.kupo-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.kupo_mainnet.id]
  fallback_pool_id = cloudflare_load_balancer_pool.kupo_mainnet.id
  proxied          = true
  steering_policy  = "off"
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

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.ogmios.enabled }
    content {
      name    = origins.value.name
      address = origins.value.ogmios.networks.cardano_preview
    }
  }
}

resource "cloudflare_load_balancer" "ogmios_preview" {
  zone_id          = var.cloudflare_zone_id
  name             = "cardano-preview-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.ogmios_preview.id]
  fallback_pool_id = cloudflare_load_balancer_pool.ogmios_preview.id
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_load_balancer" "ogmios_preview_splat" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-preview-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.ogmios_preview.id]
  fallback_pool_id = cloudflare_load_balancer_pool.ogmios_preview.id
  proxied          = true
  steering_policy  = "off"
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

  header {
    header = "Host"
    values = ["health.preview-v6.ogmios-m1.dmtr.host"]
  }
}

resource "cloudflare_load_balancer_pool" "ogmios_preprod" {
  name       = "OgmiosPreprod"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.ogmios_preprod_monitor.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.ogmios.enabled }
    content {
      name    = origins.value.name
      address = origins.value.ogmios.networks.cardano_preprod
    }
  }
}

resource "cloudflare_load_balancer" "ogmios_preprod" {
  zone_id          = var.cloudflare_zone_id
  name             = "cardano-preprod-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.ogmios_preprod.id]
  fallback_pool_id = cloudflare_load_balancer_pool.ogmios_preprod.id
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_load_balancer" "ogmios_preprod_splat" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-preprod-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.ogmios_preprod.id]
  fallback_pool_id = cloudflare_load_balancer_pool.ogmios_preprod.id
  proxied          = true
  steering_policy  = "off"
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

  header {
    header = "Host"
    values = ["health.preprod-v6.ogmios-m1.dmtr.host"]
  }
}

resource "cloudflare_load_balancer_pool" "ogmios_mainnet" {
  name       = "OgmiosMainnet"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.ogmios_mainnet_monitor.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.ogmios.enabled }
    content {
      name    = origins.value.name
      address = origins.value.ogmios.networks.cardano_mainnet
    }
  }
}

resource "cloudflare_load_balancer" "ogmios_mainnet" {
  zone_id          = var.cloudflare_zone_id
  name             = "cardano-mainnet-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.ogmios_mainnet.id]
  fallback_pool_id = cloudflare_load_balancer_pool.ogmios_mainnet.id
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_load_balancer" "ogmios_mainnet_splat" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.cardano-mainnet-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.ogmios_mainnet.id]
  fallback_pool_id = cloudflare_load_balancer_pool.ogmios_mainnet.id
  proxied          = true
  steering_policy  = "off"
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

  header {
    header = "Host"
    values = ["health.mainnet-v6.ogmios-m1.dmtr.host"]
  }
}

resource "cloudflare_load_balancer_pool" "ogmios_vector_testnet" {
  name       = "OgmiosVectorTestnet"
  account_id = var.cloudflare_account_id
  monitor    = cloudflare_load_balancer_monitor.ogmios_vector_testnet_monitor.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.ogmios.enabled && p.ogmios.networks.vector_testnet != null }
    content {
      name    = origins.value.name
      address = origins.value.ogmios.networks.vector_testnet
    }
  }
}

resource "cloudflare_load_balancer" "ogmios_vector_testnet" {
  zone_id          = var.cloudflare_zone_id
  name             = "vector-testnet-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.ogmios_vector_testnet.id]
  fallback_pool_id = cloudflare_load_balancer_pool.ogmios_vector_testnet.id
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_load_balancer" "ogmios_vector_testnet_splat" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.vector-testnet-v6.ogmios-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.ogmios_vector_testnet.id]
  fallback_pool_id = cloudflare_load_balancer_pool.ogmios_vector_testnet.id
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_load_balancer_monitor" "ogmios_vector_testnet_monitor" {
  account_id     = var.cloudflare_account_id
  type           = "https"
  description    = "Health check for OgmiosVectorTestnet"
  path           = "/healthz"
  interval       = 60
  timeout        = 5
  retries        = 2
  method         = "GET"
  expected_codes = "200"
  allow_insecure = true

  header {
    header = "Host"
    values = ["health.vector-testnet-v6.ogmios-m1.dmtr.host"]
  }
}

# Tx-Submit-API
resource "cloudflare_load_balancer_pool" "tx_submit_api_m1" {
  name = "TxSubmitApiM1"

  account_id = var.cloudflare_account_id
  # TODO: add monitor when tx-submit-api supports reliable health checks
  # monitor    = cloudflare_load_balancer_monitor.tx_submit_api_m1_monitor.id

  dynamic "origins" {
    for_each = { for p in local.demeter_providers : p.name => p if p.tx_submit_api.enabled }
    content {
      name    = origins.value.name
      address = origins.value.tx_submit_api.address != "" ? origins.value.tx_submit_api.address : "${origins.value.name}.${var.cloudflare_zone_name}"
    }
  }
}

resource "cloudflare_load_balancer" "tx_submit_api_m1" {
  zone_id          = var.cloudflare_zone_id
  name             = "*.submitapi-m1.${var.cloudflare_zone_name}"
  default_pool_ids = [cloudflare_load_balancer_pool.tx_submit_api_m1.id]
  fallback_pool_id = cloudflare_load_balancer_pool.tx_submit_api_m1.id
  proxied          = true
  steering_policy  = "off"
}
