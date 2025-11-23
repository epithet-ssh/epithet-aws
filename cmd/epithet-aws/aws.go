package main

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/epithet-ssh/epithet-aws/pkg/s3archiver"
	"github.com/epithet-ssh/epithet/pkg/ca"
	"github.com/epithet-ssh/epithet/pkg/caserver"
	"github.com/epithet-ssh/epithet/pkg/policyserver"
	policyconfig "github.com/epithet-ssh/epithet/pkg/policyserver/config"
	"github.com/epithet-ssh/epithet/pkg/policyserver/evaluator"
	"github.com/epithet-ssh/epithet/pkg/sshcert"
)

type AwsCALambdaCLI struct {
	SecretArn         string `help:"ARN of Secrets Manager secret containing CA private key" env:"CA_SECRET_ARN" required:"true"`
	PolicyURL         string `help:"URL of policy validation service" env:"POLICY_URL" required:"true"`
	CertArchiveBucket string `help:"S3 bucket for certificate archival (optional)" env:"CERT_ARCHIVE_BUCKET"`
	CertArchivePrefix string `help:"S3 key prefix for certificate archival (optional)" env:"CERT_ARCHIVE_PREFIX" default:"certs"`
}

type AwsPolicyLambdaCLI struct {
	CAPublicKeyParam string `help:"SSM parameter name containing CA public key" env:"CA_PUBLIC_KEY_PARAM" required:"true"`
}

func (a *AwsCALambdaCLI) Run(logger *slog.Logger) error {
	logger.Info("starting CA Lambda handler", "policy_url", a.PolicyURL)

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		return fmt.Errorf("failed to load AWS config: %w", err)
	}

	smClient := secretsmanager.NewFromConfig(cfg)
	result, err := smClient.GetSecretValue(context.Background(), &secretsmanager.GetSecretValueInput{
		SecretId: &a.SecretArn,
	})
	if err != nil {
		return fmt.Errorf("failed to retrieve secret: %w", err)
	}

	privateKey := *result.SecretString
	if privateKey == "" {
		return fmt.Errorf("CA private key not set in secret")
	}

	caInstance, err := ca.New(sshcert.RawPrivateKey(privateKey), a.PolicyURL)
	if err != nil {
		return fmt.Errorf("failed to create CA: %w", err)
	}

	certLogger := a.createCertLogger(cfg, logger)
	handler := caserver.New(caInstance, logger, &http.Client{}, certLogger)

	logger.Info("CA Lambda initialized successfully")

	lambda.Start(func(ctx context.Context, request events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
		return handleLambdaRequest(ctx, request, handler, logger)
	})

	return nil
}

func (a *AwsCALambdaCLI) createCertLogger(cfg aws.Config, logger *slog.Logger) caserver.CertLogger {
	slogLogger := caserver.NewSlogCertLogger(logger)

	if a.CertArchiveBucket == "" {
		logger.Info("certificate archival disabled (no S3 bucket configured)")
		return slogLogger
	}

	s3Client := s3.NewFromConfig(cfg)
	s3Archiver := s3archiver.NewS3CertArchiver(s3archiver.S3ArchiverConfig{
		S3Client:   s3Client,
		Bucket:     a.CertArchiveBucket,
		KeyPrefix:  a.CertArchivePrefix,
		Logger:     logger,
		BufferSize: 100,
	})

	logger.Info("certificate archival enabled",
		"bucket", a.CertArchiveBucket,
		"prefix", a.CertArchivePrefix)

	return &certLoggerAdapter{
		slogLogger: slogLogger,
		s3Archiver: s3Archiver,
	}
}

