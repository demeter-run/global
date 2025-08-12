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
