# ---------- DNS (externally managed) ----------
# The `un17hub.com` hosted zone — and the `staging.un17hub.com` subdomain
# folded into it — is owned by the un17hub repository, not this module. SES
# domain verification and DKIM records for the sender domain are published in
# that zone by the un17hub repository (see ses.tf). This module therefore
# manages no Route 53 zone or records of its own.
#
# Amplify custom-domain routing still works: when the target hosted zone lives
# in the same AWS account, Amplify auto-provisions its ACM validation and
# routing records into that zone. The domain association resource in amplify.tf
# manages that lifecycle against the externally-owned `un17hub.com` zone.
