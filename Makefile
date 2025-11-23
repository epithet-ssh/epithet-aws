.PHONY: build clean init plan apply destroy setup-ca-key build-lambda

# Build the epithet-aws binary
build:
	@echo "Building epithet-aws binary..."
	go build -o epithet-aws ./cmd/epithet-aws

# Build Lambda function for deployment
build-lambda:
	@echo "Building Lambda functions (linux/arm64)..."
	@mkdir -p bin
	GOOS=linux GOARCH=arm64 go build -tags lambda.norpc -o bin/bootstrap ./cmd/epithet-aws
	@cd bin && zip -q bootstrap-ca.zip bootstrap
	@cd bin && zip -qj bootstrap-policy.zip bootstrap ../config/policy/*
	@rm bin/bootstrap
	@echo "Lambda packages created in bin/"

# Alias for build-lambda
ca-lambda: build-lambda
policy-lambda: build-lambda

# Clean build artifacts
clean:
	rm -rf bin/
	rm -f epithet-aws

# Initialize OpenTofu/Terraform
init:
	cd terraform && tofu init

# Plan infrastructure changes
plan: build-lambda
	cd terraform && tofu plan

# Apply infrastructure changes
apply: build-lambda
	cd terraform && tofu apply

# Destroy infrastructure
destroy:
	cd terraform && tofu destroy

# Generate CA key and upload to Secrets Manager
setup-ca-key:
	@echo "Generating CA key..."
	@./scripts/generate-ca-key.sh

# Run tests
test:
	go test ./...

# Install locally
install: build
	@echo "Installing epithet-aws to /usr/local/bin..."
	sudo cp epithet-aws /usr/local/bin/
