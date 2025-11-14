resource "aws_s3_bucket_public_access_block" "app_bucket_block" {
  bucket = "my-app-bucket"
  
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Security group for app"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}