data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

}

# 1. Create the Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name_prefix}-igw-${var.environment}-${var.infra_suffix}"
  }
}



resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${var.app_name_prefix}-public-subnet-${count.index}-${var.infra_suffix}"
  }
}

resource "aws_subnet" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id
  # Use different subnet ranges for private subnets
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${var.app_name_prefix}-private-subnet-${count.index}-${var.infra_suffix}"
  }
}


resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = "${var.app_name_prefix}-${var.environment}-nat-eip"
  }
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.app_name_prefix}-nat-gw-${var.environment}-${var.infra_suffix}" }
}

# 2. Create a public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # 3. Create a Route in the Route Table that points to the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.app_name_prefix}-public-rt-${var.environment}-${var.infra_suffix}"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}



# Route Table for the private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    # Point internet-bound traffic to the NAT Gateway
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.app_name_prefix}-private-rt-${var.environment}-${var.infra_suffix}" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}




# Security Group for the Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "${var.app_name_prefix}-alb-sg-${var.environment}-${var.infra_suffix}"
  description = "Controls access to the ALB from the internet"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP from anywhere (will be redirected to HTTPS by the listener)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP for redirection"
  }

  # Allow HTTPS from anywhere (CloudFront will be the main client)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for the ECS Service/Tasks
resource "aws_security_group" "ecs_service" {
  name        = "${var.app_name_prefix}-ecs-sg-${var.environment}-${var.infra_suffix}"
  description = "Controls access to the ECS tasks"
  vpc_id      = aws_vpc.main.id

  # THIS IS THE CRITICAL RULE:
  # Allow traffic on the application port (5000) ONLY from the ALB's security group.
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # <-- Reference the ALB's SG
    description     = "Allow inbound from ALB"
  }

  # Allow all outbound traffic (for connecting to Secrets Manager, DB, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
