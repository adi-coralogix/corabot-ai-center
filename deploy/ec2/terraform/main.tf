terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ── Variables ──────────────────────────────────────────────────────────────

variable "region" {
  description = "AWS region for EC2 and Secrets Manager"
  type        = string
  default     = "us-west-2"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "ssh_cidr" {
  description = "CIDR block allowed to reach port 22 (restrict to your IP for security)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

# ── App secrets ─────────────────────────────────────────────────────────────

variable "openai_api_key" {
  description = "OpenAI API key"
  type        = string
  sensitive   = true
}

variable "coralogix_private_key" {
  description = "Coralogix Send-Your-Data key (passed to the OTLP collector)"
  type        = string
  sensitive   = true
}

variable "coralogix_guardrails_key" {
  description = "Coralogix Guardrails API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cx_guardrails_endpoint" {
  description = "Coralogix Guardrails endpoint URL"
  type        = string
  default     = "https://api.us2.coralogix.com/api/v1/guardrails/guard"
}

variable "guardrails_enabled" {
  description = "Enable Coralogix Guardrails (enable / disable)"
  type        = string
  default     = "enable"
}

variable "vite_coralogix_rum_key" {
  description = "Coralogix RUM public key (baked into the JS bundle at build time)"
  type        = string
  sensitive   = true
}

variable "public_coralogix_domain" {
  description = "Coralogix ingestion domain (EU1, US2, …)"
  type        = string
  default     = "US2"
}

# ── Google OAuth2 ───────────────────────────────────────────────────────────

variable "google_client_id" {
  description = "Google OAuth2 client ID (from Google Cloud Console)"
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth2 client secret"
  type        = string
  sensitive   = true
}

# ── Random oauth2-proxy cookie secret ───────────────────────────────────────

resource "random_password" "oauth2_cookie_secret" {
  length  = 32
  special = false
}

# ── IAM: EC2 role that can read the secret ──────────────────────────────────

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "corabot" {
  name               = "corabot-ai-center-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "read_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app.arn]
  }
}

resource "aws_iam_role_policy" "read_secret" {
  name   = "corabot-read-secret"
  role   = aws_iam_role.corabot.id
  policy = data.aws_iam_policy_document.read_secret.json
}

resource "aws_iam_instance_profile" "corabot" {
  name = "corabot-ai-center"
  role = aws_iam_role.corabot.name
}

# ── Security Group ───────────────────────────────────────────────────────────
# EC2 only needs port 80 for CloudFront → origin traffic.
# Port 443 is terminated at CloudFront; browsers never hit EC2 directly.

resource "aws_security_group" "corabot" {
  name        = "corabot-ai-center"
  description = "CoraBot AI Center - HTTP from CloudFront, SSH"

  ingress {
    description = "HTTP - CloudFront origin requests"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "corabot-ai-center"
    Project = "corabot-ai-center"
  }
}

# ── AMI — latest Amazon Linux 2023 (x86_64) ─────────────────────────────────

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "corabot" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.corabot.name
  vpc_security_group_ids = [aws_security_group.corabot.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # Render startup.sh with the secret ARN and region injected
  user_data = templatefile("${path.module}/../startup.sh", {
    secret_arn = aws_secretsmanager_secret.app.arn
    region     = var.region
  })

  # Re-provision if user_data changes (e.g. after a secret rotation requires a stack restart)
  user_data_replace_on_change = true

  tags = {
    Name    = "corabot-ai-center"
    Project = "corabot-ai-center"
  }
}

# ── Elastic IP ───────────────────────────────────────────────────────────────

resource "aws_eip" "corabot" {
  instance = aws_instance.corabot.id
  domain   = "vpc"

  tags = {
    Name    = "corabot-ai-center"
    Project = "corabot-ai-center"
  }
}

# ── CloudFront distribution ──────────────────────────────────────────────────
# CloudFront provides the public HTTPS URL (*.cloudfront.net) — no custom domain needed.
# TLS is terminated here; traffic to EC2 travels over plain HTTP on port 80.
# All headers and cookies are forwarded so oauth2-proxy auth works end-to-end.

resource "aws_cloudfront_distribution" "corabot" {
  origin {
    domain_name = aws_eip.corabot.public_dns
    origin_id   = "corabot-ec2"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Tell oauth2-proxy the request arrived over HTTPS even though CloudFront
    # forwards it to EC2 over HTTP.
    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  comment         = "CoraBot AI Center"

  default_cache_behavior {
    # Chat is fully dynamic — allow all methods, forward everything, no caching.
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "corabot-ec2"

    forwarded_values {
      query_string = true
      headers      = ["*"] # forward all headers (Host, Authorization, X-Forwarded-*, …)
      cookies {
        forward = "all" # forward auth cookies to oauth2-proxy
      }
    }

    viewer_protocol_policy = "redirect-to-https"

    # No caching — every request goes to the origin
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Use the free *.cloudfront.net certificate — no ACM or custom domain needed
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name    = "corabot-ai-center"
    Project = "corabot-ai-center"
  }
}

# ── Secrets Manager ──────────────────────────────────────────────────────────
# DOMAIN is set to the CloudFront domain automatically — no manual input needed.
# After apply, add https://<cloudfront_url>/oauth2/callback to your Google OAuth2
# app's Authorized Redirect URIs, then the stack is fully operational.

resource "aws_secretsmanager_secret" "app" {
  name                    = "corabot-ai-center/env"
  description             = "All runtime environment variables for corabot-ai-center"
  recovery_window_in_days = 0 # allow immediate deletion when tearing down
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    # OTLP (internal compose network)
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector:4317"
    OTEL_EXPORTER_OTLP_INSECURE = "true"

    # Coralogix
    CORALOGIX_PRIVATE_KEY    = var.coralogix_private_key
    GUARDRAILS_ENABLED       = var.guardrails_enabled
    CORALOGIX_GUARDRAILS_KEY = var.coralogix_guardrails_key
    CX_GUARDRAILS_ENDPOINT   = var.cx_guardrails_endpoint

    # RUM
    VITE_CORALOGIX_RUM_KEY  = var.vite_coralogix_rum_key
    PUBLIC_CORALOGIX_DOMAIN = var.public_coralogix_domain

    # OpenAI
    OPENAI_API_KEY = var.openai_api_key

    # Domain — auto-set from CloudFront, used in oauth2-proxy redirect URL
    DOMAIN = aws_cloudfront_distribution.corabot.domain_name

    # Google OAuth2 / oauth2-proxy
    OAUTH2_PROXY_CLIENT_ID     = var.google_client_id
    OAUTH2_PROXY_CLIENT_SECRET = var.google_client_secret
    OAUTH2_PROXY_COOKIE_SECRET = random_password.oauth2_cookie_secret.result
  })

  # Re-write the secret whenever the CloudFront domain or any credential changes
  depends_on = [aws_cloudfront_distribution.corabot]
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "app_url" {
  description = "Public HTTPS URL — add /oauth2/callback to your Google OAuth2 Authorized Redirect URIs"
  value       = "https://${aws_cloudfront_distribution.corabot.domain_name}"
}

output "google_redirect_uri" {
  description = "Register this exact URI in Google Cloud Console → OAuth2 Credentials → Authorized redirect URIs"
  value       = "https://${aws_cloudfront_distribution.corabot.domain_name}/oauth2/callback"
}

output "elastic_ip" {
  description = "EC2 Elastic IP (CloudFront origin — not accessed directly by users)"
  value       = aws_eip.corabot.public_ip
}

output "ssh_command" {
  description = "SSH into the instance"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_eip.corabot.public_ip}"
}

output "secret_arn" {
  description = "Secrets Manager ARN — rotate keys here without reprovisioning EC2"
  value       = aws_secretsmanager_secret.app.arn
}

output "startup_log" {
  description = "Watch first-boot setup progress"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_eip.corabot.public_ip} 'sudo tail -f /var/log/corabot-startup.log'"
}
