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

# --- DNS Records for SES Verification ---



# ses.tf (Append this)

# SES Domain Verification
resource "cloudflare_dns_record" "ses_domain_verification_txt" {
  zone_id = var.cloudflare_zone_id
  name    = "_amazonses.${var.ses_sending_domain}"
  type    = "TXT"
  content = aws_ses_domain_identity.chareli_sending_domain.verification_token
  ttl     = 600
  proxied = false
}

# SES DKIM Records
resource "cloudflare_dns_record" "ses_domain_dkim_cname" {
  count   = 3
  zone_id = var.cloudflare_zone_id
  # We use element() to grab the tokens from the AWS resource
  name    = "${element(aws_ses_domain_dkim.chareli_sending_domain_dkim.dkim_tokens, count.index)}._domainkey.${var.ses_sending_domain}"
  type    = "CNAME"
  content = "${element(aws_ses_domain_dkim.chareli_sending_domain_dkim.dkim_tokens, count.index)}.dkim.amazonses.com"
  ttl     = 600
  proxied = false
}
