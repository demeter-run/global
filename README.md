# Global configuration

This houses the global, shared configuration such as the `dmtr.host` domain
DNS configuration and the Cloudflare load balancing used for creating
connections to each provider.

If you need support in creating a new provider, reach out to @wolf31o2 or the
`#demeter-fabric` channel in the TxPipe Discord.

## Creating a new provider

To create a new provider, you will need to configure the backend and several
variables for terraform.

- `cloudflare_account_id`: Cloudflare account for dmtr.host
- `cloudflare_zone_id`: zone ID for dmtr.host
- `cloudflare_zone_name`: this is `dmtr.host`

## Routing

Each API has one Cloudflare load balancer pool, built from
`local.demeter_providers` in `cloudflare.tf`. A provider joins an API's pool
when that API's entry has `enabled = true`.

An entry may also set `weight`, a value from 0 to 1 that is its relative share
of the pool's traffic among the healthy origins. Entries without a `weight`
default to 1, so by default every enabled provider takes an equal share.
