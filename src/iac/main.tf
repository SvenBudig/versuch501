resource "aws_s3_bucket_public_access_block" "app_bucket_block" {
  bucket = "my-app-bucket"
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Security group for app"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/24"]
  }
}
