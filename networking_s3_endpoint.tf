
# =================================================================
# S3 VPC Gateway Endpoint
# =================================================================

# Create a VPC Endpoint for S3
# This allows instances in private subnets to access S3 directly
# without going through the NAT Gateway, saving data processing costs.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.app_name_prefix}-s3-vpce-${var.environment}-${var.infra_suffix}"
  }
}

# Associate the VPC Endpoint with the Private Route Table
resource "aws_vpc_endpoint_route_table_association" "private_s3" {
  route_table_id  = aws_route_table.private.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}