func (a *AwsPolicyLambdaCLI) Run(logger *slog.Logger) error {
	logger.Info("starting policy Lambda handler")

	// Load policy configuration from bundled file
	configPath := "/var/task/policy.yaml"
	cfg, err := policyconfig.LoadFromFile(configPath)
	if err != nil {
		return fmt.Errorf("failed to load policy config: %w", err)
	}

	logger.Info("policy configuration loaded",
		"users", len(cfg.Users),
		"hosts", len(cfg.Hosts),
		"oidc_issuer", cfg.OIDC.Issuer,
		"oidc_audience", cfg.OIDC.Audience)

	// Load CA public key from SSM Parameter Store
	awsCfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		return fmt.Errorf("failed to load AWS config: %w", err)
	}

	ssmClient := ssm.NewFromConfig(awsCfg)
	result, err := ssmClient.GetParameter(context.Background(), &ssm.GetParameterInput{
		Name: &a.CAPublicKeyParam,
	})
	if err != nil {
		return fmt.Errorf("failed to retrieve CA public key: %w", err)
	}

	caPublicKey := *result.Parameter.Value
	if caPublicKey == "" || caPublicKey == "placeholder - run make setup-ca-key to populate" {
		return fmt.Errorf("CA public key not set - run 'make setup-ca-key' first")
	}

	logger.Info("CA public key loaded from SSM Parameter Store")

	ctx := context.Background()
	eval, err := evaluator.New(ctx, cfg)
	if err != nil {
		return fmt.Errorf("failed to create policy evaluator: %w", err)
	}

	handler := policyserver.NewHandler(policyserver.Config{
		CAPublicKey: sshcert.RawPublicKey(caPublicKey),
		Evaluator:   eval,
	})

	logger.Info("policy Lambda initialized successfully")

	lambda.Start(func(ctx context.Context, request events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
		return handleLambdaRequest(ctx, request, handler, logger)
	})

	return nil
}

func handleLambdaRequest(ctx context.Context, request events.APIGatewayV2HTTPRequest, handler http.Handler, logger *slog.Logger) (events.APIGatewayV2HTTPResponse, error) {
	req, err := http.NewRequestWithContext(ctx, request.RequestContext.HTTP.Method, request.RawPath, nil)
	if err != nil {
		logger.Error("failed to create request", "error", err)
		return events.APIGatewayV2HTTPResponse{
			StatusCode: 500,
			Body:       "Internal server error",
		}, nil
	}

	for k, v := range request.Headers {
		req.Header.Set(k, v)
	}

	if request.Body != "" {
		req.Body = io.NopCloser(strings.NewReader(request.Body))
		req.ContentLength = int64(len(request.Body))
	}

	rw := &lambdaResponseWriter{
		headers: make(http.Header),
		body:    make([]byte, 0),
	}

	handler.ServeHTTP(rw, req)

	headers := make(map[string]string)
	for k, v := range rw.headers {
		if len(v) > 0 {
			headers[k] = v[0]
		}
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: rw.statusCode,
		Headers:    headers,
		Body:       string(rw.body),
	}, nil
}

type lambdaResponseWriter struct {
	headers    http.Header
	body       []byte
	statusCode int
}

func (w *lambdaResponseWriter) Header() http.Header {
	return w.headers
}

func (w *lambdaResponseWriter) Write(b []byte) (int, error) {
	w.body = append(w.body, b...)
	if w.statusCode == 0 {
		w.statusCode = 200
	}
	return len(b), nil
}

func (w *lambdaResponseWriter) WriteHeader(statusCode int) {
	w.statusCode = statusCode
}

type certLoggerAdapter struct {
	slogLogger *caserver.SlogCertLogger
	s3Archiver *s3archiver.S3CertArchiver
}

func (c *certLoggerAdapter) LogCert(ctx context.Context, event *caserver.CertEvent) error {
	if err := c.slogLogger.LogCert(ctx, event); err != nil {
		return err
	}

	s3Event := &s3archiver.CertEvent{
		Timestamp:            event.Timestamp,
		SerialNumber:         event.SerialNumber,
		Identity:             event.Identity,
		Principals:           event.Principals,
		RemoteHost:           event.Connection.RemoteHost,
		RemoteUser:           event.Connection.RemoteUser,
		Port:                 int(event.Connection.Port),
		Hash:                 string(event.Connection.Hash),
		ProxyJump:            event.Connection.ProxyJump,
		ValidAfter:           event.ValidAfter,
		ValidBefore:          event.ValidBefore,
		Extensions:           event.Extensions,
		PublicKeyFingerprint: event.PublicKeyFingerprint,
		HostPattern:          "",
	}

	return c.s3Archiver.LogCert(ctx, s3Event)
}
