# -----------------------------------------------------------------------------
# 1. ElastiCache Subnet Group
#    This tells ElastiCache which subnets it's allowed to place its nodes in.
#    It must be the private subnets.
# -----------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "redis" {
  count = var.enable_redis ? 1 : 0

  name       = "${var.app_name_prefix}-redis-subnet-group-${var.environment}-${var.infra_suffix}"
  subnet_ids = aws_subnet.private[*].id # Uses the private subnets from networking.tf
}

# -----------------------------------------------------------------------------
# 2. ElastiCache Security Group
#    This is a dedicated firewall for the Redis cluster.
# -----------------------------------------------------------------------------
resource "aws_security_group" "redis_sg" {
  count = var.enable_redis ? 1 : 0

  name        = "${var.app_name_prefix}-redis-sg-${var.environment}-${var.infra_suffix}"
  description = "Controls access to the ElastiCache Redis cluster"
  vpc_id      = aws_vpc.main.id

  # CRITICAL INGRESS RULE:
  # Allow traffic on the Redis port (6379) ONLY from the ECS service's security group.
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id] # Reference to the SG from networking.tf
  }

  # Egress can be open as it's in a private subnet.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# 2.5. ElastiCache Parameter Group
#      Custom parameter group to set the eviction policy to 'noeviction'
# -----------------------------------------------------------------------------
resource "aws_elasticache_parameter_group" "redis" {
  count = var.enable_redis ? 1 : 0

  name   = "${var.app_name_prefix}-redis-params-${var.environment}-${var.infra_suffix}"
  family = "redis${element(split(".", var.redis_engine_version), 0)}"

  description = "Custom parameter group with noeviction policy for ${var.app_name_prefix}"

  # Set the eviction policy to noeviction
  # This means Redis will return errors when memory is full instead of evicting keys
  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }

  # Optional: Set a reasonable maxmemory limit
  # This prevents Redis from using all available memory
  # Adjust based on your node type - this example sets 80% of a cache.t3.micro (555MB)
  # For cache.t3.small (1.37GB), you might use 1100mb
  # For cache.t3.medium (3.09GB), you might use 2500mb
  # Comment out if you want Redis to use all available memory
  # parameter {
  #   name  = "maxmemory"
  #   value = "450mb"
  # }

  tags = {
    Name = "${var.app_name_prefix}-redis-params-${var.environment}-${var.infra_suffix}"
  }
}


# -----------------------------------------------------------------------------
# 3. The ElastiCache Replication Group (The Redis Cluster Itself)
#    We use a replication group even for a single node, as it's the modern
#    standard and allows for easy scaling/failover later.
# -----------------------------------------------------------------------------
resource "aws_elasticache_replication_group" "redis" {
  count = var.enable_redis ? 1 : 0

  replication_group_id = "${var.app_name_prefix}-${var.environment}-${var.infra_suffix}"
  description          = "ElastiCache Redis for the arcadesbox application"

  node_type      = var.environment == "development" ? "cache.t4g.micro" : "cache.t4g.small"
  engine         = "redis"
  engine_version = var.redis_engine_version
  port           = 6379


  # For production, you would increase num_cache_clusters.
  num_cache_clusters         = var.environment == "production" ? 2 : 1
  automatic_failover_enabled = var.environment == "production" ? true : false

  subnet_group_name  = aws_elasticache_subnet_group.redis[0].name
  security_group_ids = [aws_security_group.redis_sg[0].id]

  # Use default parameters for now
  # In aws_elasticache_replication_group.redis[0]
  # For Redis 7+, the parameter group family is just '7.x', not '7.0'.
  # We can construct this by splitting the version string.
  # parameter_group_name = "default.redis${element(split(".", var.redis_engine_version), 0)}"
  parameter_group_name = aws_elasticache_parameter_group.redis[0].name

  tags = {
    Name = "${var.app_name_prefix}-redis-${var.environment}-${var.infra_suffix}"
  }
}
