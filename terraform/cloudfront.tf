# CloudFront distribution for caching discovery endpoint

# Cache policy that respects origin Cache-Control headers
resource "aws_cloudfront_cache_policy" "discovery" {
  name    = "${local.name_prefix}-discovery-cache"
  comment = "Cache policy for epithet discovery - respects origin Cache-Control"

  # TTL configuration - respect origin headers
  min_ttl     = 0          # Respect Cache-Control: no-cache
  default_ttl = 86400      # 24h default if no Cache-Control header
  max_ttl     = 31536000   # 1 year max for immutable content

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# CloudFront distribution for discovery endpoint
resource "aws_cloudfront_distribution" "discovery" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Epithet policy discovery endpoint"
  price_class     = "PriceClass_100" # US/EU only for cost savings

  origin {
    domain_name = replace(aws_apigatewayv2_api.policy.api_endpoint, "https://", "")
    origin_id   = "policy-api-gateway"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Discovery endpoint - GET /d/* with caching
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "policy-api-gateway"

    cache_policy_id          = aws_cloudfront_cache_policy.discovery.id
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader

    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}
