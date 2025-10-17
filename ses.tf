# Verify the domain for sending emails via SES
resource "aws_ses_domain_identity" "chareli_sending_domain" {
  provider = aws.ses_region_provider # Use the alias if you defined one, otherwise remove
  domain   = var.ses_sending_domain
}

# Enable DKIM for the domain identity.
# This will output CNAME records that need to be added to your DNS.
resource "aws_ses_domain_dkim" "chareli_sending_domain_dkim" {
  provider = aws.ses_region_provider # Use the alias if you defined one, otherwise remove
  domain   = aws_ses_domain_identity.chareli_sending_domain.domain
}

# Verify a specific "From" email address.
# After this is applied, an email will be sent to this address with a verification link.
# You will need to click that link to complete verification for this email address.
resource "aws_ses_email_identity" "chareli_from_email" {
  provider = aws.ses_region_provider # Use the alias if you defined one, otherwise remove
  email    = var.ses_from_email_address
}

# --- DNS Records for SES Verification (using Route 53) ---
# These assume your parent domain (e.g., reallygreattech.com) or the specific
# subdomain (dev.chareli.reallygreattech.com if it's its own zone) is managed in Route 53
# and accessible via data.aws_route53_zone.primary (which points to reallygreattech.com.)
# or a new data source for dev.chareli.reallygreattech.com.

# If dev.chareli.reallygreattech.com is a SUBDOMAIN within the reallygreattech.com ZONE:

data "aws_route53_zone" "parent_hosted_zone_for_ses" { # Using a different name for clarity
  name = "reallygreattech.com."                        # Assuming dev.chareli is within this zone
}

# TXT record for SES domain verification (_amazonses.dev.chareli.reallygreattech.com)
resource "aws_route53_record" "ses_domain_verification_txt" {
  zone_id = data.aws_route53_zone.parent_hosted_zone_for_ses.zone_id
  name    = "_amazonses.${var.ses_sending_domain}" # e.g., _amazonses.dev.chareli.reallygreattech.com
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.chareli_sending_domain.verification_token]
}

# CNAME records for SES DKIM verification
resource "aws_route53_record" "ses_domain_dkim_cname" {
  count   = 3 # SES usually provides 3 DKIM tokens/records
  zone_id = data.aws_route53_zone.parent_hosted_zone_for_ses.zone_id
  name    = "${element(aws_ses_domain_dkim.chareli_sending_domain_dkim.dkim_tokens, count.index)}._domainkey.${var.ses_sending_domain}"
  type    = "CNAME"
  ttl     = "600"
  records = ["${element(aws_ses_domain_dkim.chareli_sending_domain_dkim.dkim_tokens, count.index)}.dkim.amazonses.com"]
}
