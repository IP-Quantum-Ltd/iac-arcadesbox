# Create the ACM certificate for the API Load Balancer
resource "aws_acm_certificate" "api_cert" {
  #provider          = aws.us-east-1 // Keep in us-east-1, it's good practice
  domain_name       = var.api_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "api_cert_validation" {
  #provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.api_cert.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.api_cert_validation : record.name]
}

#Add an artificial delay to allow the new ACM certificate to replicate
#across AWS regions before being used by the ALB listener.
resource "time_sleep" "wait_for_acm_replication" {
  # This resource will only be created after the certificate validation is complete.
  depends_on = [aws_acm_certificate_validation.api_cert_validation]

  # Wait for 60 seconds.
  create_duration = "60s"
}

resource "cloudflare_dns_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  content = each.value.record
  type    = each.value.type
  ttl     = 300
  proxied = false # Important: Validation records must be DNS Only (Grey Cloud)
}
