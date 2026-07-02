resource "aws_lb" "edge" {
  name                             = "${var.project_name}-edge"
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = [for subnet in aws_subnet.public : subnet.id]
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-edge"
  }
}

resource "aws_lb_target_group" "http" {
  name        = "${var.project_name}-http"
  port        = 80
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "80"
  }

  tags = {
    Name = "${var.project_name}-http"
  }
}

resource "aws_lb_target_group" "https" {
  name        = "${var.project_name}-https"
  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "443"
  }

  tags = {
    Name = "${var.project_name}-https"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.edge.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.edge.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

resource "aws_lb_target_group_attachment" "http_workers" {
  for_each = aws_instance.workers

  target_group_arn = aws_lb_target_group.http.arn
  target_id        = each.value.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "https_workers" {
  for_each = aws_instance.workers

  target_group_arn = aws_lb_target_group.https.arn
  target_id        = each.value.id
  port             = 443
}
