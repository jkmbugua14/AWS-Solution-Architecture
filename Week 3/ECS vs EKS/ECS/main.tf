# ==========================================
# PROVIDER
# ==========================================

provider "aws" {
  region  = "ap-south-1"
  profile = "john"

  default_tags {
    tags = {
      Project         = "ECR-Microservices"
      Environment     = "Development"
      Owner           = "john"
      ManagedBy       = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ==========================================
# ARTIFACT STORAGE
# ==========================================

resource "aws_ecr_repository" "backend" {
  name                 = "backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ==========================================
# NETWORKING
# ==========================================

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "ecs-microservices-vpc"
  cidr   = "10.0.0.0/16" # The total IP address range for our network

  azs              = ["ap-south-1a", "ap-south-1b"]
  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets  = ["10.0.10.0/24", "10.0.11.0/24"]
  database_subnets = ["10.0.20.0/24", "10.0.21.0/24"]

  create_database_subnet_group = true
  enable_nat_gateway           = true  
  enable_dns_hostnames         = true
  single_nat_gateway           = false 
}

# ==========================================
# 2. DATA LAYER
# ==========================================

resource "random_password" "db_master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "ecs/development/db-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password_val" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_master_password.result
}

resource "aws_db_instance" "postgres" {
  identifier             = "eks-db"
  engine                 = "postgres"
  engine_version         = "15.15"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_name                = "appdb"
  username               = "master_admin"
  password               = aws_secretsmanager_secret_version.db_password_val.secret_string
  multi_az               = true
  skip_final_snapshot    = true
}

# ==========================================
# SECURITY & IDENTITY
# ==========================================

resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group_rule" "alb_to_internet" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_sg.id
}

# Frontend Security: ONLY allows the ALB to talk to our containers
resource "aws_security_group" "frontend_sg" {
  name   = "frontend-sg"
  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group_rule" "alb_egress_to_frontend" {
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend_sg.id
  security_group_id        = aws_security_group.alb_sg.id
}

resource "aws_security_group_rule" "frontend_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.frontend_sg.id
}

resource "aws_security_group_rule" "frontend_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.frontend_sg.id
}

resource "aws_security_group_rule" "alb_https_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group" "backend_sg" {
  name   = "backend-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name   = "database-sg"
  vpc_id = module.vpc.vpc_id
}

# 2. The Decoupled Permission
resource "aws_security_group_rule" "db_ingress_from_backend" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend_sg.id
  security_group_id        = aws_security_group.db_sg.id
}

# ==========================================
# LOAD BALANCER
# ==========================================

