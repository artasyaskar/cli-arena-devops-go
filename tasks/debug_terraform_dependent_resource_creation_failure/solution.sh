#!/bin/bash
set -e

INFRA_DIR="./resources/infra"
MAIN_TF_FILE="$INFRA_DIR/main.tf"

echo "INFO: Applying fixes to $MAIN_TF_FILE for dependency and timing issues."

# The user is supposed to modify main.tf directly.
# This solution script will overwrite main.tf with the corrected version.

cat << 'EOF_MAIN_TF_FIXED' > "$MAIN_TF_FILE"
# main.tf - Corrected for dependencies and timing

resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.common_tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "gw" {
  # No vpc_id here; attachment is handled by aws_internet_gateway_attachment
  tags = merge(var.common_tags, { Name = "${var.project_name}-igw" })
  # Explicitly depend on VPC if we want to be absolutely sure IGW creation starts after VPC.
  # Though usually not needed as attachment below will establish this link.
  # depends_on = [aws_vpc.main_vpc] # Generally not needed due to attachment resource.
}

# Attach IGW to VPC. This resource is crucial for establishing the link.
resource "aws_internet_gateway_attachment" "gw_attachment" {
  internet_gateway_id = aws_internet_gateway.gw.id
  vpc_id              = aws_vpc.main_vpc.id
  # This resource inherently depends on both the IGW and the VPC.
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a" # Example AZ
  tags                    = merge(var.common_tags, { Name = "${var.project_name}-public-subnet" })
  # Depends on VPC, which is fine.
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = merge(var.common_tags, { Name = "${var.project_name}-public-rt" })
  # Depends on VPC.
}

resource "aws_route" "public_route_to_igw" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id

  # FIX: Explicitly depend on the Internet Gateway *attachment* to ensure the IGW
  # is not only created but also attached to the VPC before this route is created.
  # This is the most common fix for this type of race condition with IGWs.
  depends_on = [aws_internet_gateway_attachment.gw_attachment]
}

resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
  # Depends on subnet and route table, which is fine.
  # If route creation was problematic, this could also fail if subnet expects outbound traffic.
}

resource "aws_security_group" "allow_http_ssh" {
  name        = "${var.project_name}-allow-http-ssh"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main_vpc.id # Correct dependency on VPC

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-sg-http-ssh" })
  # No complex dependencies needed to fix here, primary fix was the route's depends_on.
  # Ensuring this SG is created after network path is stable is good practice if it had
  # rules dependent on network resources being fully up.
  depends_on = [
    aws_route.public_route_to_igw // Ensure network path is defined before SG might be used by an EC2 instance.
                                  // While not strictly necessary for SG creation itself, it's good for dependent resources.
  ]
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main_vpc.id
}
output "public_subnet_id" {
  value = aws_subnet.public_subnet.id
}
output "igw_id" {
  value = aws_internet_gateway.gw.id
}
output "route_table_id" {
  value = aws_route_table.public_route_table.id
}
output "security_group_id" {
  value = aws_security_group.allow_http_ssh.id
}
output "igw_attachment_id" { # Changed from status to id for clarity
  value = aws_internet_gateway_attachment.gw_attachment.id
}
EOF_MAIN_TF_FIXED

echo "INFO: $MAIN_TF_FILE has been updated with fixes."
echo "To test the fix:"
echo "  cd $INFRA_DIR"
echo "  terraform init"
echo "  terraform validate"
echo "  terraform apply"
echo "  terraform destroy"

# The verify.sh script will automate these TF actions.
exit 0
