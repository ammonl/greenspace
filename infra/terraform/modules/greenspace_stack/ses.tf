# ---------- SES Domain Identity (externally managed) ----------
# The SES domain identity and DKIM signing for `un17hub.com` (which covers the
# `staging.un17hub.com` subdomain used by staging) are owned by the un17hub
# repository, alongside the hosted zone that publishes their DNS records. SES
# verifies a parent domain for all of its subdomains, so this module sends from
# `greenspace@<ses_sender_domain>` against that externally-verified identity
# without provisioning an identity of its own. Send permissions are granted in
# iam.tf; the per-environment configuration set below stays here.

# ---------- SES Configuration Set ----------

resource "aws_ses_configuration_set" "main" {
  name = "${local.naming_prefix}-delivery"
}
