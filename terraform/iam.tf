resource "aws_iam_role" "wg_ssm_role" {
  name               = "wg-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "wg_ssm_policy" {
  name        = "wg-ssm-parameter-policy"
  description = "Allow WG instances to exchange keys via SSM Parameter Store"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "ssm:PutParameter",
          "ssm:GetParameter"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wg_ssm_attach" {
  role       = aws_iam_role.wg_ssm_role.name
  policy_arn = aws_iam_policy.wg_ssm_policy.arn
}

resource "aws_iam_instance_profile" "wg_ssm_profile" {
  name = "wg-ssm-instance-profile"
  role = aws_iam_role.wg_ssm_role.name
}
