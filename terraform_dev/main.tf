resource "aws_iam_role" "eks_role" {
  name = "eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_eks_cluster" "acman" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_role.arn

  version = var.kubernetes_version

  vpc_config {
    subnet_ids = [
      "subnet-default-a",
      "subnet-default-b"
    ]
  }

  depends_on = [
    aws_iam_role.eks_role
  ]
}