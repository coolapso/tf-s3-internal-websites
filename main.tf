terraform {
  required_version = ">=1.0.0"
  required_providers { 
    aws = {
      source = "hashicorp/aws"
      version = "~>5.0"
    }
  }
}

locals {
  name   = "s3-internal-website-demo"
  region = "eu-north-1"
  vpc_id = "vpc-087ce0aaa262168ed"
  private_subnet_ids = [
    "subnet-0a1b2c3d4e5f6g7h8",
    "subnet-9a8b7c6d5e4f3g2h1",
    "subnet-2a3b4c5d6e7f8g9h0",
  ]

  domain_name = "example.com"
  route53_zone_id = "Z03152832Y4KJCOLE8AC2"

  s3_endpoint_ips = [for subnet in aws_vpc_endpoint.this.subnet_configuration : subnet.ipv4]
}

data "aws_vpc" "this" { 
  id = local.vpc_id
}

// The INTERFACE type VPC Endpoint 
resource "aws_vpc_endpoint" "this" {
  vpc_id = local.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Interface"
  security_group_ids = [aws_security_group.this.id]
  subnet_ids          = local.private_subnet_ids

  tags = {
    Name = local.name
  }
}

resource "aws_security_group" "this" {
  name        = local.name
  description = "VPC Ednpoint Security group"
  vpc_id      = local.vpc_id

  tags = {
    Name = local.name
  }
}

resource "aws_security_group_rule" "http" {
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.this.cidr_block]
  description       = "HTTP traffic"
}

resource "aws_security_group_rule" "https" {
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.this.cidr_block]
  description       = "HTTPS traffic"
}

resource "aws_security_group_rule" "egress" {
  security_group_id = aws_security_group.this.id
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  description = "Allow all outbound"
}

// Create the wildcard ACM certificate
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name  = local.domain_name
  zone_id      = local.route53_zone_id
  validation_method = "DNS"
  subject_alternative_names = ["*.${local.domain_name}"]
  wait_for_validation = true

  tags = {
    Name = local.domain_name
  }
}

// Create the load balancer, target group and listener
module "alb" {
  source = "terraform-aws-modules/alb/aws"
  version = "~>9.9.0"
  
  name     = local.name
  vpc_id   = local.vpc_id
  subnets  = local.private_subnet_ids
  internal = true
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }

    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  listeners = {
    http-https-redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = module.acm.acm_certificate_arn

      forward = {
        target_group_key = "internal_s3"
      }

      rules = {
        indexhtml = {
          priority = 10

          conditions = [{
            path_pattern = {
              values = ["*/"]
            }
          }]

          actions = [{
            type        = "redirect"
            status_code = "HTTP_301"
            protocol    = "HTTPS"
            host        = "#{host}"
            path        = "/#{path}index.html"
            query       = "#{query}"
          }]

          tags = {
            Name = "indexhtml"
          }
        }
      }
    }
  }

  target_groups = {
    internal_s3 = {
      protocol          = "HTTPS"
      port              = 443
      target_type       = "ip"
      create_attachment = false

      health_check = {
        enabled             = true
        protocol            = "HTTP"
        port                = 80
        healthy_threshold   = 5
        unhealthy_threshold = 2
        matcher             = "200,307,405"
      }
    }
  }

  additional_target_group_attachments = {
    "vpc_endpoint_a" = {
      target_group_key = "internal_s3"
      target_id        = local.s3_endpoint_ips[0]
      port             = 443
    }

    "vpc_endpoint_b" = {
      target_group_key = "internal_s3"
      target_id        = local.s3_endpoint_ips[1]
      port             = 443
    }

    "vpc_Endpoint_c" = {
      target_group_key = "internal_s3"
      target_id        = local.s3_endpoint_ips[2]
      port             = 443
    }
  }
}
