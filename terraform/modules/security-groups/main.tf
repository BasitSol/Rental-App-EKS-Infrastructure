locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.restrict_alb_to_cloudfront ? [1] : []

    content {
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing[0].id]
    }
  }

  dynamic "ingress" {
    for_each = var.restrict_alb_to_cloudfront ? [] : [1]

    content {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = var.allow_api_public_ingress_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

resource "aws_security_group" "ecs_service" {
  name        = "${local.name_prefix}-api-sg"
  description = "ECS API task security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.api_container_port
    to_port         = var.api_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-api-sg"
  }
}

resource "aws_security_group" "mongo" {
  count       = var.enable_internal_mongo ? 1 : 0
  name        = "${local.name_prefix}-mongo-sg"
  description = "Internal MongoDB access from ECS API tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [var.service_security_group_id_for_mongo != "" ? var.service_security_group_id_for_mongo : aws_security_group.ecs_service.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-mongo-sg"
  }
}

# -------------------------------------------------------------------------
# ELK Security Groups (conditional)
# -------------------------------------------------------------------------
resource "aws_security_group" "elasticsearch" {
  count       = var.elk_enabled ? 1 : 0
  name        = "${local.name_prefix}-elasticsearch-sg"
  description = "Elasticsearch cluster traffic"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-elasticsearch-sg"
  }
}

resource "aws_security_group_rule" "es_ingress_logstash" {
  count                    = var.elk_enabled ? 1 : 0
  type                     = "ingress"
  from_port                = 9200
  to_port                  = 9200
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.logstash[0].id
  security_group_id        = aws_security_group.elasticsearch[0].id
  description              = "Logstash to Elasticsearch"
}

resource "aws_security_group_rule" "es_ingress_kibana" {
  count                    = var.elk_enabled ? 1 : 0
  type                     = "ingress"
  from_port                = 9200
  to_port                  = 9200
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.kibana[0].id
  security_group_id        = aws_security_group.elasticsearch[0].id
  description              = "Kibana to Elasticsearch"
}

resource "aws_security_group_rule" "es_egress" {
  count             = var.elk_enabled ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.elasticsearch[0].id
}

resource "aws_security_group" "logstash" {
  count       = var.elk_enabled ? 1 : 0
  name        = "${local.name_prefix}-logstash-sg"
  description = "Logstash ingestion from ECS tasks"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-logstash-sg"
  }
}

resource "aws_security_group_rule" "logstash_ingress_api" {
  count                    = var.elk_enabled ? 1 : 0
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_service.id
  security_group_id        = aws_security_group.logstash[0].id
  description              = "API tasks (Fluent Bit) to Logstash HTTP"
}

resource "aws_security_group_rule" "logstash_egress" {
  count             = var.elk_enabled ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.logstash[0].id
}

resource "aws_security_group" "kibana" {
  count       = var.elk_enabled ? 1 : 0
  name        = "${local.name_prefix}-kibana-sg"
  description = "Kibana web UI from ALB"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-kibana-sg"
  }
}

resource "aws_security_group_rule" "kibana_ingress_alb" {
  count                    = var.elk_enabled ? 1 : 0
  type                     = "ingress"
  from_port                = 5601
  to_port                  = 5601
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.kibana[0].id
  description              = "ALB to Kibana"
}

resource "aws_security_group_rule" "kibana_egress" {
  count             = var.elk_enabled ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.kibana[0].id
}

resource "aws_security_group" "elk_efs" {
  count       = var.elk_enabled ? 1 : 0
  name        = "${local.name_prefix}-elk-efs-sg"
  description = "EFS mount targets for Elasticsearch data"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-elk-efs-sg"
  }
}

resource "aws_security_group_rule" "efs_ingress_es" {
  count                    = var.elk_enabled ? 1 : 0
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.elasticsearch[0].id
  security_group_id        = aws_security_group.elk_efs[0].id
  description              = "Elasticsearch to EFS"
}

resource "aws_security_group_rule" "efs_egress" {
  count             = var.elk_enabled ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.elk_efs[0].id
}