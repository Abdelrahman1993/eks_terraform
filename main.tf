provider "aws"  {
  region  = "us-east-1" 
  profile = "default" 

}

resource "aws_vpc"  "vpc"  {
cidr_block              = "10.0.0.0/16" 
  enable_dns_support    = true
  enable_dns_hostnames  = true

  tags = {
    Name = "vpc-terraform" 
 }
}

resource "aws_internet_gateway"  "internet_gw"  {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "internet_gatway-terraform" 
  }
}

resource "aws_subnet"  "public_subnet_1"  {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24" 
  availability_zone       = "us-east-1a" 
  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet_1-terrform" 
    "kubernetes.io/cluster/eks"  = "shared" 
    "kubernetes.io/role/elb"     = 1
  }
}

resource "aws_subnet"  "public_subnet_2"  {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24" 
  availability_zone       = "us-east-1b" 
  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet_2-terraform" 
    "kubernetes.io/cluster/eks"  = "shared" 
    "kubernetes.io/role/elb"     = 1
  }
}

resource "aws_subnet"  "private_subnet_1"  {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.3.0/24" 
  availability_zone = "us-east-1a" 

  tags = {
    Name                              = "private_subnet_1-terraform" 
    "kubernetes.io/cluster/eks"       = "shared" 
    "kubernetes.io/role/internal-elb" = 1
  }
}

resource "aws_subnet"  "private_subnet_2"  {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.4.0/24" 
  availability_zone = "us-east-1b" 

  tags = {
    Name                              = "private_subnet_2-terraform" 
    "kubernetes.io/cluster/eks"       = "shared" 
    "kubernetes.io/role/internal-elb" = 1
  }
}


resource "aws_eip"  "nat_eip_1"  {
  depends_on = [aws_internet_gateway.internet_gw]
}


resource "aws_eip"  "nat_eip_2"  {
  depends_on = [aws_internet_gateway.internet_gw]
}


resource "aws_nat_gateway"  "nat_gw_1"  {
  allocation_id = aws_eip.nat_eip_1.id
  subnet_id     = aws_subnet.public_subnet_1.id
  
  tags = {
    Name = "us-east-1a_nat_gatway-terraform" 
  }
}

resource "aws_nat_gateway"  "nat_gw_2"  {
  allocation_id = aws_eip.nat_eip_2.id
  subnet_id     = aws_subnet.public_subnet_2.id

  tags = {
    Name = "us-east-1b_nat_gatway-terraform" 
  }
}

#routing table for public subnets
resource "aws_route_table"  "public_route_table"  {
  vpc_id       = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0" 
    gateway_id = aws_internet_gateway.internet_gw.id
  }

  tags = {
    Name = "public_RT-terrafrom" 
  }
}

#routing table for private subnets in us-east-1a AZ
resource "aws_route_table"  "private_route_table_1"  {
  vpc_id            = aws_vpc.vpc.id

  route {
    cidr_block      = "0.0.0.0/0" 
    nat_gateway_id  = aws_nat_gateway.nat_gw_1.id
  }

  tags = {
    Name = "private1_RT-terraform" 
  }
}

#routing table for private subnets in us-east-1b AZ
resource "aws_route_table"  "private_route_table_2"  {
  vpc_id            = aws_vpc.vpc.id

  route {
    cidr_block      = "0.0.0.0/0" 
    nat_gateway_id  = aws_nat_gateway.nat_gw_2.id
  }

  tags = {
    Name = "private2_RT-terraform" 
  }
}

#public subnet routing table association
resource "aws_route_table_association"  "public_subnet_1_assoc"  {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association"  "public_subnet_2_assoc"  {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

#private subnet routing table association
resource "aws_route_table_association"  "private_subnet_1_assoc"  {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table_1.id
}

resource "aws_route_table_association"  "private_subnet_2_assoc"  {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table_2.id
}


resource "aws_iam_role"  "eks_cluster_role"  {
  name               = "eks-cluster-role" 
  assume_role_policy = <<POLICY
{
  "Version"   : "2012-10-17" ,
  "Statement" : [
    {
      "Effect"    : "Allow" ,
      "Principal" : {
        "Service" : "eks.amazonaws.com" 
      },
      "Action"    : "sts:AssumeRole" 
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment"  "amazon_eks_cluster_policy"  {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" 
  role = aws_iam_role.eks_cluster_role.name
}


resource "aws_eks_cluster"  "eks"  {
 
  name     = "eks" 
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.20" 

  vpc_config {
    endpoint_private_access = false
    endpoint_public_access = true

    subnet_ids = [
      aws_subnet.public_subnet_1.id,
      aws_subnet.public_subnet_2.id,
      aws_subnet.private_subnet_1.id,
      aws_subnet.private_subnet_2.id
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_cluster_policy 
  ]
}


resource "aws_iam_role" "nodes_group_role" {

  name               = "eks-node-group-general"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect"   : "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }, 
      "Action"   : "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy_general" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes_group_role.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy_general" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes_group_role.name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes_group_role.name
}

resource "aws_eks_node_group" "eks_node_group-terraform" {
 
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "eks_node_group-terraform"
  node_role_arn   = aws_iam_role.nodes_group_role.arn

  subnet_ids = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id
  ]

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 2
  }

  ami_type       = "AL2_x86_64"
  capacity_type  = "ON_DEMAND"
  disk_size      = 40
  instance_types = ["t2.micro"]

  labels = {
    role = "nodes-general"
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy_general,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy_general,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only
  ]
}




