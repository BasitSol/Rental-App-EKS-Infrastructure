# -------------------------------------------------------------------------
# EFS: Elasticsearch persistent storage
# -------------------------------------------------------------------------
resource "aws_efs_file_system" "es" {
  creation_token   = "${local.name_prefix}-es-data"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-es-data" })
}

resource "aws_efs_mount_target" "es" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.es.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.efs_sg_id]
}

resource "aws_efs_access_point" "es" {
  file_system_id = aws_efs_file_system.es.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/es-data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = local.common_tags
}

# -------------------------------------------------------------------------
# Service Discovery (CloudMap) for inter-service DNS
# -------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "elk" {
  name        = local.elk_namespace_name
  description = "ELK internal service discovery"
  vpc         = var.vpc_id
  tags        = local.common_tags
}

resource "aws_service_discovery_service" "elasticsearch" {
  name = "elasticsearch"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.elk.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.common_tags
}

resource "aws_service_discovery_service" "logstash" {
  name = "logstash"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.elk.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.common_tags
}

resource "aws_service_discovery_service" "kibana" {
  name = "kibana"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.elk.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.common_tags
}

# -------------------------------------------------------------------------
# IAM Roles for ELK tasks
# -------------------------------------------------------------------------
resource "aws_iam_role" "elk_execution" {
  name = "${local.name_prefix}-elk-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "elk_execution_managed" {
  role       = aws_iam_role.elk_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ssm_parameter" "elasticsearch_password" {
  name      = "/${local.name_prefix}/elk/elasticsearch_password"
  type      = "SecureString"
  value     = var.elasticsearch_password
  overwrite = true

  tags = local.common_tags
}

resource "aws_iam_policy" "elk_ssm_read" {
  name = "${local.name_prefix}-elk-ssm-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = aws_ssm_parameter.elasticsearch_password.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "elk_execution_ssm" {
  role       = aws_iam_role.elk_execution.name
  policy_arn = aws_iam_policy.elk_ssm_read.arn
}

resource "aws_iam_role" "elk_task" {
  name = "${local.name_prefix}-elk-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "elk_efs" {
  name = "${local.name_prefix}-elk-efs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.es.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "elk_efs" {
  role       = aws_iam_role.elk_task.name
  policy_arn = aws_iam_policy.elk_efs.arn
}

