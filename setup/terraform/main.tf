####################
# VPC Configuration
####################

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "udacity"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1${var.public_az}"
  map_public_ip_on_launch = true

  tags = {
    Name = "udacity-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "us-east-1${var.private_az}"
  cidr_block        = "10.0.2.0/24"

  tags = {
    Name = "udacity-private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}


############################
# VPC Endpoints
############################

resource "aws_vpc_endpoint" "eks" {
  count = var.enable_private ? 1 : 0

  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.us-east-1.eks"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  subnet_ids         = [aws_subnet.private_subnet.id]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2" {
  count = var.enable_private ? 1 : 0

  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.us-east-1.ec2"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  subnet_ids         = [aws_subnet.private_subnet.id]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr_endpoint" {
  count = var.enable_private ? 1 : 0

  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.us-east-1.ecr.dkr"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  subnet_ids         = [aws_subnet.private_subnet.id]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_api_endpoint" {
  count = var.enable_private ? 1 : 0

  vpc_id             = aws_vpc.vpc.id
  service_name       = "com.amazonaws.us-east-1.ecr.api"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  subnet_ids         = [aws_subnet.private_subnet.id]

  private_dns_enabled = true
}


###################
# ECR Repositories
###################

resource "aws_ecr_repository" "frontend" {
  name                 = "frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}


################
# EKS Cluster
################

resource "aws_eks_cluster" "main" {
  name     = "cluster"
  version  = var.k8s_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private_subnet.id,
      aws_subnet.public_subnet.id
    ]

    endpoint_public_access  = var.enable_private ? false : true
    endpoint_private_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy_attachment.eks_service
  ]
}


########################
# EKS Cluster IAM Role
########################

resource "aws_iam_role" "eks_cluster" {
  name = "eks_cluster_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_service" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}


##################
# EKS Node Group
##################

resource "aws_eks_node_group" "main" {
  node_group_name = "udacity"
  cluster_name    = aws_eks_cluster.main.name
  version         = aws_eks_cluster.main.version
  node_role_arn   = aws_iam_role.node_group.arn

  subnet_ids = [
    var.enable_private ? aws_subnet.private_subnet.id : aws_subnet.public_subnet.id
  ]

  # EKS 1.33 uses AL2023
  ami_type = "AL2023_x86_64_STANDARD"

  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_group_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_policy
  ]

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }
}


########################
# Node Group IAM Role
########################

resource "aws_iam_role" "node_group" {
  name               = "udacity-node-group"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "node_group_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = [
        "ec2.amazonaws.com"
      ]
    }
  }
}


######################
# CodeBuild Resources
######################

resource "aws_codebuild_project" "codebuild" {
  name          = "udacity"
  description   = "Udacity CodeBuild project"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 60

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/your-org/your-repo"
    git_clone_depth = 1
    buildspec       = "buildspec.yml"
  }

  cache {
    type = "NO_CACHE"
  }
}


#########################
# CodeBuild IAM Role
#########################

resource "aws_iam_role" "codebuild" {
  name = "codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "codebuild.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
  role       = aws_iam_role.codebuild.name
}


####################
# GitHub Action User
####################

resource "aws_iam_user" "github_action_user" {
  name = "github-action-user"
}

# Disabled because the AWS account does not allow
# iam:PutUserPolicy for this user.

# resource "aws_iam_user_policy" "github_action_user_permission" {
#   user   = aws_iam_user.github_action_user.name
#   policy = data.aws_iam_policy_document.github_policy.json
# }

# data "aws_iam_policy_document" "github_policy" {
#   statement {
#     effect    = "Allow"
#     actions   = ["ecr:*", "eks:*", "ec2:*"]
#     resources = ["*"]
#   }
# }