resource "aws_lb" "main" {
  name               = "microservices-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "frontend" {
  name        = "frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check { # Regularly checks if the app is "alive"
    path                = "/"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ==========================================
# 5.ECS (FARGATE)
# ==========================================

resource "aws_iam_role" "ecs_exec_role" {
  name = "ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "ecs_exec_secrets" {
  name = "ecs-secrets-policy"
  role = aws_iam_role.ecs_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [aws_secretsmanager_secret.db_password.arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  for_each          = toset(["frontend", "backend"])
  name              = "/ecs/${each.key}"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = "ecr-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_service_discovery_service" "backend" {
  name = "backend"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id
    
    dns_records {
      ttl  = 60
      type = "A" # This is the "A record" you were missing
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {

  }
}

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = .local"
  vpc         = module.vpc.vpc_id
  description = "Physical DNS for Microservices"
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"] 
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture       = "X86_64"
  }

  container_definitions = jsonencode([{
    name  = "frontend"
    image = "${aws_ecr_repository.frontend.repository_url}:latest"
    portMappings = [{ containerPort = 80 }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs["frontend"].name
        "awslogs-region"        = "ap-south-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "frontend" {
  name            = "frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.frontend_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 80
  }

  depends_on = [module.vpc, aws_lb_listener.https, aws_lb_listener.http_redirect]
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture       = "X86_64"
  }

  container_definitions = jsonencode([{
    name    = "backend"
    image = "${aws_ecr_repository.backend.repository_url}:latest"
    secrets = [{ name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }]
    environment = [
      { name = "DB_HOST", value = aws_db_instance.postgres.address },
      { name = "DB_NAME", value = aws_db_instance.postgres.db_name },
      { name = "DB_USER", value = aws_db_instance.postgres.username },
      { name = "PGSSLMODE", value = "require" }
    ]
    portMappings = [{ name = "backend-port", containerPort = 8080, appProtocol = "http" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs["backend"].name
        "awslogs-region"        = "ap-south-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "backend" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.backend_sg.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.internal.arn
    service {
      port_name      = "backend-port"
      discovery_name = "backend-connect"
      client_alias {
        port     = 8080
        dns_name = "backend.ecr-cluster.local"
      }
    }
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ==========================================
# 7.  EDGE
# ==========================================

data "aws_route53_zone" "main" {
  name         = "astralbyte.agency"
  private_zone = false
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "astralbyte.agency"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "astralbyte.agency"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ==========================================
# 7.  Monitoring
# ==========================================

resource "aws_cloudwatch_dashboard" "main_dashboard" {
  dashboard_name = "Service-Health"

  dashboard_body = jsonencode({
    widgets = [
      # --- ROW 1: THROUGHPUT & LATENCY ---
      {
        type   = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix, { "id": "m1", "stat": "Sum", "visible": false }],
            [{ "expression": "m1 / PERIOD(m1)", "label": "Requests Per Second (RPS)", "id": "e1", "color": "#2ca02c" }]
          ]
          view    = "timeSeries", region = "ap-south-1", title = "📈 Real-time Throughput (RPS)"
        }
      },
      {
        type   = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { "stat": "p99", "label": "p99 Latency (Worst Case)", "color": "#d62728" }],
            ["...", { "stat": "p50", "label": "p50 Latency (Median)", "color": "#1f77b4" }]
          ]
          view    = "timeSeries", region = "ap-south-1", title = "⚡ User Experience (Latency)"
        }
      },

      # --- ROW 2: ERROR ANALYSIS ---
      {
        type   = "metric", x = 0, y = 6, width = 24, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { "label": "5XX Errors", "color": "#d62728" }],
            [".", "HTTPCode_Target_4XX_Count", ".", ".", { "label": "4XX Errors", "color": "#ff7f0e" }],
            [".", "RequestCount", ".", ".", { "stat": "Sum", "label": "Total Traffic", "yAxis": "right", "color": "#cccccc" }]
          ]
          view    = "timeSeries", region = "ap-south-1", title = "🚫 Error Distribution vs. Traffic Volume"
        }
      },

      # --- ROW 3: INFRASTRUCTURE SATURATION ---
      {
        type   = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.backend.name, "ClusterName", aws_ecs_cluster.main.name, { "label": "Backend CPU" }],
            [".", "MemoryUtilization", ".", ".", ".", ".", { "label": "Backend Mem" }],
            [".", "CPUUtilization", "ServiceName", aws_ecs_service.frontend.name, ".", ".", { "label": "Frontend CPU" }]
          ]
          view    = "timeSeries", region = "ap-south-1", title = "🧠 Cluster Resource Saturation"
        }
      },
      {
        type   = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { "label": "DB CPU" }],
            [".", "DatabaseConnections", ".", ".", { "label": "DB Connections", "yAxis": "right" }]
          ]
          view    = "timeSeries", region = "ap-south-1", title = "🗄️ Database Load & Connections"
        }
      },

      # --- ROW 4: LOG INSIGHTS (THE "WHY") ---
      {
        type   = "log", x = 0, y = 18, width = 24, height = 6
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs_logs["backend"].name}' | fields @timestamp, @message | filter @message like /error/ or @message like /Error/ | sort @timestamp desc | limit 50"
          region  = "ap-south-1"
          title   = "📝 Live Root Cause Analysis (Backend Errors)"
          view    = "table"
        }
      }
    ]
  })
}