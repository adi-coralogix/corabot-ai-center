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
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "domain" {
  description = "Public hostname for the app (e.g. corabot.coralogix.com)"
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
  description = "Coralogix RUM public key (baked into the JS bundle)"
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

# ── AWS Secrets Manager ─────────────────────────────────────────────────────
# All runtime env vars are stored as a single JSON secret.
# The EC2 instance reads this at boot using its IAM role — no static credentials needed.

resource "aws_secretsmanager_secret" "app" {
  name                    = "corabot-ai-center/env"
  description             = "All runtime environment variables for corabot-ai-center"
  recovery_window_in_days = 0 # allow immediate deletion when tearing down
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    # OTLP (internal compose network — no change needed)
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

    # App domain (used by oauth2-proxy redirect URL in docker-compose)
    DOMAIN = var.domain

    # Google OAuth2 / oauth2-proxy
    OAUTH2_PROXY_CLIENT_ID     = var.google_client_id
    OAUTH2_PROXY_CLIENT_SECRET = var.google_client_secret
    OAUTH2_PROXY_COOKIE_SECRET = random_password.oauth2_cookie_secret.result
  })
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

resource "aws_security_group" "corabot" {
  name        = "corabot-ai-center"
  description = "CoraBot AI Center — HTTP, HTTPS, SSH"

  ingress {
    description = "HTTP — Caddy redirects to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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

  # Re-provision if user_data changes (e.g. after secret rotation)
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

# ── Outputs ──────────────────────────────────────────────────────────────────

output "elastic_ip" {
  description = "Create a DNS A record pointing ${var.domain} → this IP before Caddy can issue a certificate"
  value       = aws_eip.corabot.public_ip
}

output "ssh_command" {
  description = "SSH into the instance"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_eip.corabot.public_ip}"
}

output "app_url" {
  description = "App URL (live once DNS propagates and Caddy obtains its certificate)"
  value       = "https://${var.domain}"
}

output "secret_arn" {
  description = "Secrets Manager ARN — update values here to rotate keys without reprovisioning"
  value       = aws_secretsmanager_secret.app.arn
}

output "startup_log" {
  description = "SSH in and tail this file to watch the first-boot setup"
  value       = "sudo tail -f /var/log/corabot-startup.log"
}
