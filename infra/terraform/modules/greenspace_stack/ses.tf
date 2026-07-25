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

# ---------- Transitional: forget the formerly-managed SES identity ----------
# The `un17hub.com` SES identity is shared across every app on the domain and is
# owned by the un17hub repo; SES identities are keyed by domain + account +
# region, so this stack's identity resource points at that same live identity.
# `destroy = false` forgets it from state WITHOUT issuing `ses:DeleteIdentity`
# (which would break email for every app on the domain). Remove these blocks
# once both environments have applied.
removed {
  from = aws_ses_domain_identity.main
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_ses_domain_dkim.main
  lifecycle {
    destroy = false
  }
}
