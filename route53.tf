data "aws_route53_zone" "primary" {
  name = var.root_domain_name
}

# API Record -> Points to AWS ALB
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.primary.id
  name    = var.api_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

# Frontend Record -> Points to Cloudflare Pages
resource "aws_route53_record" "frontend" {
  zone_id = data.aws_route53_zone.primary.id
  name    = var.frontend_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [var.cloudflare_pages_cname_target] # Correctly references the variable
}

# # Games CDN Record -> Points to R2 Public Domain
# resource "aws_route53_record" "games_cdn" { // Renamed from games_cdn_cname
#   zone_id = data.aws_route53_zone.primary.id
#   name    = var.games_cdn_domain_name
#   type    = "CNAME"
#   ttl     = 300
#   records = [var.r2_public_cname_target]
# }

# Games CDN Record -> CNAME to the Cloudflare Worker's default URL
resource "aws_route53_record" "games_cdn" {
  zone_id = data.aws_route53_zone.primary.id
  name    = var.games_cdn_domain_name # e.g., games.dev.chareli...
  type    = "CNAME"
  ttl     = 300

  # This points to the *.workers.dev URL of the worker we created.
  # Note: The 'id' attribute of cloudflare_worker_script contains the full hostname.
  #records = [cloudflare_workers_script.game_cdn_worker.id]

  #Construct the url for the worker
  records = [var.r2_bucket_is_public ? var.r2_public_cname_target : "${cloudflare_workers_script.game_cdn_worker[0].script_name}.${var.cloudflare_workers_subdomain}"]
}
