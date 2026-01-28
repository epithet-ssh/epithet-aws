.PHONY: build clean init plan apply destroy setup-ca-key build-lambda download-binary build-ca build-policy test

# Epithet version to use
EPITHET_VERSION := v0.6.3
EPITHET_ARCH := linux_arm64
EPITHET_URL := https://github.com/epithet-ssh/epithet/releases/download/$(EPITHET_VERSION)/epithet_$(subst v,,$(EPITHET_VERSION))_$(EPITHET_ARCH).tar.gz

# Download the epithet binary
download-binary:
	@echo "Downloading epithet $(EPITHET_VERSION) for $(EPITHET_ARCH)..."
	@mkdir -p bin
	@curl -sL "$(EPITHET_URL)" | tar xz -C bin epithet
	@chmod +x bin/epithet
	@echo "Downloaded bin/epithet"

# Build CA Lambda package
build-ca: download-binary
	@echo "Building CA Lambda package..."
	@mkdir -p bin/ca-package
	@cp bin/epithet bin/ca-package/epithet
	@cp scripts/ca-launcher.sh bin/ca-package/bootstrap
	@chmod +x bin/ca-package/bootstrap
	@cd bin/ca-package && zip -q ../ca.zip epithet bootstrap
	@rm -rf bin/ca-package
	@echo "Created bin/ca.zip"

# Build Policy Lambda package
build-policy: download-binary
	@echo "Building Policy Lambda package..."
	@mkdir -p bin/policy-package
	@cp bin/epithet bin/policy-package/epithet
	@cp scripts/policy-launcher.sh bin/policy-package/bootstrap
	@chmod +x bin/policy-package/bootstrap
	@find config/policy -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.cue' -o -name '*.json' \) -exec cp {} bin/policy-package/ \;
	@cd bin/policy-package && zip -q ../policy.zip *
	@rm -rf bin/policy-package
	@echo "Created bin/policy.zip"

# Build both Lambda packages
build-lambda: build-ca build-policy
	@echo "Lambda packages created in bin/"

# Alias for backward compatibility
build: build-lambda

# Clean build artifacts
clean:
	rm -rf bin/

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

# Validate launcher scripts
test:
	@echo "Validating launcher scripts..."
	@bash -n scripts/ca-launcher.sh
	@bash -n scripts/policy-launcher.sh
	@echo "Scripts are valid"