# -------------------------------------------------------------------------
# CloudWatch Log Groups for ELK components
# -------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "elasticsearch" {
  name              = "/ecs/${local.name_prefix}-elasticsearch"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "logstash" {
  name              = "/ecs/${local.name_prefix}-logstash"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "kibana" {
  name              = "/ecs/${local.name_prefix}-kibana"
  retention_in_days = 14
  tags              = local.common_tags
}

# -------------------------------------------------------------------------
# Elasticsearch Task Definition
# -------------------------------------------------------------------------
resource "aws_ecs_task_definition" "elasticsearch" {
  family                   = "${local.name_prefix}-elasticsearch"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.elasticsearch_cpu
  memory                   = var.elasticsearch_memory
  execution_role_arn       = aws_iam_role.elk_execution.arn
  task_role_arn            = aws_iam_role.elk_task.arn

  volume {
    name = "es-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.es.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.es.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "elasticsearch"
      image     = "docker.elastic.co/elasticsearch/elasticsearch:${var.elk_version}"
      essential = true
      environment = [
        {
          name  = "discovery.type"
          value = "single-node"
        },
        {
          name  = "xpack.security.enabled"
          value = "true"
        },
        {
          name  = "bootstrap.memory_lock"
          value = "true"
        },
        {
          name  = "ES_JAVA_OPTS"
          value = "-Xms${floor(var.elasticsearch_memory * 0.5)}m -Xmx${floor(var.elasticsearch_memory * 0.5)}m"
        },
        {
          name  = "network.host"
          value = "0.0.0.0"
        }
      ]
      secrets = [
        {
          name      = "ELASTIC_PASSWORD"
          valueFrom = aws_ssm_parameter.elasticsearch_password.name
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "es-data"
          containerPath = "/usr/share/elasticsearch/data-717"
          readOnly      = false
        }
      ]
      portMappings = [
        {
          containerPort = 9200
          protocol      = "tcp"
        },
        {
          containerPort = 9300
          protocol      = "tcp"
        }
      ]
      ulimits = [
        {
          name      = "memlock"
          softLimit = -1
          hardLimit = -1
        },
        {
          name      = "nofile"
          softLimit = 65536
          hardLimit = 65536
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.elasticsearch.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "es"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "elasticsearch" {
  name            = "${local.name_prefix}-elasticsearch"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.elasticsearch.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.elasticsearch_sg_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.elasticsearch.arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_efs_mount_target.es]

  tags = local.common_tags
}

# -------------------------------------------------------------------------
# Logstash Task Definition
# -------------------------------------------------------------------------
resource "aws_ecs_task_definition" "logstash" {
  family                   = "${local.name_prefix}-logstash"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.logstash_cpu
  memory                   = var.logstash_memory
  execution_role_arn       = aws_iam_role.elk_execution.arn
  task_role_arn            = aws_iam_role.elk_task.arn

  container_definitions = jsonencode([
    {
      name      = "logstash"
      image     = "docker.elastic.co/logstash/logstash:${var.elk_version}"
      essential = true
      command = [
        "logstash",
        "-e",
        "input { beats { port => 5044 } http { port => 8080 } } filter { json { source => 'message' skip_on_invalid_json => true } } output { elasticsearch { hosts => ['http://elasticsearch.${local.elk_namespace_name}:9200'] user => 'elastic' password => '$${ELASTIC_PASSWORD}' index => 'rentalapp-logs-%%{+YYYY.MM.dd}' } stdout { codec => rubydebug } }"
      ]
      environment = [
        {
          name  = "xpack.monitoring.enabled"
          value = "false"
        }
      ]
      secrets = [
        {
          name      = "ELASTIC_PASSWORD"
          valueFrom = aws_ssm_parameter.elasticsearch_password.name
        }
      ]
      portMappings = [
        {
          containerPort = 5044
          protocol      = "tcp"
        },
        {
          containerPort = 8080
          protocol      = "tcp"
        },
        {
          containerPort = 9600
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.logstash.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "logstash"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "logstash" {
  name            = "${local.name_prefix}-logstash"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.logstash.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.logstash_sg_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.logstash.arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.common_tags
}

# -------------------------------------------------------------------------
# Kibana Task Definition
# -------------------------------------------------------------------------
resource "aws_ecs_task_definition" "kibana" {
  family                   = "${local.name_prefix}-kibana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.kibana_cpu
  memory                   = var.kibana_memory
  execution_role_arn       = aws_iam_role.elk_execution.arn
  task_role_arn            = aws_iam_role.elk_task.arn

  container_definitions = jsonencode([
    {
      name      = "kibana"
      image     = "docker.elastic.co/kibana/kibana:${var.elk_version}"
      essential = true
      environment = [
        {
          name  = "ELASTICSEARCH_HOSTS"
          value = "http://elasticsearch.${local.elk_namespace_name}:9200"
        },
        {
          name  = "ELASTICSEARCH_USERNAME"
          value = "elastic"
        },
        {
          name  = "SERVER_HOST"
          value = "0.0.0.0"
        },
        {
          name  = "SERVER_PORT"
          value = "5601"
        },
        {
          name  = "SERVER_BASEPATH"
          value = "/kibana"
        },
        {
          name  = "SERVER_REWRITEBASEPATH"
          value = "true"
        },
        /*
        {
          name  = "XPACK_SECURITY_ENABLED"
          value = "true"
        }
        */
      ]
      secrets = [
        {
          name      = "ELASTICSEARCH_PASSWORD"
          valueFrom = aws_ssm_parameter.elasticsearch_password.name
        }
      ]
      portMappings = [
        {
          containerPort = 5601
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.kibana.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "kibana"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "kibana" {
  name                              = "${local.name_prefix}-kibana"
  cluster                           = var.ecs_cluster_id
  task_definition                   = aws_ecs_task_definition.kibana.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 600

  load_balancer {
    target_group_arn = var.kibana_target_group_arn
    container_name   = "kibana"
    container_port   = 5601
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.kibana_sg_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kibana.arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.common_tags
}