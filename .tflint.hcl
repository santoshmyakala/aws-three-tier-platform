# Bundled Terraform ruleset only, so linting needs no plugin downloads.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
