output "admins_group_name" {
  value = aws_iam_group.admins.name
}

output "developers_group_name" {
  value = aws_iam_group.developers.name
}

output "auditors_group_name" {
  value = aws_iam_group.auditors.name
}

output "ec2_s3_role_arn" {
  value = aws_iam_role.ec2_s3_role.arn
}

output "ec2_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_s3_profile.name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app_bucket.bucket
}
