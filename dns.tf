# 1. Root Domain (Redirect Source)
# We use the dummy IP so Cloudflare handles the request and redirects to WWW
resource "cloudflare_dns_record" "root" {
  count   = var.environment == "production" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "@" # or "arcadesbox.com"
  type    = "A"
  content = "192.0.2.1" # The dummy IP
  proxied = true
  ttl     = 1

  lifecycle {
    ignore_changes = [
      content,
      ttl
    ]
  }
}

# 2. API Record (ALB)
# In AWS this was an Alias. In Cloudflare, we CNAME to the ALB DNS name.
# We enable the proxy (orange cloud) to get DDoS protection.
resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_domain_name
  type    = "CNAME"
  content = aws_lb.app.dns_name
  proxied = true # Orange Cloud enabled
  ttl     = 1    # Auto
}

# 2. Frontend Record (Cloudflare Pages)
resource "cloudflare_dns_record" "frontend" {
  zone_id = var.cloudflare_zone_id
  name    = var.frontend_domain_name
  type    = "CNAME"
  content = var.cloudflare_pages_cname_target
  proxied = true
  ttl     = 1
}


resource "cloudflare_dns_record" "spf" {
  count   = var.environment == "production" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "TXT"

  content = "\"v=spf1 include:amazonses.com include:_spf.google.com include:sendgrid.net ~all\""

  ttl     = 1
  proxied = false

  lifecycle {
    ignore_changes = [
      content,
      ttl
    ]
  }
}



# SendGrid CNAME 1
resource "cloudflare_dns_record" "sendgrid_cname_1" {
  count   = var.environment == "production" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "57531807" # REPLACE with the "Host" SendGrid gives you (minus .arcadesbox.com)
  type    = "CNAME"
  content = "sendgrid.net" # REPLACE with the "Value" SendGrid gives you
  proxied = false          # Important: SendGrid validation must be DNS Only
  ttl     = 1

  lifecycle {
    ignore_changes = [
      content,
      ttl
    ]
  }
}

# Example SendGrid CNAME 2
resource "cloudflare_dns_record" "sendgrid_cname_2" {
  count   = var.environment == "production" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "s1._domainkey" # REPLACE with the "Host" SendGrid gives you
  type    = "CNAME"
  content = "s1.domainkey.u57531807.wl058.sendgrid.net" # REPLACE with the "Value"
  proxied = false
  ttl     = 1

  lifecycle {
    ignore_changes = [
      content,
      ttl
    ]
  }
}

# Example SendGrid CNAME 3
resource "cloudflare_dns_record" "sendgrid_cname_3" {
  count   = var.environment == "production" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "s2._domainkey" # REPLACE with the "Host" SendGrid gives you
  type    = "CNAME"
  content = "s2.domainkey.u57531807.wl058.sendgrid.net" # REPLACE with the "Value"
  proxied = false
  ttl     = 1

  lifecycle {
    ignore_changes = [
      content,
      ttl
    ]
  }
}

resource "cloudflare_dns_record" "sendgrid_cname_4" {
  count   = var.environment == "production" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "em9551" # REPLACE with the "Host" SendGrid gives you
  type    = "CNAME"
  content = "u57531807.wl058.sendgrid.net" # REPLACE with the "Value"
  proxied = false
  ttl     = 1

  lifecycle {
    ignore_changes = [
      content,
      ttl
    ]
  }
}

resource "cloudflare_dns_record" "sendgrid_cname_5" {
  count   = var.environment == "production" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "url1098" # REPLACE with the "Host" SendGrid gives you
  type    = "CNAME"
  content = "sendgrid.net" # REPLACE with the "Value"
  proxied = false
  ttl     = 1

  lifecycle {
    ignore_changes = [
      content,
      ttl
    ]
  }
}
