locals {
  env_vars = yamldecode(file("config.yaml"))
}
