output "runner_security_group_id" {
  value = aws_security_group.runner.id
}

output "runner_asg_name" {
  value = aws_autoscaling_group.runner.name
}

output "runner_role_arn" {
  value = aws_iam_role.runner.arn
}

output "runner_log_group_name" {
  value = aws_cloudwatch_log_group.runner.name
}
