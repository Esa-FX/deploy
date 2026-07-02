resource "aws_lb" "api" {
  name               = "${local.name_prefix}-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-api-alb" })
}

resource "aws_lb_target_group" "identity" {
  name     = "${local.name_prefix}-identity"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "crm_api" {
  name     = "${local.name_prefix}-crm-api"
  port     = 8001
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "client" {
  name     = "${local.name_prefix}-client"
  port     = 8002
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.common_tags
}

resource "aws_lb_target_group_attachment" "identity" {
  target_group_arn = aws_lb_target_group.identity.arn
  target_id        = aws_instance.core.id
  port             = 8000
}

resource "aws_lb_target_group_attachment" "crm_api" {
  target_group_arn = aws_lb_target_group.crm_api.arn
  target_id        = aws_instance.crm.id
  port             = 8001
}

resource "aws_lb_target_group_attachment" "client" {
  target_group_arn = aws_lb_target_group.client.arn
  target_id        = aws_instance.crm.id
  port             = 8002
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.identity.arn
  }
}

resource "aws_lb_listener_rule" "staff" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.identity.arn
  }

  condition {
    path_pattern { values = ["/staff", "/staff/*"] }
  }
}

resource "aws_lb_listener_rule" "crm" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.crm_api.arn
  }

  condition {
    path_pattern { values = ["/api/v1/crm/*"] }
  }
}

resource "aws_lb_listener_rule" "intake" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 15

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.crm_api.arn
  }

  condition {
    path_pattern { values = ["/api/v1/intake", "/api/v1/intake/*"] }
  }
}

resource "aws_lb_listener_rule" "client" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.client.arn
  }

  condition {
    path_pattern { values = ["/api/v1/client/*"] }
  }
}

resource "aws_lb_listener_rule" "users" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.identity.arn
  }

  condition {
    path_pattern { values = ["/users/*", "/internal/*"] }
  }
}

resource "aws_lb_listener_rule" "ws" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.crm_api.arn
  }

  condition {
    path_pattern { values = ["/ws", "/ws/*"] }
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
