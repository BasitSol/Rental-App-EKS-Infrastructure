locals {
  name_prefix = "${var.project_name}-${var.environment}"
  labels_csv  = join(",", var.github_runner_labels)
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_cloudwatch_log_group" "runner" {
  name              = "/aws/github-runner/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_security_group" "runner" {
  name        = "${local.name_prefix}-gha-runner"
  description = "GitHub Actions runner access"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  name               = "${local.name_prefix}-gha-runner"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "runner_access" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.github_app_secret_kms_key_arn == "" ? [] : [var.github_app_secret_kms_key_arn]
    content {
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "runner_access" {
  name   = "${local.name_prefix}-gha-runner-access"
  role   = aws_iam_role.runner.name
  policy = data.aws_iam_policy_document.runner_access.json
}

resource "aws_iam_instance_profile" "runner" {
  name = "${local.name_prefix}-gha-runner"
  role = aws_iam_role.runner.name
}

resource "aws_launch_template" "runner" {
  name_prefix   = "${local.name_prefix}-gha-runner-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.runner.name
  }

  vpc_security_group_ids = [aws_security_group.runner.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region            = var.aws_region
    github_owner          = var.github_owner
    github_repo           = var.github_repo
    github_app_secret_arn = var.github_app_secret_arn
    log_group_name         = aws_cloudwatch_log_group.runner.name
    runner_version        = var.runner_version
    runner_labels_csv     = local.labels_csv
    runner_group          = var.github_runner_group
    ephemeral_flag        = var.enable_ephemeral ? "--ephemeral" : ""
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-gha-runner"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "runner" {
  name                      = "${local.name_prefix}-gha-runner"
  max_size                  = var.max_size
  min_size                  = var.min_size
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.subnet_ids
  health_check_type         = "EC2"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-gha-runner"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
