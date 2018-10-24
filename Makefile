# Constants
SHELL := /bin/bash
env ?= dev
.DEFAULT_GOAL := clean
.EXPORT_ALL_VARIABLES:
ENCRYPTED_TFVARS := 

# check for terraform - if not present, abort Make
$(if $(shell which terraform),$(eval TF_EXEC := $(shell which terraform)),$(error Executable 'terraform' not found))

# check for ansible-vault - if not present, skip encrypted files
VAULT_EXEC := null
$(if $(shell which ansible-vault 2>/dev/null),$(eval VAULT_EXEC := $(shell which ansible-vault)),$(info Executable 'ansible-vault' not found - skipping decryption))

# Extract the service name from the make commandline
$(eval SERVICE_NAME := $(shell CN=`echo ${MAKECMDGOALS} | cut -d'.' -f1`; echo $$CN))

# Import 'global' config and service-specific config (if it exists)
include \
	$(shell [ -f config.mk ] && echo config.mk) \
	$(shell [ -f config-$(env).mk ] && echo config-$(env).mk) \
	$(shell [ -f $(SERVICE_NAME)/config.mk ] && echo $(SERVICE_NAME)/config.mk) \
	$(shell [ -f $(SERVICE_NAME)/config-$(env).mk ] && echo $(SERVICE_NAME)/config-$(env).mk)

# Available debug levels: TRACE, DEBUG, INFO, WARN, ERROR
TF_LOG ?= WARN

# assign default variable values
REGION ?= europe-west2
PROJECT ?= my-project-id
TFSTATE_FILE := $(PROJECT)-$(env)-$(SERVICE_NAME)
TFPLAN_FILE := /tmp/$(TFSTATE_FILE)-tf.plan

# Expose relevant Make variables to Terraform
TF_VAR_env := $(env)
TF_VAR_project := $(PROJECT)
TF_VAR_region := $(REGION)
TF_VAR_tfstate_bucket := $(PROJECT)-tfstate
TF_VAR_docker_registry := gcr.io/$(PROJECT)

clean:
	@rm -f *.terraform
	@rm -f $(*)/*.terraform
	@rm -f $(*)/terraform*

%.check: 
	@# Check that the specified service exists
	@if [[ ! -d ./$(SERVICE_NAME) ]]; then \
		echo "ERROR: Component [$(SERVICE_NAME)] does not exist."; \
		exit 1; \
	fi

%.decrypt-ansible:
	VAULT_PASSWORD_OVERRIDE ?= null
	$(if $(filter $(VAULT_PASSWORD_OVERRIDE),null), \
		$(eval VAULT_PASSWORD := $(shell read -s -p "Vault password: " PASSWORD; echo $${PASSWORD})), \
		$(eval VAULT_PASSWORD := $(VAULT_PASSWORD_OVERRIDE)))
	@echo # newline to sanitise output

	@# Check for the various potential encrypted files, and gather all outputs
	$(eval ENCRYPTED_TFVARS := $(shell contents secrets.tfvars $(VAULT_PASSWORD)))
	$(eval ENCRYPTED_TFVARS := $(shell contents secrets-$(env).tfvars $(VAULT_PASSWORD)))
	$(eval ENCRYPTED_TFVARS := $(ENCRYPTED_TFVARS) $(shell contents $(SERVICE_NAME)/secrets.tfvars $(VAULT_PASSWORD)))
	$(eval ENCRYPTED_TFVARS := $(ENCRYPTED_TFVARS) $(shell contents $(SERVICE_NAME)/secrets-$(env).tfvars $(VAULT_PASSWORD)))

	@# Decrypt state-file encryption key if present
	$(eval TF_STATE_ENCRYPTION_KEY := $(shell contents encryption-key.vault $(VAULT_PASSWORD)))

ifeq ($(VAULT_EXEC),null)
%.init: clean %.check 
else
%.init: clean %.check %.decrypt-ansible
endif
	$(TF_EXEC) fmt
	@cd $(SERVICE_NAME); \
		TF_PLUGIN_CACHE_DIR="$(HOME)/.terraform.d/plugin-cache" \
			$(TF_EXEC) init \
				-backend=true \
				-get=true \
				-upgrade=true \
				-backend-config="bucket=$(TF_VAR_tfstate_bucket)" \
				-backend-config="prefix=$(TFSTATE_FILE)" \
				$(if $(filter $(TF_STATE_ENCRYPTION_KEY),),$(shell echo -backend-config="encryption_key=$(TF_STATE_ENCRYPTION_KEY)"),) \
				-backend-config="project=$(PROJECT)"				

%.plan: %.init
	@cd $(SERVICE_NAME); $(TF_EXEC) plan \
		-var-file=<(echo $${ENCRYPTED_TFVARS}) \
		$(if $(filter $(TF_STATE_ENCRYPTION_KEY),),$(shell echo -var 'remote_state_encryption_key=$(TF_STATE_ENCRYPTION_KEY)'),) \
		-module-depth=-1 \
		-refresh=true \
		-out=$(TFPLAN_FILE)

%.apply: clean %.check
	@cd $(SERVICE_NAME); $(TF_EXEC) apply $(TFPLAN_FILE) && rm -f $(TFPLAN_FILE)

%.destroy: %.variables
	@cd $(SERVICE_NAME); $(TF_EXEC) destroy \
		-var-file=<(echo $${ENCRYPTED_TFVARS}) \
		$(if $(filter $(TF_STATE_ENCRYPTION_KEY),),$(shell echo -var 'remote_state_encryption_key=$(TF_STATE_ENCRYPTION_KEY)'),) \
		-auto-approve    

%.import: %.init
	@: $${tf_sig?The runtime variable 'tf_sig' is required.  It should contain the terraform signature of the target resource.}
	@: $${id?The runtime variable 'id' is required. It should contain the environment resource id of the target resource.}

	@cd $(SERVICE_NAME); $(TF_EXEC) import \
		-var-file=<(echo $${ENCRYPTED_TFVARS}) \
		$(if $(filter $(TF_STATE_ENCRYPTION_KEY),),$(shell echo -var 'remote_state_encryption_key=$(TF_STATE_ENCRYPTION_KEY)'),) \
		$(tf_sig) $(id)    


