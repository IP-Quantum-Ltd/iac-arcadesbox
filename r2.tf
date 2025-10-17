resource "aws_s3_bucket" "games_bucket" {
  provider = aws.r2
  bucket   = "${var.app_name_prefix}-games-cdn-${var.environment}-${var.infra_suffix}"
}


resource "aws_s3_bucket_cors_configuration" "games_bucket_cors" {
  provider = aws.r2
  bucket   = aws_s3_bucket.games_bucket.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["https://${var.frontend_domain_name}"]
    max_age_seconds = 3000
  }
}
