output "cluster_name" {
  value = aws_eks_cluster.acman.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.acman.endpoint
}

output "cluster_arn" {
  value = aws_eks_cluster.acman.arn
}